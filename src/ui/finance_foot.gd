extends HBoxContainer

## The Finances page's footer -- V5.3 screen 4, direction A slice 2: the draft's sentence and the one verb it
## calls for. It replaces the Budget's and the Tax Code's Commit and Revert pair. While rows are drafted it says
## how many, what they do to each side of the books a year and when the Assembly divides, and offers the ONE
## button, "Table the changes" (a bill already before the Assembly takes them as an amendment: "Add to the
## bill"). With nothing drafted and a bill before the Assembly it says so and offers that bill's sheet and its
## withdrawal. Nothing drafted and nothing tabled: the footer is not there.
##
## A button that the rule would refuse is never a dead verb: it is disabled and the refusal is said in words
## beside it (the goal panel's own wording, GoalRows.reason_text), read from FinanceRead.draft, which asks the
## very rule tabling meets.

signal table_pressed
signal open_pressed
signal withdraw_pressed

const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const GoalRows = preload("res://src/ui/goal_rows.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")

var _text: Label
var _table: Button
var _open: Button
var _withdraw: Button


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_text = Label.new()
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_text)
	_withdraw = _button("Withdraw", Strings.t("Withdraw the bill"), withdraw_pressed)
	_open = _button("OpenBill", Strings.t("Open the bill"), open_pressed)
	_table = _button("Table", Strings.t("Table the changes"), table_pressed)
	visible = false


func _button(node_name: String, label: String, signal_out: Signal) -> Button:
	var button := PanelKit.sized(Button.new())
	button.name = node_name  # i18n: ok a node name, found by tests
	button.text = label
	button.pressed.connect(signal_out.emit)
	add_child(button)
	return button


## Written from the draft and the books; called on every draft move and every redraw, so it reads only.
func refresh(state, loader, draft, price) -> void:
	var ns = state.player()
	var tabled = FinanceBillLaw.tabled(ns)
	var drafted: bool = not draft.is_empty()
	visible = drafted or tabled != null
	_table.visible = drafted
	_open.visible = not drafted and tabled != null
	_withdraw.visible = not drafted and tabled != null
	if not visible:
		return
	if not drafted:
		_text.text = Strings.t("A finance bill is before the Assembly: it divides on %s.") % DateText.day_month(
			int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
		return
	var moves: Dictionary = price.moves(draft.pending())
	var text: String = Strings.tn("%d change", "%d changes", draft.count()) % draft.count() + " · " + \
		Strings.t("spending %s, revenue %s a year") % [EffectsStrip.money_text(float(moves["spending_bn"])), EffectsStrip.money_text(float(moves["revenue_bn"]))] + " · " + \
		Strings.t("the Assembly divides on %s") % DateText.day_month(Calendar.days_in_month(int(state.year), int(state.month)), int(state.month))
	var refusal := String(FinanceRead.draft(state, loader, draft.bill())["refusal"])
	_table.text = Strings.t("Add to the bill") if tabled != null else Strings.t("Table the changes")
	_table.disabled = refusal != ""
	_text.text = text if refusal == "" else text + "\n" + GoalRows.reason_text(refusal)


## The control the page exists to let the player press: the draft's verb, else the bill's sheet.
func primary_action() -> Control:
	if not visible:
		return null
	return _table if _table.visible else _open
