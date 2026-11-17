extends RefCounted

## Whether a law may be put to the Assembly now, and if not, which rule shuts it -- the scan
## Legislature.available() runs, split out at the Bills second pass (the author's "A : les
## rayons") so a shut law can keep its place on its shelf and say WHY on its row. One gate, two
## readers: available() keeps the laws whose gate reads "", and the catalogue prints the flag's
## sentence, so the row can never call open a law the press would refuse. Writes nothing.
##
## Its own file because legislature.gd sits at its size ceiling, and a LEAF on purpose:
## legislature.gd preloads this file, so this file preloads nothing that preloads it back.

const Referendum = preload("res://src/sim/referendum.gd")
const LawConditions = preload("res://src/sim/law_conditions.gd")

## The flags, in the order the scan checks them: the first rule that shuts a law names it.
const PASSED := "passed"            ## a once-only law already carried
const COOLDOWN := "cooldown"        ## divided recently: ns.law_cooldown_months holds its wait
const NOTHING_TO_REPEAL := "nothing_to_repeal"
const CONSTITUTION := "constitution"  ## another constitution's law, or a change of system this one forbids
const IN_FORCE := "in_force"        ## the electoral method it sets is already the nation's
const REFERENDUM := "referendum"    ## put to the country, the vote in flight
const HELD := "held"                ## carried, and the second chamber is holding it
const ASSEMBLY := "assembly"        ## the Assembly's own backbench has it tabled
const CONDITIONS := "conditions"    ## its preconditions are not met


## The rule that shuts `law` for `ns` now, "" when it may be proposed.
static func shut(ns, law) -> String:
	if law.once and ns.passed_law_ids.has(law.id):
		return PASSED
	if ns.law_cooldown_months.has(law.id):
		return COOLDOWN
	# V4.2 ultra pass 2. A repeal whose target has no ledger entry is not
	# proposable: repeal_target_legal() gates it at composition, so a target
	# gone from the book means the repeal was ALREADY carried -- re-offering
	# it would pass a carried no-op (quiet since the pass-4 finding made the
	# empty-ledger subtraction a no-op, but a button that repeals nothing is
	# still the half-removed act class). Kills both the after-cooldown no-op
	# and the propose-path half of the two-repeals-of-one-target case -- the
	# held window's half is the moot release's, in _tick_held_bills; the
	# window self-heals the other way too, since a re-passed target re-opens
	# its own repealer here.
	if law.repeals != "" and not ns.law_ledger.has(law.repeals):
		return NOTHING_TO_REPEAL
	if not constitution_allows(ns, law):
		return CONSTITUTION
	if already_in_force(ns, law):
		return IN_FORCE
	# One referendum at a time, and while one is in flight nothing else may be
	# put to the country. A second live question is not a bound that needed a
	# constant -- it is what "the country votes on this" means.
	if Referendum.is_pending(ns) and Referendum.pending_law_id(ns) == law.id:
		return REFERENDUM
	# V1.1e. A bill the second chamber is holding is IN FLIGHT and cannot be
	# proposed again while it waits -- the same thing the line above says about a
	# question already put to the country, and for the same reason: proposing it
	# twice would let the player restart the clock they are waiting out.
	if ns.held_bills.has(law.id):
		return HELD
	# V4.2 T6. A bill the assembly's own backbench has tabled is IN FLIGHT on
	# exactly the held_bills grounds: the player proposing the same law inside
	# the endorsement window would divide it twice and apply the effects twice,
	# which is the double-application guard this scan exists to keep.
	if in_assembly_tray(ns, law.id):
		return ASSEMBLY
	if not LawConditions.preconditions_met(ns, law.preconditions):
		return CONDITIONS
	return ""


## Whether the assembly's own backbench has this law tabled.
static func in_assembly_tray(ns, law_id: String) -> bool:
	for entry in ns.assembly_bills.values():
		if String(entry.get("law_id", "")) == law_id:
			return true
	return false


## The constitutional gate: a law authored for a template the nation is not under,
## or a change of system its constitution forbids. available() runs it at proposal;
## MANDATORY does not need asking -- propose() reads that off the nation instead.
static func constitution_allows(ns, law) -> bool:
	return (not law.constitutional or law.systems.has(ns.system_id)) and (not law.changes_system or ns.permits_system_change)


## An electoral-reform Act that names the method the nation already uses changes
## nothing, and a button that changes nothing is the bug V1.3e's screenshot pass
## found on the diplomacy panel. Checked in code rather than by asking content to
## remember it -- src/sim/campaign.gd's _op_legal() and src/sim/projects.gd's
## available() give the argument -- and it is checked here rather than as a
## precondition because PRECONDITION_FIELDS is numeric and an electoral system is a
## string, which is a schema difference and not an oversight.
static func already_in_force(ns, law) -> bool:
	var inst: Dictionary = law.effects.get("institutional", {})
	if not inst.has("election_system"):
		return false
	if String(inst["election_system"]) != ns.election_system:
		return false
	# The method matches; the law is still live if it also moves the threshold.
	if inst.has("election_threshold_pct"):
		return is_equal_approx(float(inst["election_threshold_pct"]), ns.election_threshold_pct)
	return true
