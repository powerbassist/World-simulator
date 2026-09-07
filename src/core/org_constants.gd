extends RefCounted

## Bounds for data/orgs/*.json, checked at load. The VALUES an org carries are
## content -- bonuses, durations, positions live in the org files; what belongs
## here is only the envelope a typo'd file cannot be allowed to escape, the
## same split opinion_constants.gd draws between its label tables and the
## content that references them.

## How many organisations the register may bind. Four ship (eu, eurozone,
## schengen, nato); this is a ceiling on load errors and on tick cost, not a
## design target -- a fifth org is a data edit, not a change here.
const MAX_ORGS := 8

## The standing prices an org may carry. A key outside this list on an org file
## is a load error, not a silently inert field -- the same rule
## bloc_proposal.gd applies to a constraint naming an unknown field.
const ORG_EFFECT_KEYS := ["relations_bonus", "trade_bonus"]

const MAX_RELATIONS_BONUS := 30.0
const MAX_TRADE_BONUS := 1.0

## Negotiation countdowns are whole years at least -- a one-month accession is
## not a multi-year domestic fight, which is the row this machinery exists for.
const MIN_ACCESSION_MONTHS := 12
const MAX_ACCESSION_MONTHS := 60
