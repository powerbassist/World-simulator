extends RefCounted

## Who a finance change is for, or who pays it -- the bill's rail (finance_foot.gd) says it on each change. A spending
## line's blocs are read once a line a day (FinanceRead.line_blocs prices a copy of the state, about 30 ms); a tax's
## payers are its data. The autumn's two rows (a kind put in force, a kind abolished) name no one.

const FinanceRead = preload("res://src/sim/finance_read.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")

var _blocs := {}
var _day := ""


func say(state, loader, row: Dictionary) -> String:
	var key := String(row["key"])
	match String(row["channel"]):
		FinanceDraft.SPENDING:
			var blocs := line_blocs(state, loader, key)
			return Strings.t("for %s") % ", ".join(blocs.map(func(b) -> String: return Labels.bloc(String(b)))) if not blocs.is_empty() else ""
		FinanceDraft.TAX:
			if bool(row.get("birth", false)):
				return ""
			var payers: Array = state.player().tax_library[key].get("who_pays", [])
			return Strings.t("%s pay") % ", ".join(payers.map(func(b) -> String: return Labels.bloc(String(b)))) if not payers.is_empty() else ""
	return ""


## The blocs that weigh spending line `key`, most first, kept for the day.
func line_blocs(state, loader, key: String) -> Array:
	var day := "%d|%d|%d" % [state.year, state.month, state.day]
	if day != _day:
		_day = day
		_blocs = {}
	if not _blocs.has(key):
		_blocs[key] = (FinanceRead.line_blocs(state, loader, key)["weights"] as Array).map(func(pair: Array) -> String: return String(pair[0]))
	return _blocs[key]
