extends RefCounted

## The Finances page's ONE draft -- V5.3 screen 4, direction A slice 2. What the Budget tab and the Tax Code
## tab kept apart (two pendings, two Commits, one bill) is a single set of edited rows here, so the rows, the
## strip, the footer and the Table button all read the same thing.
##
## Only a row the player MOVED is held. An untouched row reads the live register, so a law, an event or a
## summit that moves a rate under the player's feet is never undone by a stale copy (docs/tax-model.md 11),
## and an off-grid rate (France's fuel duty, 0.6545) is never snapped into a draft by a slider's init: the
## draft changes on input and nowhere else. A row dragged back to its live value is no row.
##
## Plain data over the live state: it reads the state and writes nothing; the command is
## FinanceBill.table(state, loader, draft.bill()), the footer's.

const FinanceBill = preload("res://src/sim/finance_bill.gd")

const SPENDING := "spending_pct_gdp"
const TAX := "tax_rates_pct"
## The brackets lever sets no rate: a scalar riding the pending, the bill's own key.
const BRACKETS := "tax_progressivity"

var _state
## {channel: {key: absolute value}}, the rows the player touched.
var _edited := {SPENDING: {}, TAX: {}}
var _brackets = null


func setup(state) -> void:
	_state = state
	revert()


func revert() -> void:
	_edited = {SPENDING: {}, TAX: {}}
	_brackets = null


## The player's input on one row. `channel` is SPENDING or TAX; the brackets have their own call.
func set_value(channel: String, key: String, value: float) -> void:
	(_edited[channel] as Dictionary)[key] = value


func set_brackets(value: float) -> void:
	_brackets = value


## The register's value for a row now.
func live(channel: String, key: String) -> float:
	var ns = _state.player()
	if channel == BRACKETS:
		return float(ns.tax_progressivity)
	var register: Dictionary = ns.spending_pct_gdp if channel == SPENDING else ns.tax_rates_pct
	return float(register.get(key, 0.0))


## The draft's value for a row: the player's if they moved it, the live one otherwise.
func value(channel: String, key: String) -> float:
	if channel == BRACKETS:
		return float(_brackets) if _brackets != null else live(BRACKETS, "")
	return float((_edited[channel] as Dictionary).get(key, live(channel, key)))


func is_moved(channel: String, key: String) -> bool:
	if channel == BRACKETS:
		return _brackets != null and not is_equal_approx(float(_brackets), live(BRACKETS, ""))
	return (_edited[channel] as Dictionary).has(key) and not is_equal_approx(value(channel, key), live(channel, key))


## The moved rows as [{channel, key, live, draft}], spending first, in a stable order.
func rows() -> Array:
	var out := []
	for channel in [SPENDING, TAX]:
		for key in (_edited[channel] as Dictionary):
			if is_moved(channel, String(key)):
				out.append({"channel": channel, "key": String(key), "live": live(channel, String(key)), "draft": value(channel, String(key))})
	if is_moved(BRACKETS, ""):
		out.append({"channel": BRACKETS, "key": "", "live": live(BRACKETS, ""), "draft": value(BRACKETS, "")})
	return out


func count() -> int:
	return rows().size()


func is_empty() -> bool:
	return count() == 0


## Budget.commit's shape, the moved rows alone -- what the strip and the forecast price.
func pending() -> Dictionary:
	var out := {}
	for row in rows():
		match String(row["channel"]):
			SPENDING, TAX:
				if not out.has(row["channel"]):
					out[row["channel"]] = {}
				out[row["channel"]][row["key"]] = float(row["draft"])
			BRACKETS:
				out[BRACKETS] = float(row["draft"])
	return out


## The finance bill's rows: the deltas against the live register (FinanceBill.from_pending's contract).
func bill() -> Dictionary:
	return FinanceBill.from_pending(_state.player(), pending())
