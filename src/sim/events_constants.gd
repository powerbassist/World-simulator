extends RefCounted

## Tuning for src/sim/events.gd -- V1.8, the last block of the V1 tier. The model and
## the justification for every number is docs/events-model.md.
##
## ONE TUNED CONSTANT, and everything else on this page is a BOUND. That is
## src/sim/projects_constants.gd's and src/sim/pledges_constants.gd's position reached a
## third time, and it is the shape the content forced rather than a target: an event's
## hazard, its deadline and its effects are three independent facts about that event, so
## each is authored and each is only bounded here. src/core/investment_action.gd's
## refusal of a second authored strength is the rule -- a number solved against another
## number is one strength written twice -- and it does not fire, because none of the
## three is derivable from the others.
##
## The one dial is EVENT_COOLDOWN_MONTHS, and it is tuned rather than bounded for a
## reason nothing in the content can supply: how often the world interrupts you is a
## property of the GAME, not of any one event.

## How long after an event resolves before any other may fire.
##
## THE SESSION'S ONLY TUNED CONSTANT. Selected by tools/events_probe.gd table E1
## against a band fixed before the sweep -- between 2 and 6 events over a five-year
## term in the median reachable regime. Two-sided by construction, so V1.5c's
## correction applies (the midpoint governs, not an edge) and V1.5b's diagnostic is
## checked (a value at the endpoint of the swept grid is a suspect, not a result).
##
## The band's two halves are two different failures. Under 2 a term the machine is
## decorative -- §8's own falsifier, "the loop legible but inert", arriving from the
## other side. Over 6 the message column, which holds six cards and drops the oldest,
## starts burying an event under the next one, and an occasion the player never read is
## not an occasion.
const EVENT_COOLDOWN_MONTHS := 9

## Bounds on an event's authored monthly hazard, once its preconditions hold.
##
## A BOUND, NOT A DIAL. The floor exists because a hazard of zero is content that never
## loads its own consequence -- V1.3f's property that nothing on the law list does
## nothing -- and the ceiling because at 1.0 the "semi-random" half of §8's own sentence
## disappears and the model is precondition-only, which is bullet 1 without bullet 2.
const LIKELIHOOD_MIN := 0.005
const LIKELIHOOD_MAX := 0.50

## Bounds on an event's authored deadline, in months.
##
## The floor is 1 because an event that resolves in the month it arrives has no
## deadline: the card and the default would land together and there would be nothing to
## respond to. The ceiling is a presidential term's own quarter -- long enough for a
## slow-burning inquiry, short enough that no event outlives the government it landed on.
const RESPOND_MONTHS_MIN := 1
const RESPOND_MONTHS_MAX := 15

## How many resolved events the ledger keeps. src/sim/unrest_constants.gd's ACTS_KEPT,
## and a bound for its reason: the register is the panel's whole memory, so this is what
## keeps a save file finite.
const EVENTS_KEPT := 24

## Where the hazard's deterministic draw is anchored. tools/balance_probe.gd and
## tests/test_balance.gd both set state.year AFTER new_game(), so an epoch read off live
## state would move under the harness -- cycle_constants.CYCLE_EPOCH_YEAR records the
## same trap and takes the same way out.
const EVENT_EPOCH_YEAR := 2026
const EVENT_EPOCH_MONTH := 1

## The precondition fields an event may NOT name, expressed as a refusal beside
## legislature_constants.PRECONDITION_FIELDS rather than as a second list.
##
## THE SHAPE IS THE POINT. legislature.gd already records that its whitelist and its
## _read_field() match are the same list in two places and that a session can add half of
## it; a third copy here would be the same failure again with the same excuse. So there
## is ONE list, and this is a subtraction from it -- src/core/law.gd's
## ORDINARY_INSTITUTIONAL_KEYS split, which is also a subtraction rather than a
## parallel table.
##
## WHY `overall_approval_pct` IS REFUSED. Every choice's core price is `bloc_offset`, a
## clamped permanent accumulator that reaches approval directly. An event preconditioned
## on low approval and priced in approval is positive feedback with no damping anywhere
## in the loop -- so a president who slips once is handed a crisis, pays for it in
## approval, and is handed another. docs/credit-model.md deleted its own deficit term
## for exactly that reason (the session's only positive feedback loop went with it), and
## the shape at the end of the spiral is economy-model.md's IMPULSE_MAX a sixth time.
##
## docs/pledge-model.md refused the same field on a DIFFERENT argument -- a promise
## about your own approval is circular -- and the two refusals agreeing about one field
## for two reasons is worth more than either.
const EVENT_PRECONDITION_REFUSED := ["overall_approval_pct"]

## The offices an event may name as its subject. U6b's rule verbatim: a law names an
## OFFICE and the nation's own data names the person, so nothing in src/sim/ ever holds
## a person id on this channel and "no mechanism on a person" stays true by
## construction. src/ui/main.gd resolves the label at card time.
const SUBJECT_OFFICES := ["head_of_government", "head_of_state", "largest_party_leader"]
