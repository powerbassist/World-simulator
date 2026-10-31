extends RefCounted

## The music's band, one step a briefing -- V5.3-0, docs/design/v5.3-0-readability.md
## 4.3, band RF9. Pure, so Systems' probe counts the bed changes over 120 months
## with the rule the player will hear, and the music player (block 0's step 6)
## only plays what this says.
##
## Up at once, down slowly: a move to a tenser band takes the next briefing; a move
## to a calmer one waits for two consecutive months of it. Hysteresis both ways
## would lag the emotion it exists for -- a crisis solved in a month would never be
## heard (GLM's finding 13). The campaign band takes the three months before an
## election; a crisis still beats it.

const CALM := "calm"  # i18n: ok a band key
const TENSE := "tense"  # i18n: ok a band key
const CRISIS := "crisis"  # i18n: ok a band key
const CAMPAIGN := "campaign"  # i18n: ok a band key
## Tension order: a step up is a move to a higher rank.
const RANK := {CALM: 0, TENSE: 1, CAMPAIGN: 2, CRISIS: 3}
const CAMPAIGN_MONTHS := 3
const CALMER_MONTHS := 2


## `prev` is the last call's return ({} at the start); `situation` is
## Priorities.situation() of this month's three; `months_to_election` is -1 when
## the nation has no vote ahead. Returns {band, calmer_months}.
static func step(prev: Dictionary, situation: String, months_to_election: int) -> Dictionary:
	var want := situation
	if want != CRISIS and months_to_election >= 0 and months_to_election <= CAMPAIGN_MONTHS:
		want = CAMPAIGN
	var band := String(prev.get("band", ""))
	if band.is_empty() or int(RANK.get(want, 0)) >= int(RANK.get(band, 0)):
		return {"band": want, "calmer_months": 0}
	var calmer := int(prev.get("calmer_months", 0)) + 1
	if calmer >= CALMER_MONTHS:
		return {"band": want, "calmer_months": 0}
	return {"band": band, "calmer_months": calmer}
