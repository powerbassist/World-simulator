extends HBoxContainer

## The Finances page's footer -- V5.3 screen 4, direction A slice 2: the draft's sentence and the one verb it
## calls for. It replaces the Budget's and the Tax Code's Commit and Revert pair. While rows are drafted it says
## how many, what they do to each side of the books a year and when the Assembly divides, and offers the ONE
## button, "Table the changes" (a bill already before the Assembly takes them as an amendment: "Add to the
## bill"). With nothing drafted and a bill before the Assembly it says so and offers that bill's sheet and its
## withdrawal. Nothing drafted and nothing tabled: the footer is not there.
##
## The player sees the effect AND the price before he tables (the parent's ruling, G4): the sentence carries the
## draft's totals and, on the next line, how the Assembly would divide on it now (FinanceRead.draft's vote).
##
## "Withdraw the bill" is there whenever a bill is at vote, drafted or not, and it keeps the draft (never stranded).
##
## A button that the rule would refuse is never a dead verb: it is disabled and the refusal is said in words
## beside it, read from FinanceRead.draft, which asks the very rule tabling meets. A draft can be dropped
## ("Discard the changes"): the Budget's Revert is gone with its tab.

signal table_pressed
signal discard_pressed
signal open_pressed
signal review_pressed
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
var _discard: Button
var _open: Button
var _review: Button
var _withdraw: Button


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_text = Label.new()
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_text)
	_discard = _button("Discard", Strings.t("Discard the changes"), discard_pressed)  # i18n: ok a node name
	_withdraw = _button("Withdraw", Strings.t("Withdraw the bill"), withdraw_pressed)  # i18n: ok a node name
	_withdraw.flat = true  # quiet: the draft's verb beside it is the one that carries the weight
	_open = _button("OpenBill", Strings.t("Open the bill"), open_pressed)
	_review = _button("Review", Strings.t("Review the bill"), review_pressed)  # i18n: ok a node name
	_review.flat = true  # the sheet is the act's detail, the footer's own verb stays the loud one
	_table = _button("Table", Strings.t("Table the changes"), table_pressed)  # i18n: ok a node name
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
	_discard.visible = drafted
	_review.visible = drafted
	_open.visible = not drafted and tabled != null
	_withdraw.visible = tabled != null
	if not visible:
		return
	if not drafted:
		_text.text = Strings.t("A finance bill is before the Assembly: it divides on %s.") % DateText.day_month(
			int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
		return
	var read: Dictionary = FinanceRead.draft(state, loader, draft.bill())
	var refusal := String(read["refusal"])
	# The same pricing as the sheet (FinancePrice.whole): the bill the vote decides. On an amendment the count is the
	# new rows but the money is the whole bill's, and the sentence says so.
	var whole: Dictionary = price.whole(loader, draft, refusal != "")
	var money := Strings.t("the whole bill: spending %s, revenue %s a year") if tabled != null else Strings.t("spending %s, revenue %s a year")
	var text: String = Strings.tn("%d change", "%d changes", draft.count()) % draft.count() + " · " + \
		money % [EffectsStrip.money_text(float(whole["spending_bn"])), EffectsStrip.money_text(float(whole["revenue_bn"]))] + " · " + \
		Strings.t("the Assembly divides on %s") % DateText.day_month(Calendar.days_in_month(int(state.year), int(state.month)), int(state.month))
	_table.text = Strings.t("Add to the bill") if tabled != null else Strings.t("Table the changes")
	_table.disabled = refusal != ""
	if refusal != "":
		_text.text = text + "\n" + reason(refusal)
		return
	var vote: Dictionary = read["vote"]
	_text.text = text + "\n" + Strings.t("Forecast now: %d for, %d against, %d undecided of %d.") % [
		int(vote["yes_seats"]), int(vote["no_seats"]), int(vote["abstain_seats"]), int(vote["seats_total"])]


## The refusal in words, for a page with no queue verb: another bill in the slot is said as it is.
static func reason(flag: String) -> String:
	if flag == "already_tabled":
		return Strings.t("Another bill holds this month's slot.")
	return GoalRows.reason_text(flag)


## The control the page exists to let the player press: the draft's verb, else the bill's sheet.
func primary_action() -> Control:
	if not visible:
		return null
	return _table if _table.visible else _open
