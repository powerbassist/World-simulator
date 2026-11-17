extends RefCounted

## One law on its shelf -- the Bills second pass (the author's "A : les rayons"). The row says
## what the law changes before the player opens it: its name and its verb ("raises", from the
## data, never guessed), its summary whole, and the vote as a small bar with the counts for and
## against. A law the Assembly cannot take now keeps its row and says WHY in the warning tone --
## the sim's own rule (law_gate.gd), never a tooltip -- and a law already on the order paper says
## which vote it is in. law_list.gd owns the list and the selection; this file lays one row out.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const LawGate = preload("res://src/sim/law_gate.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const BillActions = preload("res://src/ui/bill_actions.gd")

## The vote bar's width on a row, px.
const BAR_WIDTH := 150.0


static func build(list, ns, party_list: Array, law, selected: bool, flag: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.set_meta("law_id", String(law.id))
	# PASS, not STOP: the row hears its click and the list's scroll still hears the wheel.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.gui_input.connect(func(event: InputEvent) -> void:
		var press := event as InputEventMouseButton
		if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
			list.select(String(law.id)))
	row.gui_input.connect(BillActions.row_input.bind(list, law))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	row.add_child(top)
	var pick := Button.new()
	pick.text = Strings.law_name(law)
	pick.tooltip_text = pick.text
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.toggle_mode = true
	pick.flat = not selected
	pick.button_pressed = selected
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.pressed.connect(list.select.bind(String(law.id)))
	pick.gui_input.connect(BillActions.row_input.bind(list, law))
	top.add_child(pick)
	row.set_meta("pick", pick)
	var verb := Strings.law_verb(list._panel._loader, law)
	if verb != "":
		var word := Label.new()
		word.text = verb.to_upper()
		word.theme_type_variation = UiTheme.MICRO
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(word)
	if flag == "":
		top.add_child(_vote(list, ns, party_list, law))
	PanelKit.line(row, Strings.law_summary(law))
	var why := shut_text(ns, law, flag) if flag != "" else _paper_text(list, law)
	if why != "":
		var line := Label.new()
		line.text = why
		line.theme_type_variation = UiTheme.WARN_TEXT
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(line)
	return row


## The vote at a glance: the forecast bar, and the counts under it.
static func _vote(list, ns, party_list: Array, law) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size.x = BAR_WIDTH * UiTheme.text_scale()
	var c: Dictionary = list.counts_of(ns, party_list, law)
	box.add_child(list._forecast_bar(ns, party_list, law, BAR_WIDTH, c))
	var counts := Label.new()
	counts.text = Strings.t("%d for · %d against") % [c["yes"], c["no"]]
	counts.theme_type_variation = UiTheme.CAPTION
	box.add_child(counts)
	return box


## Where an open law stands on the order paper: in this month's vote, or queued for a month.
static func _paper_text(list, law) -> String:
	var panel = list._panel
	var cells := BillVerbs.cells(panel._state, panel._loader, String(law.id), panel._find_law)
	if cells["slot"] == "here":
		return Strings.t("In %s's vote.") % DateText.month_long(int(panel._state.player().tabled_bill.get("vote_month", panel._state.month)))
	if int(cells["queued"]) >= 0:
		return Strings.t("Queued for %s.") % BillVerbs.month_name(panel._state, int(cells["queued"]))
	return ""


## Why the Assembly cannot take `law` now, in the player's words: the gate's flag
## (law_gate.gd) made a sentence. A flag this table does not know reads as a plain refusal.
static func shut_text(ns, law, flag: String) -> String:
	match flag:
		LawGate.PASSED:
			return Strings.t("Passed, and it can pass only once.")
		LawGate.COOLDOWN:
			var months := int(ns.law_cooldown_months.get(law.id, 0))
			return Strings.tn("Voted on recently: it can come back in %d month.", "Voted on recently: it can come back in %d months.", months) % months
		LawGate.NOTHING_TO_REPEAL:
			return Strings.t("Nothing to repeal: the law it undoes is not in force.")
		LawGate.IN_FORCE:
			return Strings.t("Already the rule: the electoral method it sets is in force.")
		LawGate.REFERENDUM:
			return Strings.t("Put to the country: the referendum is under way.")
		LawGate.HELD:
			return Strings.t("Carried, and held by the second chamber.")
		LawGate.ASSEMBLY:
			return Strings.t("The Assembly's own bill: it is already before the Assembly.")
		LawGate.CONDITIONS:
			return Strings.t("Its conditions are not met yet.")
	return Strings.t("The Assembly cannot take it now.")
