extends RefCounted

## The rows of "What moves it" -- V5.3 screen 4, the goal panel. One row per measure GoalRead.rank
## returns for the picked goal, best first: what kind of measure it is, its name, what it does to
## the goal, and either whether the Assembly would pass it or, greyed, why it cannot be tabled now.
## The figures are the read's own (goal_read.gd); this file words them and never derives one.
##
## Honest labels, section 11's: the balance is "a year, at today's economy"; a bloc's support and
## unemployment are where they are HEADING (the target the measure moves them to), never "in two
## years". A measure the read cannot size for the goal is listed with "not read here".

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Labels = preload("res://src/ui/labels.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")

## The rows shown before "Show all": the best few are what the player acts on, and a list of every
## measure on the page is the text the author asked to be rid of (tests/test_prose_budget.gd).
const SHOWN := 8
const KIND_WIDTH := 52.0
const EFFECT_WIDTH := 124.0
const STATE_WIDTH := 150.0


## What a goal's figures mean, said once above the list.
static func caption_of(goal: String) -> String:
	if goal == "deficit":
		return Strings.t("The balance a year, at today's economy, if it passed.")
	if goal == "unemployment":
		return Strings.t("Where the unemployment rate is heading if it passed.")
	if goal.begins_with("field:"):
		return Strings.t("A promise on the books, read through the figure it names.")
	return Strings.t("Where this bloc's support is heading if it passed.")


## Fills `box` with one row per entry of `rows` (GoalRead.rank's), the best SHOWN of them unless
## `all`; `pick` is called with the row's measure when it is pressed, `more` when "Show all" is.
static func build(box: Control, rows: Array, goal: String, state, find_law: Callable, pick: Callable, all: bool, more: Callable) -> void:
	if rows.is_empty():
		PanelKit.line(box, Strings.t("Nothing open to propose moves this."), PanelKit.Tone.DIM)
		return
	if bool(rows[0].get("no_read", false)):
		PanelKit.line(box, Strings.t("Not read here: run the forecast."), PanelKit.Tone.DIM)
		return
	for i in rows.size() if all else mini(SHOWN, rows.size()):
		box.add_child(_row(rows[i], goal, state.player(), find_law, pick))
	if not all and rows.size() > SHOWN:
		var button := PanelKit.sized(Button.new())
		button.text = Strings.t("Show all %d") % rows.size()
		button.pressed.connect(more)
		box.add_child(button)


static func _row(row: Dictionary, goal: String, ns, find_law: Callable, pick: Callable) -> Control:
	var measure: Dictionary = row["measure"]
	var greyed := String(row.get("table", "")) != ""
	var press := Button.new()
	press.flat = true
	press.custom_minimum_size.y = 30.0 * UiTheme.text_scale()
	press.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	press.tooltip_text = _tip(row)
	press.pressed.connect(pick.bind(measure))
	var cells := HBoxContainer.new()
	cells.set_anchors_preset(Control.PRESET_FULL_RECT)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.add_theme_constant_override("separation", 10)
	press.add_child(cells)
	var kind := _cell(cells, _kind_word(measure), UiTheme.MICRO, KIND_WIDTH)
	var title := _cell(cells, _name_of(measure, ns, find_law), UiTheme.CAPTION if greyed else "", 0.0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var effect := _cell(cells, _effect_text(row, goal), _effect_tone(row, goal, greyed), EFFECT_WIDTH)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var state := _cell(cells, _state_text(row, greyed), _state_tone(row, greyed), STATE_WIDTH)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return press


static func _cell(parent: Control, text: String, variation: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.custom_minimum_size.x = width * UiTheme.text_scale()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


static func _kind_word(measure: Dictionary) -> String:
	match String(measure["kind"]):
		"law":
			return Strings.t("Law")
		"line":
			return Strings.t("Budget")
	return Strings.t("Tax")


static func _name_of(measure: Dictionary, ns, find_law: Callable) -> String:
	match String(measure["kind"]):
		"law":
			var id := String(measure["id"])
			return Strings.law_name(find_law.call(id), id)
		"line":
			return Strings.t("%s %s pt of GDP") % [Strings.t(BudgetPanel.LEVER_LABELS[String(measure["key"])]), Num.fs(float(measure["step"]), 1)]
	var kind := String(measure["key"])
	return "%s %s" % [Strings.row_name("taxes", ns.tax_library[kind]), Num.fs(float(measure["step"]), TaxLibrary.step_decimals(ns, kind))]


## The goal's figure. `effect` is signed so more is better for the goal (goal_read.gd).
static func _effect_text(row: Dictionary, goal: String) -> String:
	if not bool(row.get("read", true)):
		return Strings.t("not read here")
	var effect := float(row["effect"])
	if goal == "deficit":
		return Strings.t("%s bn a year") % Num.fs(effect, 1)
	if goal == "unemployment":
		return Strings.t("%s pt") % Num.fs(-effect, 2)
	return Strings.t("%s pt") % Num.fs(effect, 2)


static func _effect_tone(row: Dictionary, _goal: String, greyed: bool) -> String:
	if greyed or not bool(row.get("read", true)):
		return UiTheme.CAPTION
	return UiTheme.GOOD_TEXT if float(row["effect"]) > 0.0 else UiTheme.BAD_TEXT


## The right cell: why it cannot be tabled now (greyed), else the Assembly's reading, with a
## word as well as a tone.
static func _state_text(row: Dictionary, greyed: bool) -> String:
	if greyed:
		return reason_text(String(row["table"]))
	return Strings.t("would pass") if bool(row["passes"]) else Strings.t("would fail")


static func _state_tone(row: Dictionary, greyed: bool) -> String:
	if greyed:
		return UiTheme.CAPTION
	return UiTheme.GOOD_SMALL if bool(row["passes"]) else UiTheme.BAD_SMALL


## The refusal flags GoalRead hands back (Legislature.refusal's and FinanceBill.refusal's), in words.
static func reason_text(flag: String) -> String:
	match flag:
		"already_tabled":
			return Strings.t("A bill is before the Assembly: queue it.")
		"finance_queued":
			return Strings.t("A budget text is already queued.")
		"referendum_in_flight":
			return Strings.t("A referendum is in flight.")
		"unavailable":
			return Strings.t("Not open to propose now.")
		"range":
			return Strings.t("Outside the tax's range.")
		"verb":
			return Strings.t("A row of the bill is not legal now.")
	return Strings.t("It cannot be tabled now.")


## The hover: the balance the measure books a year, which the goal's own figure leaves out
## unless the goal is the deficit.
static func _tip(row: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append(Strings.t("Balance: %s bn a year, at today's economy.") % Num.fs(float(row["cost_bn"]), 1))
	if String(row.get("table", "")) != "":
		parts.append(reason_text(String(row["table"])))
	return "\n".join(parts)
