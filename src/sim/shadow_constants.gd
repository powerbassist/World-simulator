extends RefCounted

## V5.2c, the shadows' numbers: corruption, the affair, lies and exposure. The
## design is docs/design/v5.2-spec.md ("Corruption, in the author's four
## currencies", "Lies and their detection"); the bands are docs/design/bands-v5.2.md
## B6, B7 and B8; the plan is .superpowers/sdd/v5.2c-plan.md.

const PresidentK = preload("res://src/sim/president_constants.gd")

## The four ways a shadow is found out, named once (the spec, the currencies table).
const ROUTES := ["press", "courts", "auditors", "turned"]

## Which evidence each route can reach. The spec's table: the press and the courts
## follow personal money; the auditors read the party's accounts and the spending
## lines; a turned person can talk about anything they took part in. The affair's
## routes are the plan's reading (its Call 3): the press, and a lover who turns.
const ROUTE_KINDS := {
	"press": ["personal_wealth", "affair"],
	"courts": ["personal_wealth", "diverted_budget"],
	"auditors": ["party_money", "diverted_budget"],
	"turned": PresidentK.EVIDENCE_KINDS,
}
