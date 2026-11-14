extends RefCounted

## What an event's choice DOES, in a few short tags -- V5.3 screen 3 (gate H7, "decision
## popup is unclear": three buttons, and nothing said what any of them cost). A tag is a
## status-toned phrase in the briefing's own words (briefing_effects.gd: a bloc offset under
## 0.05 is "slightly", from 0.15 "clearly"); the tone is never alone, since the phrase says
## which way it went and the card draws a glyph with it.
##
## Every key an event's `effects` can carry is worded here (WORDED); the test sweeps
## data/events and fails on a key this file does not know, because a choice whose cost is
## corruption or a sector burden must not read as bloc tags alone. A key it does not know
## still draws ONE neutral "Other effects" tag rather than nothing.

const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")

## At most this many tags a choice; the rest fold into one "+N" whose title lists them.
const TAG_MAX := 4
## The blocs a choice shows before its other effects take a slot: the two it moves most.
const BLOCS_FIRST := 2

## The effect keys this file words: key -> the subkeys it words (an empty list: the key itself).
const WORDED := {
	"bloc_offset": ["pensioners", "business", "students", "workers", "urban", "rural"],
	"society": ["corruption", "migration", "settlement", "press_freedom", "judicial_independence"],
	"spending_pct_gdp": ["health", "education", "defence", "pensions", "infrastructure"],
	"tax_rates_pct": ["income", "vat"],
	"other_revenue_pct_gdp": [],
	"company": ["sector", "burden"],
}


## [{text, tone (1 good, -1 bad, 0 neither)}], the biggest first.
static func of(choice: Dictionary) -> Array[Dictionary]:
	var effects: Dictionary = choice.get("effects", {})
	var all: Array[Dictionary] = []
	var blocs: Dictionary = effects.get("bloc_offset", {})
	var ordered: Array = blocs.keys()
	ordered.sort_custom(func(a, b): return absf(float(blocs[a])) > absf(float(blocs[b])))
	var rest: Array[Dictionary] = []
	for key in effects:
		if key == "bloc_offset":
			continue
		rest.append_array(_others(key, effects[key]))
	for i in ordered.size():
		if i < BLOCS_FIRST or rest.is_empty() and i < TAG_MAX:
			var d := float(blocs[ordered[i]])
			all.append({"text": BriefingEffects._offset_words(String(ordered[i]), d), "tone": 1 if d > 0.0 else -1})
	all.append_array(rest)
	if all.size() > TAG_MAX:
		var folded := all.size() - TAG_MAX + 1
		var kept: Array[Dictionary] = []
		kept.assign(all.slice(0, TAG_MAX - 1))
		kept.append({"text": "+%d" % folded, "tone": 0})
		return kept
	return all


static func _others(key: String, value) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match key:
		"society":
			for term in value:
				out.append(_society(String(term), float(value[term])))
		"spending_pct_gdp":
			for lever in value:
				var label: String = Strings.t(String(BudgetPanel.LEVER_LABELS.get(lever, lever)))
				out.append({"text": (Strings.t("%s spending up") if float(value[lever]) > 0.0 else Strings.t("%s spending down")) % label, "tone": 0})
		"tax_rates_pct":
			for tax in value:
				out.append({"text": (Strings.t("%s up") if float(value[tax]) > 0.0 else Strings.t("%s down")) % Labels.tax(String(tax)), "tone": 0})
		"other_revenue_pct_gdp":
			out.append({"text": Strings.t("More other revenue") if float(value) > 0.0 else Strings.t("Less other revenue"), "tone": 0})
		"company":
			var burden := float(value.get("burden", 0.0))
			if burden != 0.0:
				var sector := Labels.sector(String(value.get("sector", "")))
				out.append({"text": (Strings.t("A burden on %s") if burden > 0.0 else Strings.t("Relief for %s")) % sector, "tone": -1 if burden > 0.0 else 1})
		_:
			out.append({"text": Strings.t("Other effects"), "tone": 0})
	return out


## The five society terms, in the briefing's stance words, short.
static func _society(term: String, v: float) -> Dictionary:
	var up := v > 0.0
	match term:
		"corruption":
			return {"text": Strings.t("Looser on corruption") if up else Strings.t("Tighter on corruption"), "tone": -1 if up else 1}
		"migration":
			return {"text": Strings.t("Opens migration") if up else Strings.t("Tightens migration"), "tone": 0}
		"settlement":
			return {"text": Strings.t("Settles with the unions") if up else Strings.t("Harder on the unions"), "tone": 0}
		"press_freedom":
			return {"text": Strings.t("A freer press") if up else Strings.t("A less free press"), "tone": 1 if up else -1}
		"judicial_independence":
			return {"text": Strings.t("Stronger courts") if up else Strings.t("Weaker courts"), "tone": 1 if up else -1}
	return {"text": Strings.t("Other effects"), "tone": 0}
