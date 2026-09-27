extends RefCounted

## The character layer's SCHEMA constants: the trait vocabulary, the kinds, the
## kind->meter map and the want grammar. Same shape as programme_constants.gd --
## model parameters, not content, so not in data/. The argument for every table
## is docs/people-model.md section 14; this file is the values, that file is the
## argument.
##
## *** EVERYTHING HERE IS A CLOSED VOCABULARY, AND NONE OF IT PRICES ANYTHING. ***
## The act and band constants -- prices, thresholds, decay rates -- are
## characters.gd's own file, swept by its probe before they ship. This file
## holds only what the loader validates content against and what the UI
## compares strings with, so a typo in data/people/*.json is a load error
## rather than a silently inert trait.

## The eight traits, 2-3 authored per person. Each gates an act threshold or
## price -- the CK lever docs/tiers/v4.md 4.3 signed -- and the whole
## mechanical definitions live in docs/people-model.md section 14.2 beside the
## constants that price them; membership is all the loader checks. A ninth
## trait needs a measurement, not a mood (the SLOT_POSITION standard).
## `ambitious` the trait and `ambition` the authored scalar are different
## things and both exist: the scalar is the dial, the trait is the floor.
##
## ALL EIGHT ARE MECHANICALLY REAL, and the review's I3 is why this comment now
## says so: five of them (loyal, principled, pragmatic, vain, fervent) were
## FICTION at the first ship -- named in this list, authored into 1,595 people,
## and read by nothing. Where the shipped form differs from 14.2's sketch, the
## table was corrected to the code rather than the code stretched to the prose:
## `loyal` halves the grudge PULSE (not the relief), `principled` doubles it,
## `pragmatic`/`stubborn` scale the DECAY where the person is in hand, `vain`'s
## discount is gated on the target being an office want they carry, and
## `fervent` amplifies METER-want pulses for the collective kinds rather than
## building a second salience read it would have to invent.
const TRAIT_KEYS := [
 "ambitious", "loyal", "principled", "pragmatic", "vain", "stubborn",
 "networked", "fervent",
]

## The kinds whose lever is the COLLECTIVE read -- grievance as a body of people
## rather than a politician's own standing. `fervent`'s gate reads this list
## rather than naming kinds inline (14.2's "union/activist kinds"), so a kind
## added to the collective side is added in one place.
const KIND_COLLECTIVE := ["union_leader", "activist"]

## What a person IS when no political slot points at them. `politician` is the
## version-35 default every existing entry reads (the whole register was the
## political cast); the other five are the bench the deep roster generates.
## `regional_figure` is a politician shape without a national slot -- a
## governor, a mayor -- and shares the politician lever (wants + standing).
const KIND_KEYS := [
	"politician", "regional_figure", "union_leader", "press_owner", "judge",
	"activist", "executive",
]

## V4.7a: an executive is a FIRM CHIEF -- the face of a hand-authored major and
## the future appoint-to-board pool. DECLARED STOPGAP, in the V1.4b sense of
## that word: executives carry no meter and no wants, so in V4.7 they cannot
## act, and a kind that cannot act is the inert-content class
## tests/test_people.gd refuses. What makes this honest rather than silent is
## that the chief's action is the FIRM's action (V4.7b's autonomy machine acts
## through the firm), and their own lever -- lobbying spend, a voice in the
## assembly arithmetic -- is V4.2's to open, recorded in that block's handoff.
## The exemption in _check_kind_meter_coverage carries the same sentence.

## The EXISTING meter each metered kind reads. A kind that is neither
## `politician`, `regional_figure` nor in this table has no lever at all, and
## tests/test_people.gd refuses one rather than letting it load inert. NO
## SECOND METER IS BUILT (the tier's own refusal): union leaders and activists
## read the grievance ladder, press owners read press_freedom, judges read
## judicial independence -- the meter IS the lever, the person is a face on it.
## politicians and regional_figure carry no meter; their lever is wants +
## standing.
const KIND_METERS := {
	"union_leader": "grievance",
	"activist": "grievance",
	"press_owner": "press_freedom",
	"judge": "judicial_independence",
}

## The meters a want may name, and the only meters in the game -- the closed
## set KIND_METERS draws from. grievance reads ns.unrest_pct, press_freedom
## reads ns.press_freedom, judicial_independence reads
## Judiciary.independence_deviation(ns) -- a derived read, which is why the
## vocabulary lives here and the reads live in characters.gd where the caller
## hands the values in.
const METER_KEYS := ["grievance", "press_freedom", "judicial_independence"]

## The stances legal for each want-object family -- the family is the prefix
## before the object's first colon. `sponsor`/`oppose` judge a programme entry,
## `want` claims an office, `demand`/`defend` name a meter's direction with a
## threshold (`below` or `above`, exactly one, validated in person.gd). A want
## denied is a grudge and a want served is loyalty -- the whole price book is
## two channels, both existing registers.
const WANT_STANCES := {
	"programme": ["sponsor", "oppose"],
	"office": ["want"],
	"meter": ["demand", "defend"],
}

## The portfolios an `office:portfolio:<key>` want may name. BORROWED rather
## than re-declared, for programme_constants' own reason in reverse: a
## portfolio IS a spending line cabinet_constants owns, and a second list would
## be one answer written twice. The loader resolves wants against this, so
## content and cabinet cannot disagree about what a portfolio is called.
const CabinetK = preload("res://src/sim/cabinet_constants.gd")
const PORTFOLIO_KEYS := CabinetK.PORTFOLIO_KEYS
