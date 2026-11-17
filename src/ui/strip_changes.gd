extends RefCounted

## The change beside a standing figure on the strip (V5.3, gate H6: a figure with no
## movement beside it says where it is and not where it is going): its own movement over
## Trends' window, signed, and whether that is good news. Only the figures history
## carries (the money, GDP's growth, unemployment); an empty dictionary is "no history
## yet" or "no movement the player would notice". The tone is never alone: the glyph, the
## number and, since gate 3 (G3-10, "i dont know if i got positive or negative flux"),
## the word -- better or worse -- print too.

const Trends = preload("res://src/ui/trends.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")
const StripSeries = preload("res://src/ui/strip_series.gd")

const WINDOW := Trends.TREND_MONTHS

## Below this a move is not one the player would notice, in the figure's own units.
const NOTICED := 0.05

const CHANGES := {
	"deficit": {"key": "", "good_when_rising": true},  # i18n: ok reading ids -- the money, in bn a month (StripSeries)
	"gdp": {"key": "growth_annual_pct", "good_when_rising": true},  # i18n: ok reading ids
	"unemployment": {"key": "unemployment_pct", "good_when_rising": false},  # i18n: ok reading ids
}

## {text: "▼ 0.4 bn worse", good: false} or {} -- see CHANGES.
static func change(id: String, state) -> Dictionary:
	if not CHANGES.has(id):
		return {}
	var spec: Dictionary = CHANGES[id]
	var moved := _balance_moved(state) if id == "deficit" else Trends.delta(state, String(spec["key"]), WINDOW)
	if is_nan(moved) or absf(moved) < NOTICED:
		return {}
	var good: bool = (moved > 0.0) == bool(spec["good_when_rising"])
	var amount := Strings.t("%s bn") % Num.f(absf(moved), 1) if id == "deficit" else Strings.t("%s pt") % Num.f(absf(moved), 2)
	var figure := "%s %s" % ["▲" if moved > 0.0 else "▼", amount]  # i18n: ok a glyph and a figure
	return {"text": Strings.t("%s better") % figure if good else Strings.t("%s worse") % figure, "good": good}


## The month's balance now less WINDOW months ago, in bn: up is a smaller deficit.
static func _balance_moved(state) -> float:
	var now := Trends.entry_at(state, 0)
	var then := Trends.entry_at(state, WINDOW)
	if now.is_empty() or then.is_empty():
		return NAN
	return StripSeries.balance_bn(float(now.get("deficit_pct_gdp", 0.0)), float(now.get("gdp_eur_bn", 0.0))) \
		- StripSeries.balance_bn(float(then.get("deficit_pct_gdp", 0.0)), float(then.get("gdp_eur_bn", 0.0)))
