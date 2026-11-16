extends RefCounted

## A sector's head on its tab -- V5.3 screen 5, slice 1: the verdict in words, one lead
## sentence and four figures (output, jobs, trend, share of GDP). Every figure is the
## sim's: the trend is Economy.sector_trend_pct() (the rate the month's growth applies,
## #254), set against ns.trend_annual_pct, so the UI copies no part of economy.gd's sum.
##
## THE VERDICT IS A RULE OVER ONE GAP, the sector's trend less the nation's, in points a
## year. The edges are presentation, not tuning (the sim never reads them), so they live
## here beside their only reader. 1.0 and 0.2 are set on France's start: agriculture
## 0.2 against 1.3 reads "falling behind", industry 1.0 "slower", services 1.4 "keeping
## pace" -- the three readings the author saw in the pictures, now a rule rather than
## three hand-picked words.

const Companies = preload("res://src/sim/companies.gd")
const Economy = preload("res://src/sim/economy.gd")
const Strings = preload("res://src/ui/strings.gd")

## Points a year under the nation's trend from which a sector is "falling behind".
const BEHIND := 1.0
## Within this many points of the nation's trend, a sector "keeps pace".
const PACE := 0.2

## The verdict's tag, lower case (it sits beside the sector's name).
const WORDS := {
	"behind": "falling behind",  # i18n: msgid
	"slower": "slower than the nation",  # i18n: msgid
	"pace": "keeping pace",  # i18n: msgid
	"ahead": "ahead of the nation",  # i18n: msgid
}
## The lead sentence: the sector's trend, then the nation's. The verdict is the tag
## beside the name, so the sentence does not say it twice (the text diet).
const LEAD := "%s %% a year against %s %% for the nation."  # i18n: msgid


## behind, slower, pace or ahead, for a gap in points a year (sector less nation).
static func verdict(gap: float) -> String:
	if gap < -BEHIND:
		return "behind"
	if gap < -PACE:
		return "slower"
	if gap <= PACE:
		return "pace"
	return "ahead"


static func verdict_words(id: String) -> String:
	return Strings.t(String(WORDS.get(id, "")))  # i18n: row-ok the table's msgids


## {verdict, trend, nation, output, jobs, of_gdp} for one sector of the nation.
static func head(state, loader, ns, sector: String) -> Dictionary:
	var trend := Economy.sector_trend_pct(state, ns, sector)
	var nation := float(ns.trend_annual_pct)
	var output := float(ns.sector_output.get(sector, 0.0))
	var gdp := float(ns.gdp_eur_bn)
	return {
		"verdict": verdict(trend - nation), "trend": trend, "nation": nation, "output": output,
		"jobs": jobs(loader, ns, sector), "of_gdp": 100.0 * output / gdp if gdp > 0.0 else 0.0,
	}


## The lead sentence for a head() reading, its figures signed.
static func lead(reading: Dictionary, fmt: Callable) -> String:
	return Strings.t(LEAD) % [fmt.call(float(reading["trend"])), fmt.call(float(reading["nation"]))]


## The jobs at the sector's named firms, majors and body, at today's headcount.
static func jobs(loader, ns, sector: String) -> float:
	var total := 0.0
	for company in Companies.firms_in_sector(loader, ns.id, sector):
		total += Companies.headcount(ns, company)
	return total
