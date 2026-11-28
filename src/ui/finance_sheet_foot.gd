extends HBoxContainer

## The foot of the finance bill's document (finance_sheet.gd): the verdict at the left -- how the Assembly would
## divide on the draft now, or the censure a forced passage would meet, or why it cannot be tabled -- with the force
## box under it; the verbs at the right, one row, bottom-aligned: Discard all (Withdraw the bill while one is at
## vote), Close, and the ONE filled verb. The states and their tones are Design's table (c-build.md sections 3, 4):
## a refusal is red when nothing can be pressed and amber when a verb is still live, and wears the warning glyph;
## the queue's note is red, and said first, only when it is a cause; the verdict's words are toned and bare.
##
## It computes nothing of its own: the division is FinanceRead.draft's, the censure Government.resolve_censure's (the
## Government window's own tally), and whether a passage can be forced is the very rule tabling meets
## (FinanceBill.refusal with the force flag), never a nation id.

signal table_pressed(force: bool)
signal discard_pressed
signal withdraw_pressed
signal close_pressed

const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const FinanceQueue = preload("res://src/ui/finance_queue.gd")
const FinanceRefusal = preload("res://src/ui/finance_refusal.gd")
const Government = preload("res://src/sim/government.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const Strings = preload("res://src/ui/strings.gd")

const WARNING := "res://assets/icons/material/warning.svg"
## The Assembly's bar at text 100.
const BAR_W := 360.0

var _state
var _loader
var _draft
var _read := {}
var _lines: VBoxContainer
var _verbs: HBoxContainer
var _force: CheckBox
## Where Tab goes after the last verb: the document's first control.
var _first: Control


## Call once, after add_child(): `ticked` is the force box as the rebuilt document left it.
func build(state, loader, draft, read: Dictionary, first: Control, ticked: bool) -> void:
	_state = state
	_loader = loader
	_draft = draft
	_read = read
	_first = first
	add_theme_constant_override("separation", 24)
	var verdict := VBoxContainer.new()
	verdict.add_theme_constant_override("separation", 6)
	verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(verdict)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	verdict.add_child(_lines)
	# The very rule tabling meets: a refusal for another reason says so, and a system with no forced passage says "forced".
	var can_force: bool = String(read["refusal"]) == "" and not FinanceBill.refusal(state, loader, draft.bill(), true).has("forced")
	if can_force:
		_force = CheckBox.new()
		_force.name = "Force"  # i18n: ok a node name, found by tests
		_force.text = Strings.t("Force it through (49.3)")
		_force.theme_type_variation = UiTheme.OPTION_CHECK
		_force.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_force.set_pressed_no_signal(ticked)
		_force.toggled.connect(_fill)
		verdict.add_child(_force)
	_verbs = HBoxContainer.new()
	_verbs.add_theme_constant_override("separation", PanelKit.BUTTON_SEPARATION)
	_verbs.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(_verbs)
	_fill(ticked and can_force)


func force_ticked() -> bool:
	return _force != null and _force.button_pressed


## The part the force box changes: the division (or the censure) and the verbs.
func _fill(forced: bool) -> void:
	for box in [_lines, _verbs]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var refusal := String(_read["refusal"])
	var queue: Dictionary = FinanceQueue.verb(_state, _loader, refusal, _draft.bill())
	var live := bool(queue.get("enabled", false))
	if refusal != "":
		var held := _refusal_line(FinanceRefusal.reason(refusal), not live)
		if queue.has("cause"):
			_lines.move_child(_refusal_line(String(queue["note"]), true), held.get_index())
		elif queue.has("note"):
			_small(_lines, String(queue["note"]))
	elif forced:
		_censure(_state.player())
	else:
		_assembly(_read["vote"])
	_fill_verbs(refusal, forced, queue, live)


## A refusal said with its glyph: red when nothing can be pressed, amber beside a live verb.
func _refusal_line(text: String, bad: bool) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.set_meta("refusal", "bad" if bad else "warn")
	var px := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
	var glyph := TextureRect.new()
	glyph.texture = Icon.load_icon(WARNING, UiTheme.BAD if bad else UiTheme.WARN, px)
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	glyph.custom_minimum_size = Vector2(px, px)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(glyph)
	var words := PanelKit.plain_line(line, text)
	words.theme_type_variation = UiTheme.BAD_SMALL if bad else UiTheme.WARN_TEXT
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_child(line)
	return line


## The verdict's small plain cut (the type scale's 13, untoned).
func _small(box: Control, text: String) -> Label:
	var label := PanelKit.plain_line(box, text)
	label.theme_type_variation = UiTheme.CHIP_TEXT
	return label


func _toned(box: Control, text: String, good: bool) -> Label:
	var label := PanelKit.plain_line(box, text)
	label.theme_type_variation = UiTheme.GOOD_SMALL if good else UiTheme.BAD_SMALL
	return label


func _censure(ns) -> void:
	var censure: Dictionary = Government.resolve_censure(ns, _loader.parties.get(ns.id, []), true)
	_small(_lines, Strings.t("Adopted without a vote. A censure motion follows: %d seats would move against the government, %d are needed.") % [
		int(censure["for_seats"]), Government.censure_seats(ns)])
	var survives := not bool(censure["carried"])
	_toned(_lines, Strings.t("It survives: the bill is adopted.") if survives else Strings.t("It falls: the government goes and the bill with it."), survives)
	PanelKit.plain_line(_lines, Strings.t("Forcing costs standing with every bloc and with your own majority.")).theme_type_variation = UiTheme.CAPTION


func _assembly(vote: Dictionary) -> void:
	var bar := VBoxContainer.new()
	bar.custom_minimum_size.x = BAR_W * UiTheme.text_scale()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_lines.add_child(bar)
	FinanceRefusal.division_bar(bar, Strings.t("Assembly, if it divided now").to_upper(), vote)
	var said := HBoxContainer.new()
	said.add_theme_constant_override("separation", 6)
	_lines.add_child(said)
	var rebels := 0
	for party in vote.get("party_rebels", {}):
		rebels += int(vote["party_rebels"][party])
	if rebels > 0:
		var line := PanelKit.plain_line(said, Strings.t("%d of your seats rebel.") % rebels)
		line.theme_type_variation = UiTheme.CAPTION
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
	var passed := bool(vote["passed"])
	_toned(said, Strings.t("It carries.") if passed else Strings.t("It falls."), passed).autowrap_mode = TextServer.AUTOWRAP_OFF


func _fill_verbs(refusal: String, forced: bool, queue: Dictionary, live: bool) -> void:
	var tabled := FinanceBillLaw.tabled(_state.player()) != null
	if tabled:
		_ghost("SheetWithdraw", Strings.t("Withdraw the bill"), withdraw_pressed)
	else:
		_ghost("SheetDiscard", Strings.t("Discard all"), discard_pressed)
	_ghost("SheetClose", Strings.t("Close"), close_pressed)
	var label := Strings.t("Table and force it") if forced else (Strings.t("Add to the bill") if tabled else Strings.t("Table the bill"))
	if String(queue.get("text", "")) != "":
		label = String(queue["text"])
	var table := PanelKit.button(label, PanelKit.Size.L)
	table.name = "SheetTable"  # i18n: ok a node name, found by tests
	table.theme_type_variation = UiTheme.PRIMARY
	table.disabled = refusal != "" and not live
	table.pressed.connect(func() -> void: table_pressed.emit(forced))
	_verbs.add_child(table)
	# Tab stays in the document: past the last verb it comes round to the first control, and Shift+Tab back.
	table.focus_next = table.get_path_to(_first)
	_first.focus_previous = _first.get_path_to(table)


func _ghost(node_name: String, label: String, signal_out: Signal) -> void:
	var button := PanelKit.button(label, PanelKit.Size.S)
	button.name = node_name  # i18n: ok a node name, found by tests
	button.theme_type_variation = UiTheme.GHOST
	button.pressed.connect(signal_out.emit)
	_verbs.add_child(button)
