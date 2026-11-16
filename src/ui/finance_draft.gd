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
## The autumn bill's two kinds of row (slice 4): a kind put in force and a kind abolished. They are rows of the
## draft, never rate deltas: tabling refuses a rate row on a kind not in force or being abolished, so the bill
## carries them under their own keys (FinanceBill.CREATE, FinanceBill.ABOLISH) and the priceable-now pending
## holds neither (the pricing of a birth is its own read).
const ABOLISH := "abolish"

var _state
## {channel: {key: absolute value}}, the rows the player touched.
var _edited := {SPENDING: {}, TAX: {}}
var _brackets = null
## Kinds put in force (their rate is in _edited[TAX], read and written like any rate row) and kinds abolished.
var _created := {}
var _abolished: Array = []
## Share moves, [{line, from, to, amount}] in the order drafted (slice 5). NOT rows of the bill: a move costs no
## money and needs no vote, so it applies the moment the footer's verb is pressed (Sectors.move_share), whatever the
## tabling answers. The draft only holds them, so the tile, the footer and the forecast all count the same ones.
var _moves: Array = []
## The move verb's picks (from, to, how much), kept here so a rebuild of the page does not reset them.
var pick := {}


func setup(state) -> void:
	_state = state
	revert()


func revert() -> void:
	_edited = {SPENDING: {}, TAX: {}}
	_brackets = null
	_created = {}
	_abolished = []
	_moves = []


## A kind not in force is put in force at `rate` (the editor's slider then moves it like any rate).
func set_create(kind: String, rate: float) -> void:
	_created[kind] = true
	(_edited[TAX] as Dictionary)[kind] = rate


func clear_create(kind: String) -> void:
	_created.erase(kind)
	(_edited[TAX] as Dictionary).erase(kind)


func is_created(kind: String) -> bool:
	return _created.has(kind)


## A kind in force is abolished, or kept after all. Any rate edit on it is dropped: it is no rate row any more.
func toggle_abolish(kind: String) -> void:
	if _abolished.has(kind):
		_abolished.erase(kind)
		return
	_abolished.append(kind)
	(_edited[TAX] as Dictionary).erase(kind)


func is_abolished(kind: String) -> bool:
	return _abolished.has(kind)


## Whether the kind is in the register now (a rate of 0 % is in force: it is no birth).
func in_force(kind: String) -> bool:
	return _state.player().tax_rates_pct.has(kind)


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
	if channel == TAX and _created.has(key):
		return true
	if channel == BRACKETS:
		return _brackets != null and not is_equal_approx(float(_brackets), live(BRACKETS, ""))
	return (_edited[channel] as Dictionary).has(key) and not is_equal_approx(value(channel, key), live(channel, key))


## The moved rows as [{channel, key, live, draft}], spending first, in a stable order.
func rows() -> Array:
	var out := []
	for channel in [SPENDING, TAX]:
		for key in (_edited[channel] as Dictionary):
			if is_moved(channel, String(key)):
				var row := {"channel": channel, "key": String(key), "live": live(channel, String(key)), "draft": value(channel, String(key))}
				if channel == TAX and _created.has(key):
					row["birth"] = true
				out.append(row)
	if is_moved(BRACKETS, ""):
		out.append({"channel": BRACKETS, "key": "", "live": live(BRACKETS, ""), "draft": value(BRACKETS, "")})
	for kind in _abolished:
		out.append({"channel": ABOLISH, "key": String(kind), "live": live(TAX, String(kind)), "draft": 0.0})
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
				if row.get("birth", false):
					continue
				if not out.has(row["channel"]):
					out[row["channel"]] = {}
				out[row["channel"]][row["key"]] = float(row["draft"])
			BRACKETS:
				out[BRACKETS] = float(row["draft"])
	return out


## A share move drafted: the line, the sector paying, the sector gaining and the share (a fraction of the line).
func add_move(line: String, from_id: String, to_id: String, amount: float) -> void:
	_moves.append({"line": line, "from": from_id, "to": to_id, "amount": amount})


func moves() -> Array:
	return _moves.duplicate(true)


func has_moves() -> bool:
	return not _moves.is_empty()


## The moves are spent (booked, or put away with the draft): the rows stay.
func clear_moves() -> void:
	_moves = []


## Nothing drafted at all, rows and moves alike (is_empty() is the BILL's: no row, whatever the moves).
func is_clean() -> bool:
	return is_empty() and _moves.is_empty()


## The finance bill's rows: the deltas against the live register (FinanceBill.from_pending's contract).
func bill() -> Dictionary:
	var out := FinanceBill.from_pending(_state.player(), pending())
	if not _created.is_empty():
		out[FinanceBill.CREATE] = births()
	if not _abolished.is_empty():
		out[FinanceBill.ABOLISH] = _abolished.duplicate()
	return out


## The autumn rows go (the month is over): every birth and abolition leaves the draft, the ordinary rows stay.
## Returns whether anything left.
func drop_autumn() -> bool:
	var had := not _created.is_empty() or not _abolished.is_empty()
	for kind in _created:
		(_edited[TAX] as Dictionary).erase(kind)
	_created = {}
	_abolished = []
	return had


## The kinds put in force: {kind: rate}.
func births() -> Dictionary:
	var out := {}
	for kind in _created:
		out[kind] = float((_edited[TAX] as Dictionary).get(kind, 0.0))
	return out


## The kinds abolished.
func abolitions() -> Array:
	return _abolished.duplicate()
