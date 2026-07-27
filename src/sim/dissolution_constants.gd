extends RefCounted

## Every tunable in the dissolution model, in one file. Same shape as
## government_constants.gd and discipline_constants.gd — model parameters, not
## content, so not in data/, per docs/engine-decision.md Rule 1.
##
## `dissolution_rule`, `dissolution_lockout_months` and `dissolution_notice_months`
## in data/nations/*.json stay content: they describe a particular nation's real
## constitutional rule. Everything here is what calling a dissolution costs,
## which is the same for every nation whose rule permits one.
##
## Rationale for every number is docs/dissolution-model.md; this file is the
## values, that file is the argument.

## The cost of calling a dissolution, paid on every use through
## Government.penalise_blocs() — the same accumulator Article 49.3 and a fallen
## government already move, so inertia and every docs/opinion-model.md bound
## still apply. Set equal to government_constants.FORCE_BLOC_PENALTY: both are
## an executive going over the ordinary process's head, and section 1's
## measurement (a 57-seat spread between the worst and best approval a snap can
## return) found the structural upside large enough that the bloc penalty alone
## does not need to carry the whole downside — the gamble is real because a bad
## dissolution barely helps, not because this number is punishing.
const DISSOLUTION_BLOC_PENALTY := -0.08

## No dissolution within this many months of an already-scheduled legislative
## election. Without it, dissolving one month early is a free reroll of a vote
## that was coming anyway, paying the bloc penalty for no gamble at all.
const DISSOLUTION_BLACKOUT_MONTHS := 6
