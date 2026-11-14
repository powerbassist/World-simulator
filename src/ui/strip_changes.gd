extends RefCounted

## The change beside a standing figure on the strip (V5.3, gate H6: a figure with no
## movement beside it says where it is and not where it is going): its own movement over
## Trends' window, signed, and whether that is good news. Only the figures history
## carries (deficit, GDP's growth, unemployment); an empty dictionary is "no history
## yet" or "no movement the player would notice". The tone is never alone: the glyph and
## the number print too.

const Trends = preload("res://src/ui/trends.gd")
const Num = preload("res://src/ui/num.gd")

const WINDOW := Trends.TREND_MONTHS

const CHANGES := {
	"deficit": {"key": "deficit_pct_gdp", "sign": -1.0, "good_when_rising": true},  # i18n: ok reading ids
	"gdp": {"key": "growth_annual_pct", "sign": 1.0, "good_when_rising": true},  # i18n: ok reading ids
	"unemployment": {"key": "unemployment_pct", "sign": 1.0, "good_when_rising": false},  # i18n: ok reading ids
}

## {text: "▲ 0.19", good: true} or {} -- see CHANGES.
static func change(id: String, state) -> Dictionary:
	if not CHANGES.has(id):
		return {}
	var spec: Dictionary = CHANGES[id]
	var moved: float = Trends.delta(state, String(spec["key"]), WINDOW) * float(spec["sign"])
	if is_nan(moved) or absf(moved) < 0.05:
		return {}
	return {"text": "%s %s" % ["▲" if moved > 0.0 else "▼", Num.f(absf(moved), 2)],  # i18n: ok glyph and figure
		"good": (moved > 0.0) == bool(spec["good_when_rising"])}

