extends RefCounted

## Dissolution and snap elections -- the player's gamble on a better mandate.
##
## Who may call one is data, dispatched on `dissolution_rule` the same way
## government.gd dispatches on `formation_method` and electoral_systems.gd on
## `election.system` -- docs/engine-decision.md Rule 1. What it costs, and how
## long the lockout that follows runs, is docs/dissolution-model.md.
##
## No engine access, no node references, no signals, and no randomness -- the
## same discipline as every other module in src/sim/. dissolve() is the one
## command this module owns, the Budget.commit()/Legislature.propose() shape;
## everything else is a pure query.

const DK = preload("res://src/sim/dissolution_constants.gd")
const GovernmentSim = preload("res://src/sim/government.gd")

## Rules an executive command can actually fire under. `confidence_failure`
## (only reachable after a lost confidence vote -- no such command exists yet)
## and `self_dissolution` (the chamber's own act, not the executive's) and
## `none` all refuse -- see refusal_reason().
const EXECUTIVE_RULES := ["executive_discretion", "head_of_state_limited"]


## Seed dissolution state from the authored rule. Runs for all ten nations,
## same as every other init_nation -- a second playable nation is then a data
## change, not a change here.
static func init_nation(ns, nation) -> void:
	ns.dissolution_rule = nation.dissolution_rule
	ns.dissolution_lockout_months = nation.dissolution_lockout_months
	ns.dissolution_notice_months = nation.dissolution_notice_months
	ns.dissolution_lockout_remaining = 0
	ns.dissolution_pending = false
	ns.dissolutions_called = 0
	ns.last_dissolution = {}


## Months from the current date to the next scheduled legislative election.
## Same shape as discipline.gd's months_to_legislative() -- negative once
## overdue, which the blackout check below treats as "not blacked out".
static func _months_to_election(state, ns) -> int:
	return (ns.next_election_year - int(state.year)) * 12 + (ns.next_election_month - int(state.month))


## True when the rule permits the player to call a dissolution right now --
## the rule allows an executive command, no dissolution is already pending, the
## lockout has expired, and the scheduled election is not close enough that
## dissolving early would just be a free reroll of a vote already coming.
static func can_dissolve(state, ns) -> bool:
	if not EXECUTIVE_RULES.has(ns.dissolution_rule):
		return false
	if ns.dissolution_pending:
		return false
	if ns.dissolution_lockout_remaining > 0:
		return false
	var months := _months_to_election(state, ns)
	if months >= 0 and months < DK.DISSOLUTION_BLACKOUT_MONTHS:
		return false
	return true


## Why the button is disabled or absent, for the panel to print. The one place
## the rule is turned into words, so the panel does not re-derive it.
static func refusal_reason(state, ns) -> String:
	match ns.dissolution_rule:
		"confidence_failure":
			return "Only reachable after a lost confidence vote."
		"self_dissolution":
			return "Only the chamber can dissolve itself."
		"none":
			return "This assembly cannot be dissolved."
	if ns.dissolution_pending:
		return "A dissolution is already under way."
	if ns.dissolution_lockout_remaining > 0:
		return "Available again in %d months." % ns.dissolution_lockout_remaining
	var months := _months_to_election(state, ns)
	if months >= 0 and months < DK.DISSOLUTION_BLACKOUT_MONTHS:
		return "Too close to the scheduled election to be worth calling."
	return ""


## The player command. Moves the legislative election to now + notice_months --
## the executive clock, where one exists, is untouched, which is what makes a
## French dissolution cost the Assembly and nothing else. The lockout is NOT
## set here; Elections._tick_nation() sets it once the snap election actually
## resolves, because France's rule is one year from the new Assembly, not from
## the decree.
static func dissolve(state, ns) -> void:
	if not can_dissolve(state, ns):
		return

	var total_months: int = int(state.year) * 12 + (int(state.month) - 1) + int(ns.dissolution_notice_months)
	ns.next_election_year = int(total_months / 12)
	ns.next_election_month = total_months % 12 + 1

	ns.dissolution_pending = true
	ns.dissolutions_called += 1
	ns.last_dissolution = {"year": state.year, "month": state.month}

	GovernmentSim.penalise_blocs(ns, DK.DISSOLUTION_BLOC_PENALTY)


## Count the lockout down. Its own module rather than folded into
## Legislature.tick_month() next to force_cooldown_months --
## docs/engine-decision.md Rule 3, one system one job. Gated on has_budget, the
## same flag every other opinion-reading system uses.
static func tick_month(state) -> void:
	for ns in state.nations.values():
		if not ns.has_budget:
			continue
		if ns.dissolution_lockout_remaining > 0:
			ns.dissolution_lockout_remaining -= 1
