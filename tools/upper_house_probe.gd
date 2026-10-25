extends SceneTree

## Upper-house probe: godot --headless --script res://tools/upper_house_probe.gd
##
## V1.1e's named measurement for the second chamber. Four tables, and the first two run
## before either constant matters, because the chamber's COMPOSITION ships no constant at
## all: it is the lower chamber's own seat share, and what makes it a check is that
## src/sim/legislature.gd resolves it on `spatial_support()` where the Assembly votes on
## `support()`. The difference between those two is the coalition bonus.
##
##   (U0) REACHABILITY, MEASURED FIRST AND WITH THE ELECTIONS IN THE LOOP. How many laws
##        a reachable played run actually proposes, how many the Assembly carries, and how
##        many of those the second chamber then refuses. docs/pledge-model.md's V1.7b
##        table measured the wrong state -- its `_tick()` omitted Elections, so 168 months
##        reported ONE run-up and ZERO judgements against a real three and two -- and
##        docs/unrest-model.md's V1.5c probe ran a government already thrown out of
##        office. That is the same error four times before this session; this table exists
##        so it is not five. If a played run proposes nothing, every band below is
##        measuring a machine the player never meets.
##
##   (U1) THE STANDING DISAGREEMENT, at new game and with no lag anywhere. For every
##        authored law: what the Assembly does, what the Senat does, and where they
##        differ. This is the table that decides whether the chamber is a live check on
##        frame one or a register nothing reads until the first election -- the decay
##        docs/diplomacy-model.md's rule exists to prevent. It also KILLS OR CONFIRMS the
##        whole design: if the two chambers never disagree, there is no second chamber
##        here, only a second reading.
##
##   (U2) UPPER_RENEWAL. Two-sided and both edges are the model's. Too fast and the
##        chamber is a mirror -- a landslide sweeps both on one day and France's Senat
##        stops being the thing that survived 2012 and 2017. Too slow and it is frozen: a
##        chamber that never catches up is a permanent veto by the dead, which is
##        docs/defence-model.md's permanent monotone charge wearing a rosette. Measured
##        over the three legislative elections a fourteen-year run contains.
##
##   (U5) UPPER_WHIP, and it is the table this session did not plan for. The design was
##        that the second chamber votes on spatial_support() ALONE -- no coalition bonus,
##        because there is no government in it. Measured, that chamber refuses seven of
##        seven authored amendments, which under France's `absolute` amendment row kills
##        V1.2c's amendment machine and V1.7c's referendum outright. No whip at all is
##        not `unwhipped`, it is `no government exists`.
##
##   (U3) UPPER_HOLD_MONTHS, and THE HOLD IS PURE TIME so this table has to establish
##        that time is a cost at all. docs/calendar-model.md's U6a finding is that every
##        observable in this project is piecewise-constant across a month, so a deferral
##        that buys nothing is the strictly-dominated shape this project has killed ten
##        times. Band (i): the widest per-bloc approval spread between a bill held N
##        months and the same bill passed at once must clear the +-3.0 poll floor --
##        docs/events-model.md's E2 correction, that an act moving a few blocs hard is
##        invisible in the headline, which is V1.3g's rural row and V1.5c's workers row a
##        fifth time. Band (ii): a bill held in the first playable term must arrive inside
##        it, and that term is 16 months.
##
##        ESCALATION DECLARED IN ADVANCE, and it is not a longer hold. If no candidate
##        clears band (i), the answer is a PRICED OVERRIDE -- a second division carrying a
##        `bloc_offset`, Article 49.3's own accumulator -- because a longer hold is the
##        constant doing the model's work and is bounded above by the term anyway.
##        docs/referendum-model.md's STATUS_QUO_PULL is the precedent for declaring the
##        escalation and honouring it.

const DataLoader = preload("res://src/core/data_loader.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const Chambers = preload("res://src/sim/chambers.gd")
const CK = preload("res://src/sim/chambers_constants.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Government = preload("res://src/sim/government.gd")

const PLAYER := "FRA"
const START_YEAR := 2026
const MONTHS := 168

## The first playable term. France's presidential election is May 2027 against a January
## 2026 start -- docs/electoral-systems.md -- so a bill held on day one has this many
## months to arrive in.
const FIRST_TERM_MONTHS := 16

## The published-poll floor, docs/opinion-model.md's. Fixed here BEFORE any sweep so the
## numbers can falsify the design rather than be fitted to it.
const POLL_FLOOR_PTS := 3.0

const RENEWAL_SWEEP := [
	0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
	0.55, 0.60, 0.65, 0.70, 0.80, 0.90, 1.00,
]
const HOLD_SWEEP := [1, 2, 3, 4, 6, 8, 9, 12, 15, 18, 24]
const OFFSET_SWEEP := [0.02, 0.04, 0.06, 0.08, 0.10, 0.15, 0.20, 0.25, 0.30]

## A budget a government can hold office under -- tools/balance_probe.gd's `managed`.
##
## A DELTA AGAINST THE NATION'S OWN STARTING LINES, and the first version of this probe
## committed it as ABSOLUTES: `income: 0.5` set France's income tax to half a percent
## instead of raising VAT by three, the government was thrown out at month 15, and
## Elections.tick_month() returns early once `in_government` is false -- so the run saw
## ZERO legislative elections in fourteen years and table U2 reported `no election
## reached` for every candidate. Two tables measuring the wrong state from one
## four-character mistake.
const MANAGED_DELTA := {
	"spending_pct_gdp": {"defence": -1.4},
	"tax_rates_pct": {"vat": 3.0},
}


## The delta turned back into the absolute values Budget.commit() expects, against the
## nation's own starting lines -- tools/balance_probe.gd's _resolve_pending().
static func _managed(ns) -> Dictionary:
	var out := {}
	for channel in MANAGED_DELTA:
		var lines := {}
		var live: Dictionary = ns.spending_pct_gdp if channel == "spending_pct_gdp" else ns.tax_rates_pct
		for key in MANAGED_DELTA[channel]:
			lines[key] = maxf(0.0, float(live.get(key, 0.0)) + float(MANAGED_DELTA[channel][key]))
		out[channel] = lines
	return out


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_reachability_table(loader)
	_disagreement_table(loader)
	_renewal_table(loader)
	_hold_table(loader)
	_override_table(loader)
	_whip_table(loader)
	quit(0)


# ---------------------------------------------------------------------------
# (U0) Reachability
# ---------------------------------------------------------------------------

func _reachability_table(loader) -> void:
	print("")
	print("(U0) REACHABILITY -- a played run, elections in the loop, a player who stays in office")
	print("")

	var counts := _played_run(loader)
	print("  months in office            %d of %d" % [counts["months"], MONTHS])
	print("  legislative elections seen  %d" % counts["elections"])
	print("  laws proposed               %d" % counts["proposed"])
	print("  lost the Assembly           %d" % counts["lost_lower"])
	print("  carried the Assembly        %d" % counts["carried_lower"])
	print("  refused by the Senat        %d  (blocked %d, held %d)" % [
		counts["blocked"] + counts["held"], counts["blocked"], counts["held"]])
	print("  released after a hold       %d  -- each one an OVERRIDE, priced" % counts["released"])
	print("  struck down by the court    %d" % counts["struck"])
	print("  in force                    %d" % counts["in_force"])
	print("  worst bloc_offset reached   %.4f of %.2f" % [counts["worst_offset"], 1.0])
	if counts["proposed"] == 0:
		print("  ** UNREACHABLE: a played run proposes nothing, so every band below is about")
		print("     a machine the player never meets.")


## Fourteen years of a player who proposes the first legal law every month and stays in
## office. THE PLAYER MUST STAY IN OFFICE, and the first version of this did not:
## `managed` alone lost the 2027 presidential election at month 15 and the table
## reported 15 proposals, zero elections and nothing carried -- V1.5c's probe running a
## government already thrown out, and V1.7b's reachability table missing its elections,
## a FIFTH time. The run continues past a lost office here rather than stopping, because
## what is being counted is the machine's exposure over fourteen years and the assembly
## keeps sitting whoever is president.
func _played_run(loader) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _managed(state.player()))
	var ns = state.player()
	var out := {
		"months": 0, "elections": 0, "proposed": 0, "lost_lower": 0, "carried_lower": 0,
		"blocked": 0, "held": 0, "released": 0, "struck": 0, "in_force": 0,
		"worst_offset": 0.0,
	}

	for i in range(MONTHS):
		var held_before: int = ns.held_bills.size()
		# V5.2 b+ R2: the bill tabled last month divides at this close's first step.
		var result: Dictionary = _tick(state, loader, i).get("division", {})
		if ns.in_government:
			out["months"] = int(out["months"]) + 1
		if int(ns.last_election.get("year", 0)) == state.year \
				and int(ns.last_election.get("month", 0)) == state.month:
			out["elections"] = int(out["elections"]) + 1
		if ns.held_bills.size() < held_before:
			out["released"] = int(out["released"]) + (held_before - ns.held_bills.size())
		if not result.is_empty():
			_count(out, result)
		for bloc in ns.bloc_offset:
			out["worst_offset"] = maxf(float(out["worst_offset"]), absf(float(ns.bloc_offset[bloc])))

		# THE FIRST VERSION PROPOSED available()[0] AND LOST 168 DIVISIONS OUT OF 168.
		# A law with no cooldown that fails stays available, so the run re-proposed the
		# same doomed bill every month for fourteen years and nothing ever reached the
		# second chamber at all. `available()` returns what is LEGAL and nothing models
		# what the player WANTS -- docs/calendar-model.md's U6a finding, reached from a
		# third direction -- so the probe supplies the missing half itself and proposes
		# the first bill the Assembly would actually carry.
		var law = _winnable(ns, loader, Legislature.available(ns, loader.laws))
		if law == null:
			continue
		Legislature.propose(state, loader, law, false, false)
		out["proposed"] = int(out["proposed"]) + 1
	return out


## One division's outcome into the run's counts.
static func _count(out: Dictionary, result: Dictionary) -> void:
	if result.has("upper_passed"):
		out["carried_lower"] = int(out["carried_lower"]) + 1
		if bool(result.get("blocked_by_upper", false)):
			out["blocked"] = int(out["blocked"]) + 1
		elif bool(result.get("held_by_upper", false)):
			out["held"] = int(out["held"]) + 1
		elif bool(result.get("struck_down", false)):
			out["struck"] = int(out["struck"]) + 1
		else:
			out["in_force"] = int(out["in_force"]) + 1
	elif bool(result.get("struck_down", false)):
		out["carried_lower"] = int(out["carried_lower"]) + 1
		out["struck"] = int(out["struck"]) + 1
	elif bool(result.get("passed", false)):
		out["carried_lower"] = int(out["carried_lower"]) + 1
		out["in_force"] = int(out["in_force"]) + 1
	else:
		out["lost_lower"] = int(out["lost_lower"]) + 1


## The first law on the open list the Assembly would carry, or null.
static func _winnable(ns, loader, open: Array):
	var party_list: Array = loader.parties.get(PLAYER, [])
	for law in open:
		if bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			return law
	return null


# ---------------------------------------------------------------------------
# (U1) The standing disagreement
# ---------------------------------------------------------------------------

func _disagreement_table(loader) -> void:
	print("")
	print("(U1) THE STANDING DISAGREEMENT at new game, no lag anywhere")
	print("")

	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()
	var party_list: Array = loader.parties.get(PLAYER, [])

	print("  Assembly %d seats, %s %d seats, composition identical (no tilt)" % [
		ns.assembly_seats, ns.upper_chamber_name, ns.upper_seats
	])
	var chamber := Chambers.seats(ns)
	var line := "   "
	for party in party_list:
		line += " %s %d/%d" % [
			party.id.substr(0, 10), int(ns.seats_by_party.get(party.id, 0)),
			int(chamber.get(party.id, 0))
		]
	print(line)
	print("")
	print("  %-34s %-9s %-9s %s" % ["law", "assembly", "senat", "power"])

	var agree := 0
	var carried := 0
	var lower_yes_upper_no := 0
	var lower_no_upper_yes := 0
	for law in loader.laws:
		var lower := Legislature.resolve_vote(ns, party_list, law, false)
		var upper := Legislature.resolve_upper(ns, party_list, law)
		var lo: bool = bool(lower["passed"])
		var hi: bool = bool(upper["passed"])
		if lo:
			carried += 1
		if lo == hi:
			agree += 1
		elif lo:
			lower_yes_upper_no += 1
		else:
			lower_no_upper_yes += 1
		if lo and not hi:
			print("  %-34s %-9s %-9s %s" % [
				law.id, "yes %d-%d" % [int(lower["yes_seats"]), int(lower["no_seats"])],
				"NO %d-%d" % [int(upper["yes_seats"]), int(upper["no_seats"])],
				Chambers.power_over(ns, law)
			])

	print("")
	print("  agree %d, Assembly yes / Senat no %d, Assembly no / Senat yes %d, of %d laws" % [
		agree, lower_yes_upper_no, lower_no_upper_yes, loader.laws.size()
	])
	print("  the Assembly carries %d of %d; the Senat refuses %d of those, %.0f %%" % [
		carried, loader.laws.size(), lower_yes_upper_no,
		0.0 if carried == 0 else 100.0 * float(lower_yes_upper_no) / float(carried)
	])
	if lower_yes_upper_no == 0:
		print("  ** DEAD: the second chamber never refuses a bill the Assembly carries, so it")
		print("     is a second reading and not a second chamber.")


# ---------------------------------------------------------------------------
# (U2) UPPER_RENEWAL
# ---------------------------------------------------------------------------

func _renewal_table(loader) -> void:
	print("")
	print("(U2) UPPER_RENEWAL -- the lag, measured over a run's legislative elections")
	print("")
	print("  Band (i)  the chamber must LAG: after the run's elections the Senat's share")
	print("            must differ from the Assembly's by more than one seat in the")
	print("            smallest chamber on the roster, which is 1/46 = 0.0217.")
	print("  Band (ii) the chamber must be CATCHABLE inside the horizon: the lag decays")
	print("            geometrically, and the elections it takes to reach band (i)'s floor")
	print("            must be at most the THREE a fourteen-year run holds. Otherwise the")
	print("            dead hold a veto no amount of winning can shift.")
	print("            THIS CLAUSE WAS WRONG TWICE. The first only asked that the distance")
	print("            FALL, which every rate above zero satisfies, so the passing set ran")
	print("            to the bottom of the grid and V1.5b's diagnostic fired. The second")
	print("            asked it to HALVE over two elections, which is a ratio nobody")
	print("            measured, and it cut France's real 50 %% renewal by a hair -- 0.532")
	print("            against 0.500. This one is anchored on the harness instead.")
	print("")
	print("  %-9s %-11s %-11s %-11s %-7s %s" % [
		"renewal", "L1 after 1", "after 2", "after 3", "catch", "clauses"])

	var passing: Array = []
	for renewal in RENEWAL_SWEEP:
		var distances := _renewal_run(loader, renewal)
		if distances.is_empty():
			print("  %-9.2f (no election reached)" % renewal)
			continue
		var lags: bool = distances[distances.size() - 1] > 1.0 / 46.0
		# CATCHABLE WITHIN THE HORIZON, and the horizon is the harness's fourteen years
		# rather than a ratio somebody picked. The distance decays geometrically, so the
		# elections it takes to fall under band (i)'s floor is a closed form off the first
		# two -- and a fourteen-year run holds three legislative elections.
		var catch_in := _catch_elections(distances)
		var settles: bool = catch_in <= 3.0
		var cells := "  %-9.2f" % renewal
		for k in range(3):
			cells += " %-11s" % ("%.4f" % distances[k] if k < distances.size() else "-")
		cells += " %-7s %s%s" % [
			("%.2f" % catch_in) if catch_in < 99.0 else "never",
			"Y" if lags else "n", "Y" if settles else "n"]
		if lags and settles:
			cells += "  PASS"
			passing.append(renewal)
		print(cells)

	print("")
	if passing.is_empty():
		print("  ** NO CANDIDATE PASSES.")
		return
	var mid: float = passing[passing.size() / 2]
	print("  passing %s" % [passing])
	print("  midpoint of the passing set: %.2f" % mid)


## One run at an emulated renewal rate. Returns the L1 distance between the Senat's share
## and the Assembly's, once per legislative election.
##
## EMULATED rather than set, because a probe cannot change a `const` at runtime --
## docs/inflation-model.md's V1.6b correction, where the first version rescaled a
## measured headline from the shipped value and the passing interval MOVED when the
## shipped value moved.
func _renewal_run(loader, renewal: float) -> Array:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _managed(state.player()))
	var ns = state.player()
	var party_list: Array = loader.parties.get(PLAYER, [])
	var share: Dictionary = Chambers.target_share(ns, party_list)
	var out: Array = []

	# THE FIRST VERSION OF THIS LOOP DETECTED AN ELECTION BY COMPARING SEAT DICTIONARIES
	# and reported `no election reached` for every candidate, on a run that holds three.
	# ns.seats_by_party is REPLACED at an election, and a deterministic vote share over an
	# unchanged electorate can return the identical allocation -- so the comparison was
	# asking whether the result differed, not whether the election happened. Read the date
	# off ns.last_election instead, which is what table U0 already does.
	for i in range(MONTHS):
		_tick(state, loader, i)
		if int(ns.last_election.get("year", 0)) != state.year \
				or int(ns.last_election.get("month", 0)) != state.month:
			continue
		# A legislative election has rewritten the Assembly. Blend by hand.
		var target: Dictionary = Chambers.target_share(ns, party_list)
		var blended := {}
		var total := 0.0
		for party_id in target:
			var was: float = float(share.get(party_id, 0.0))
			var value: float = was + (float(target[party_id]) - was) * renewal
			blended[party_id] = value
			total += value
		if total > 0.0:
			for party_id in blended:
				blended[party_id] = float(blended[party_id]) / total
		share = blended
		out.append(_l1(share, target))
	return out


## How many elections until the lag falls under one seat of the smallest chamber, read
## off the geometric ratio of the first two. 99.0 for a chamber that never catches up.
func _catch_elections(distances: Array) -> float:
	if distances.size() < 2 or float(distances[0]) <= 0.0:
		return 99.0
	var floor_value := 1.0 / 46.0
	if float(distances[0]) <= floor_value:
		return 0.0
	var ratio: float = float(distances[1]) / float(distances[0])
	if ratio <= 0.0:
		return 1.0
	if ratio >= 1.0:
		return 99.0
	return log(floor_value / float(distances[0])) / log(ratio)


func _l1(a: Dictionary, b: Dictionary) -> float:
	var total := 0.0
	for key in b:
		total += absf(float(a.get(key, 0.0)) - float(b[key]))
	return total / 2.0


# ---------------------------------------------------------------------------
# (U3) UPPER_HOLD_MONTHS
# ---------------------------------------------------------------------------

func _hold_table(loader) -> void:
	print("")
	print("(U3) UPPER_HOLD_MONTHS -- is TIME a cost at all?")
	print("")
	print("  Band (i)  the widest per-bloc approval spread between a bill held N months")
	print("            and the same bill in force at once must clear the %.1f poll floor." % POLL_FLOOR_PTS)
	print("  Band (ii) a bill held on day one must arrive inside the first playable term,")
	print("            which is %d months." % FIRST_TERM_MONTHS)
	print("")

	var law = _held_law(loader)
	if law == null:
		print("  ** no reviewable law with a bloc_offset to measure on.")
		return
	print("  measured on %s" % law.id)
	print("")
	print("  %-7s %-11s %-11s %s" % ["hold", "worst bloc", "headline", "clauses"])

	var passing: Array = []
	for hold in HOLD_SWEEP:
		var spread := _hold_spread(loader, law, hold)
		var legible: bool = spread["bloc"] >= POLL_FLOOR_PTS
		var in_term: bool = hold <= FIRST_TERM_MONTHS
		var row := "  %-7d %-11.4f %-11.4f %s%s" % [
			hold, spread["bloc"], spread["headline"],
			"Y" if legible else "n", "Y" if in_term else "n"
		]
		if legible and in_term:
			row += "  PASS"
			passing.append(hold)
		print(row)

	print("")
	if passing.is_empty():
		print("  ** NO CANDIDATE CLEARS BAND (i). The escalation declared in")
		print("     src/sim/chambers_constants.gd fires: the hold gains a PRICED OVERRIDE")
		print("     rather than being lengthened.")
		return
	print("  passing %s" % [passing])
	print("  headline is recorded rather than banded against: an act that moves a few blocs")
	print("  hard is invisible in it, which is docs/events-model.md's E2 correction.")


## A law the Senat actually refuses, carrying a bloc_offset so the hold has something to
## be measured on. Picked from the content rather than named, so a content edit cannot
## silently leave this table measuring a law nobody can propose.
func _held_law(loader):
	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()
	var party_list: Array = loader.parties.get(PLAYER, [])
	for law in loader.laws:
		if law.constitutional:
			continue
		if not law.effects.has("bloc_offset"):
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			continue
		if bool(Legislature.resolve_upper(ns, party_list, law)["passed"]):
			continue
		return law
	return null


## Worst per-bloc and headline approval gap at the end of the first term, between a run
## where the bill is in force from month 1 and one where it arrives at month N.
func _hold_spread(loader, law, hold: int) -> Dictionary:
	var early := _run_with_law_at(loader, law, 0)
	var late := _run_with_law_at(loader, law, hold)
	var worst := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		worst = maxf(worst, absf(float(early["bloc"].get(bloc, 0.0)) - float(late["bloc"].get(bloc, 0.0))))
	return {
		"bloc": worst,
		"headline": absf(float(early["headline"]) - float(late["headline"])),
	}


func _run_with_law_at(loader, law, arrives: int) -> Dictionary:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _managed(state.player()))
	var ns = state.player()
	for i in range(FIRST_TERM_MONTHS):
		if i == arrives:
			Legislature.apply(state, ns, law, loader)
		_tick(state, loader, i)
	return {"headline": ns.overall_approval_pct, "bloc": ns.bloc_approval.duplicate()}


# ---------------------------------------------------------------------------
# (U4) UPPER_OVERRIDE_OFFSET
# ---------------------------------------------------------------------------

## SWEPT, NOT SOLVED, and the first version assumed a closed form it did not have.
## docs/referendum-model.md measured the approval response to `bloc_offset` as exactly
## linear at V1.7c and this table was written to reuse that -- measured here it comes
## back 3.96 points of approval at an offset of 0.10 and 8.83 at 0.20, super-linear by
## a fifth, because a run started from new game feeds the offset through the grievance
## and the press before the term ends. A slope measured on one path is not a slope.
func _override_table(loader) -> void:
	print("")
	print("(U4) UPPER_OVERRIDE_OFFSET -- what overriding the second chamber costs")
	print("")
	print("  Band (i)  ONE override must move the headline at least one point -- V1.7a's")
	print("            ruler, because a swing the published polls cannot resolve is not a")
	print("            price the player can act on.")
	print("  Band (ii) a whole career of them must leave BLOC_OFFSET_MAX slack, so the")
	print("            clamp is a guard rail rather than the thing setting the number.")
	print("")
	var counts := _played_run(loader)
	var overrides: int = int(counts["released"])
	print("  a played run releases %d held bills, so a career is %d overrides" % [
		overrides, overrides])
	print("")
	print("  %-9s %-13s %-13s %s" % ["offset", "one costs", "career stack", "clauses"])
	var passing: Array = []
	var base := _run_with_offset(loader, 0.0)
	for offset in OFFSET_SWEEP:
		var one: float = absf(base - _run_with_offset(loader, -offset))
		var stack: float = offset * float(maxi(overrides, 1))
		var legible: bool = one >= 1.0
		var slack: bool = stack < 1.0
		var row := "  %-9.3f %-13.4f %-13.4f %s%s" % [
			offset, one, stack, "Y" if legible else "n", "Y" if slack else "n"]
		if legible and slack:
			row += "  PASS"
			passing.append(offset)
		print(row)
	print("")
	if passing.is_empty():
		print("  ** NO CANDIDATE PASSES.")
		return
	print("  passing [%.3f, %.3f], midpoint %.4f" % [
		passing[0], passing[passing.size() - 1],
		(float(passing[0]) + float(passing[passing.size() - 1])) / 2.0])



func _run_with_offset(loader, offset: float) -> float:
	var state = GameState.new_game(loader, PLAYER)
	Budget.commit(state, _managed(state.player()))
	var ns = state.player()
	if offset != 0.0:
		for bloc in OpinionK.BLOC_KEYS:
			ns.bloc_offset[bloc] = offset
	for i in range(FIRST_TERM_MONTHS):
		_tick(state, loader, i)
	return ns.overall_approval_pct


# ---------------------------------------------------------------------------
# (U5) UPPER_WHIP
# ---------------------------------------------------------------------------

func _whip_table(loader) -> void:
	print("")
	print("(U5) UPPER_WHIP -- how much of the government's whip survives the second chamber")
	print("")
	print("  Band (i)   it must refuse at least ONE ordinary bill the Assembly carries, or")
	print("             it is a second reading and not a second chamber.")
	print("  Band (ii)  at least ONE authored amendment must survive BOTH chambers, or")
	print("             V1.2c's amendment machine and V1.7c's referendum are dead in the")
	print("             nation the game is about. THIS IS THE CLAUSE THE SESSION MISSED:")
	print("             with no whip at all the Senat refuses 7 of 7, and France's")
	print("             `absolute` amendment row makes that fatal.")
	print("  Band (iii) a MAJORITY of the bills the Assembly carries must survive.")
	print("")

	var state = GameState.new_game(loader, PLAYER)
	var ns = state.player()
	var party_list: Array = loader.parties.get(PLAYER, [])
	print("  %-7s %-13s %-13s %-15s %s" % [
		"whip", "ord carried", "ord refused", "amend survive", "clauses"])

	var passing: Array = []
	for step in range(0, 21):
		var whip: float = float(step) / 20.0
		var carried := 0
		var refused := 0
		var amend := 0
		var amend_total := 0
		for law in loader.laws:
			var lower := Legislature.resolve_vote(ns, party_list, law, law.constitutional)
			var upper := _upper_at(ns, party_list, law, whip)
			if law.constitutional:
				amend_total += 1
				if bool(lower["passed"]) and upper:
					amend += 1
			elif bool(lower["passed"]):
				carried += 1
				if not upper:
					refused += 1
		var c1: bool = refused >= 1
		var c2: bool = amend >= 1
		var c3: bool = float(carried - refused) > float(carried) / 2.0
		var row := "  %-7.2f %-13d %-13d %-15s %s%s%s" % [
			whip, carried, refused, "%d of %d" % [amend, amend_total],
			"Y" if c1 else "n", "Y" if c2 else "n", "Y" if c3 else "n"]
		if c1 and c2 and c3:
			row += "  PASS"
			passing.append(whip)
		print(row)

	print("")
	if passing.is_empty():
		print("  ** NO CANDIDATE PASSES.")
		return
	print("  passing [%.2f, %.2f], both edges the MODEL'S and both interior to the swept" % [
		passing[0], passing[passing.size() - 1]])
	print("  range, so the midpoint selects: %.2f" % [
		(float(passing[0]) + float(passing[passing.size() - 1])) / 2.0])
	print("  SHIPPED: %.2f" % CK.UPPER_WHIP)


## The second chamber's verdict at an EMULATED whip -- a probe cannot change a `const`
## at runtime, V1.6b's correction.
func _upper_at(ns, party_list: Array, law, whip: float) -> bool:
	var chamber := Chambers.seats(ns)
	var yes := 0
	var no := 0
	for party in party_list:
		var seats: int = int(chamber.get(party.id, 0))
		if seats <= 0:
			continue
		var line: float = clampf(
			Legislature.spatial_support(ns, party, law)
				+ whip * Government.coalition_bonus(ns, party),
			-1.0, 1.0
		)
		match Legislature.vote_of(line):
			"yes": yes += seats
			"no": no += seats
	return yes > no


# ---------------------------------------------------------------------------

## Returns the month's report: V5.2 b+ R2's tabled bill divides at its first step,
## `report["division"]`.
func _tick(state, loader, i: int) -> Dictionary:
	state.month = (i + 1) % 12 + 1
	state.year = START_YEAR + (i + 1) / 12

	# The game's own month (src/sim/world_month.gd), not a copy of it: the copy
	# this replaced had fallen behind main.gd by several systems.
	return WorldMonth.tick_month(state, loader)
