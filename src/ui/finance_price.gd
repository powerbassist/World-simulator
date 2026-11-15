extends RefCounted

## What a draft does to the books, priced once however many surfaces ask. A row editor's effect line and the
## footer's totals both read the live state against the SAME pending when one row is moved, and a drag asks a
## frame: one Budget.preview() is ~19 ms (V5.1-0a), so the last answers are kept, keyed by the pending and
## by the state's day, and the second asker costs nothing. A copy of the state is priced and never the
## state itself (engine-decision.md rule 2); a day later is another state.

const Budget = preload("res://src/sim/budget.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")

## How many pendings are kept: a drag moves one row a frame, and the row's own and the whole draft's differ
## only when two rows are moved.
const KEEP := 4

var _state
var _stamp := ""
var _now := {}
var _kept := {}


func setup(state) -> void:
	_state = state
	_stamp = ""


## The books with nothing pending: the live position, re-read once a day.
func now() -> Dictionary:
	_check()
	if _now.is_empty():
		_now = Budget.preview(_state, {})
	return _now


## The books with `pending` committed on a copy.
func after(pending: Dictionary) -> Dictionary:
	_check()
	var key := var_to_str(pending)
	if _kept.has(key):
		return _kept[key]
	if _kept.size() >= KEEP:
		_kept.erase(_kept.keys()[0])
	_kept[key] = Budget.preview(_state, pending)
	return _kept[key]


## The balance `pending` books a year, EUR bn (a gain positive), as the strip prints it.
func balance_bn(pending: Dictionary) -> float:
	return EffectsStrip.balance_bn(now(), after(pending))


## {spending_bn, revenue_bn, balance_bn}: how far `pending` moves each side a year.
func moves(pending: Dictionary) -> Dictionary:
	var a := now()
	var b := after(pending)
	return {
		"spending_bn": EffectsStrip.moved_bn(a, b, "total_spending_pct_gdp"),
		"revenue_bn": EffectsStrip.moved_bn(a, b, "total_revenue_pct_gdp"),
		"balance_bn": EffectsStrip.balance_bn(a, b),
	}


## The state moved behind the page (a law, an event): both are due again.
func reset() -> void:
	_stamp = ""


func _check() -> void:
	var stamp := "%d|%d|%d|%s" % [_state.year, _state.month, _state.day, str(_state.player().tabled_bill)]
	if stamp != _stamp:
		_stamp = stamp
		_now = {}
		_kept = {}
