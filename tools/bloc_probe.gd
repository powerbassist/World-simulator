extends SceneTree

## Bloc envelope probe: godot --headless --script res://tools/bloc_probe.gd
##
## V1.3d's named measurement. Table (a) runs BEFORE anything else in the session
## exists, because it is pure arithmetic over src/sim/opinion_constants.gd and it
## is what sets the six BLOC_SALIENCE_BASE rows every later step depends on.
## Tables (b) onward need src/sim/bloc.gd and are run after the module and before
## data/bloc-proposals/*.json -- the same split tools/coercion_probe.gd used, which
## preloads src/sim/coercion.gd and still preceded measures.json.
##
##   (a) THE DILUTION. A twelfth ISSUE_KEYS entry is the call three sessions
##       deferred to this one, and docs/tiers/declined.md records that EVERY tuned
##       opinion constant was measured against the six-row table it changes. Rows
##       currently sum to 1.0, so adding `europe` at weight w scales that bloc's
##       other weights by 1/(1+w). The question is not whether that is zero -- it
##       is not -- but whether it moves the RATIO S10's finding was about:
##       public_finances against the five spending lines. Prints both, before and
##       after, and the per-bloc scaling that produces the difference.
##
##   (b) LEGIBILITY -- THE ESCALATION TRIGGER. One bloc rule in force and defied,
##       against a control. Does anything the player can READ move past
##       poll_noise.gd's floor? Unlike V1.3b's and V1.3c's triggers this one is
##       FRA/DEU-shaped, because GBR is not a member: for a non-member the bloc is
##       something done to it rather than a lever it holds.
##
##   (c) THE TRANSFER. What a contribution is worth against a tax point, so the
##       budget line is legible on the panel it is printed on.
##
##   (d) THE VOTE. Whether the player is ever actually outvoted, swept over the
##       proposal's position -- a council the player always wins is a rubber stamp
##       and a council it always loses is a scripted event.
##
## Not a test. tests/test_bloc.gd asserts the invariants; this prints the spread a
## human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd, trade_probe.gd, diplomacy_probe.gd and coercion_probe.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Elections = preload("res://src/sim/elections.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")

const PLAYABLE := ["FRA", "DEU", "GBR"]
const START_YEAR := 2026

## Sixty months: a full term plus a year, the same horizon
## tools/coercion_probe.gd and tools/trade_probe.gd use, so the three are
## readable against each other.
const HORIZON := 60

## Taken FROM src/ui/poll_noise.gd rather than restated, so the floor cannot
## drift away from the panel it is a floor for: an approval move smaller than the
## noise the panel already adds is one the player cannot distinguish from nothing.
const APPROVAL_LEGIBLE_PCT := PollNoise.NOISE_MAX_PCT

## The budget panel prints a line as a percent of GDP to one decimal, so a line
## under 0.05 rounds to "0.0%" and reads as no transfer at all.
const TRANSFER_LEGIBLE_PCT_GDP := 0.05

## A budget that defies the fiscal rules rather than merely missing them: the one
## spending line a single bloc weights, cut to nothing, and every rate dropped.
## Not RUINOUS -- that regime is off in guard-rail territory and would measure the
## clamp rather than the model.
const DEFIANT := {
	"spending_pct_gdp": {
		"health": 13.0, "education": 7.0, "defence": 0.5,
		"pensions": 16.5, "infrastructure": 5.0,
	},
	"tax_rates_pct": {"income": 17.0, "corporate": 15.0, "vat": 18.0},
}

## The candidate rows. Europe is ONE-SIGNED in this model -- opinion.gd scores
## every bloc against the same satisfaction, so a bloc cannot like what another
## dislikes through this channel, only care more or less about it. So these are
## "how much does being overruled from Brussels dominate this bloc's agenda", and
## the political SPLIT comes from membership's economic upside landing on `growth`
## and `public_finances`, which the existing table already weights very unevenly:
## pensioners and rural carry NO `growth` entry at all, so 37% of the electorate
## structurally receives the constraint and not the single market.
const EUROPE_CANDIDATE := {
	"workers": 0.10,
	"pensioners": 0.10,
	"urban": 0.06,
	"rural": 0.14,
	"business": 0.06,
	"students": 0.05,
}

## The five player-set spending lines, as one group. S10's finding was a ratio
## between this group and public_finances, not an absolute weight, which is the
## whole reason a uniform-ish dilution might be survivable.
const SPENDING_ISSUES := ["health", "education", "defence", "pensions", "infrastructure"]


func _init() -> void:
	_dilution_table()

	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_legibility_table(loader)
	_transfer_table(loader)
	_vote_table(loader)
	quit(0)


## Adopt a proposal straight into the register, bypassing the council. The same
## thing tools/coercion_probe.gd's _impose() does for a measure and
## tools/trade_probe.gd did for a weight -- it is what lets the measurement set
## the content's numbers instead of validating them afterwards.
func _adopt(state, proposal) -> void:
	var entry := {
		"name": proposal.proposal_name,
		"field": "", "op": "", "value": 0.0, "tolerance": 1.0, "severity": 0.0,
		"transfer_pct_gdp": proposal.transfer_pct_gdp,
		"since_year": state.year, "since_month": state.month,
	}
	if not proposal.constraint.is_empty():
		entry["field"] = String(proposal.constraint["field"])
		entry["op"] = String(proposal.constraint["op"])
		entry["value"] = float(proposal.constraint["value"])
		entry["tolerance"] = float(proposal.constraint["tolerance"])
		entry["severity"] = float(proposal.constraint["severity"])
	state.bloc["rules"][proposal.id] = entry


## Every loaded proposal that actually constrains policy, in agenda order.
func _constraining(loader) -> Array:
	var out: Array = []
	for p in loader.bloc_proposals:
		if not p.constraint.is_empty():
			out.append(p)
	return out


## Table (b). THE ESCALATION TRIGGER.
##
## A rule is in force and the player is outside it. Every quantity printed is one
## the player can read off a panel, because the question is not whether the state
## moved but whether the player can tell.
##
## Unlike V1.3b's and V1.3c's triggers this one is FRA/DEU-shaped: GBR is not a
## member, carries no burden by construction, and is measured in table (d)
## instead, where the bloc acts ON it.
func _legibility_table(loader) -> void:
	print("\n\n########## (b) can the player FEEL a bloc rule? ##########")
	print("ESCALATION TRIGGER, and the table that sets FINE_PCT_GDP_PER_BURDEN and")
	print("the six salience rows above. Rules are adopted at month 0 and held for %d" % HORIZON)
	print("months against a control with an empty register and the same budget.")
	print("")
	print("Poll noise is +/-%.1f, so an approval move under that is one the player" % APPROVAL_LEGIBLE_PCT)
	print("cannot distinguish from nothing. Two budgets: the nation's own starting")
	print("policy, which is what a player who never opens the budget screen runs, and")
	print("a DEFIANT one that breaches on purpose. The first is the floor the content")
	print("has to clear to be a mechanic at all; the second is the ceiling of what")
	print("this session can reach without V1.3e.")
	print("")
	print("%-6s %-9s %-7s %9s %10s %11s %11s   %s" % [
		"actor", "budget", "rules", "burden", "fine %GDP", "peak approv", "peak defic", "legible?",
	])
	print("-".repeat(88))

	var constraining := _constraining(loader)
	var worst_single := 0.0

	for budget_name in ["starting", "defiant"]:
		var pending: Dictionary = {} if budget_name == "starting" else DEFIANT
		for rule_count in [1, 2, constraining.size()]:
			for actor_id in ["FRA", "DEU"]:
				var control = GameState.new_game(loader, actor_id)
				var treated = GameState.new_game(loader, actor_id)
				for s in [control, treated]:
					s.year = START_YEAR
					s.month = 1
					if not pending.is_empty():
						Budget.commit(s, pending)
				for r in range(mini(rule_count, constraining.size())):
					_adopt(treated, constraining[r])

				var peak_approval := 0.0
				var peak_deficit := 0.0
				var peak_burden := 0.0
				for i in range(HORIZON):
					_tick(control, loader, i)
					_tick(treated, loader, i)
					var t = treated.player()
					var c = control.player()
					if absf(t.bloc_burden) > absf(peak_burden):
						peak_burden = t.bloc_burden
					if absf(t.overall_approval_pct - c.overall_approval_pct) > absf(peak_approval):
						peak_approval = t.overall_approval_pct - c.overall_approval_pct
					if absf(t.deficit_pct_gdp - c.deficit_pct_gdp) > absf(peak_deficit):
						peak_deficit = t.deficit_pct_gdp - c.deficit_pct_gdp

				var legible: bool = absf(peak_approval) >= APPROVAL_LEGIBLE_PCT
				if rule_count == 1 and budget_name == "defiant" and absf(peak_approval) > 0.0:
					var shortfall: float = APPROVAL_LEGIBLE_PCT / absf(peak_approval)
					if shortfall > worst_single:
						worst_single = shortfall

				print("%-6s %-9s %-7d %9.3f %10.3f %11.3f %11.3f   %s" % [
					actor_id, budget_name, rule_count, peak_burden,
					BK.FINE_PCT_GDP_PER_BURDEN * peak_burden,
					peak_approval, peak_deficit, "yes" if legible else "NO",
				])
			print("")

	print("-".repeat(88))
	print("The row that decides it is ONE rule, DEFIANT -- one bloc verb against one")
	print("player is what the content has to be legible at, read off the worse of the")
	print("two members, which is docs/amendment-model.md's discipline: open to one")
	print("nation in two is closed.")
	if worst_single > 1.0:
		print("")
		print("TRIGGER FIRED: that row needs %.2fx to clear +/-%.1f." % [worst_single, APPROVAL_LEGIBLE_PCT])
		print("The response the plan named is to raise THESE rows -- the europe salience")
		print("weights and FINE_PCT_GDP_PER_BURDEN -- and re-run table (a), NOT to touch")
		print("SALIENCE_GAIN or the public_finances row, which would undo S10 inside a")
		print("diplomacy session.")
	else:
		print("")
		print("TRIGGER DID NOT FIRE: one defied rule clears the noise floor with %.2fx" % (1.0 / maxf(worst_single, 0.0001)))
		print("to spare on the weaker of the two members.")


## Table (c). The transfer, which is the half of membership that is money rather
## than sovereignty.
func _transfer_table(loader) -> void:
	print("\n\n########## (c) what membership charges ##########")
	print("Derived from starting prosperity, not authored: base %.2f%% of GDP plus" % BK.CONTRIBUTION_BASE_PCT_GDP)
	print("%.2f per unit of GDP-per-capita above the bloc mean, clamped to" % BK.CONTRIBUTION_PROSPERITY_SPAN)
	print("[%.2f, %.2f]. One tax point is about 0.50%% of GDP" % [
		BK.CONTRIBUTION_MIN_PCT_GDP, BK.CONTRIBUTION_MAX_PCT_GDP,
	])
	print("(economy_constants.TAX_BASE_SHARE), and the budget panel prints a line to")
	print("one decimal, so under %.2f%% of GDP it reads as nothing at all." % TRANSFER_LEGIBLE_PCT_GDP)
	print("")
	print("%-6s %8s %10s %12s %12s %10s   %s" % [
		"nation", "member", "gdp/cap", "vs bloc mean", "net %GDP", "tax pts", "legible?",
	])
	print("-".repeat(70))

	var positions := Bloc.net_positions(loader)
	var total_gdp := 0.0
	var total_pop := 0.0
	for n in loader.nations.values():
		if n.eu_member:
			total_gdp += float(n.gdp_eur_bn)
			total_pop += float(n.population)
	var mean: float = total_gdp * 1.0e9 / total_pop / 1000.0

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var n = loader.nations[id]
		# EUR thousand per person: gdp is in billions and population is absolute, so
		# the raw ratio prints as 0.0000 and says nothing.
		var per_capita: float = float(n.gdp_eur_bn) * 1.0e9 / float(n.population) / 1000.0
		var net: float = float(positions.get(id, 0.0))
		print("%-6s %8s %10.1f %12.3f %12.3f %10.2f   %s" % [
			id, "yes" if n.eu_member else "no", per_capita, per_capita / mean, net,
			net / 0.50, "yes" if absf(net) >= TRANSFER_LEGIBLE_PCT_GDP else "NO",
		])
	print("-".repeat(70))
	print("A non-member must read EXACTLY 0.000, by construction rather than by")
	print("rounding -- it is half of what keeps the balance re-run's diff readable.")


## Table (d). The vote, and the two ways it can be decorative.
##
## A council the player always wins is a rubber stamp; one they always lose is a
## scripted event wearing a vote's clothes. What this looks for is proposals in
## between -- and, specifically, whether the player's own vote is ever PIVOTAL,
## because a vote that never changes the outcome is the decorative-axis failure
## docs/scenario-model.md records, with a ballot box drawn on it.
func _vote_table(loader) -> void:
	print("\n\n########## (d) is the council a real division? ##########")
	print("Members appraise a proposal against their own books since V1.3e -- this was")
	print("the DECLARED STOPGAP and it is discharged. Weighted by ep_seats, %.0f%% to carry." % (BK.PASS_SEAT_FRACTION * 100.0))
	print("Threshold %.2f. The sweep that set it is tools/foreign_policy_probe.gd (c)." % BK.SUPPORT_THRESHOLD)
	print("")
	print("Read from FRANCE's seat. `pivotal` is the one that matters: it is true when")
	print("the outcome differs between the player voting for and voting against, which")
	print("is the difference between a division and a cutscene.")
	print("")
	print("%-26s %7s %7s %7s %8s %9s   %s" % [
		"proposal", "for", "against", "abstain", "others", "support", "pivotal?",
	])
	print("-".repeat(80))

	var state = GameState.new_game(loader, "FRA")
	var members := Bloc.members(state, loader)
	var seats_total := 0
	for id in members:
		seats_total += loader.eu.ep_seats(id)
	var needed: int = int(ceil(BK.PASS_SEAT_FRACTION * float(seats_total)))

	# Where the eight other members actually sit, because the sweep below is
	# meaningless without it: if they are clustered, no sigma produces a spread and
	# the fix is the proposals' POSITIONS rather than the constant.
	print("Member governments, by seats:")
	for id in members:
		var pos: Dictionary = state.nations[id].coalition_position
		print("  %-4s %3d seats   econ %+.3f  social %+.3f" % [
			id, loader.eu.ep_seats(id), float(pos["economic"]), float(pos["social"]),
		])
	print("")

	var pivotal_count := 0
	var player_seats: int = loader.eu.ep_seats("FRA")
	var others_total: int = seats_total - player_seats
	for p in loader.bloc_proposals:
		var others_for := 0
		for id in members:
			if id == "FRA":
				continue
			if Bloc.support(state, state.nations[id], p) >= BK.SUPPORT_THRESHOLD:
				others_for += loader.eu.ep_seats(id)

		# Three outcomes, because the threshold is a share of the seats CAST. Voting
		# for adds to the numerator; voting against adds to the denominator and
		# blocks; abstaining removes the player from both and lets it through on a
		# smaller base.
		var with_for: bool = float(others_for + player_seats) >= BK.PASS_SEAT_FRACTION * float(seats_total)
		var with_against: bool = float(others_for) >= BK.PASS_SEAT_FRACTION * float(seats_total)
		var with_abstain: bool = float(others_for) >= BK.PASS_SEAT_FRACTION * float(others_total)
		if with_for != with_against:
			pivotal_count += 1
		print("%-26s %7s %7s %7s %8d %9s   %s" % [
			p.id,
			"pass" if with_for else "fail",
			"pass" if with_against else "fail",
			"pass" if with_abstain else "fail",
			others_for, "%.2f" % Bloc.support(state, state.player(), p),
			"YES" if with_for != with_against else "no",
		])
	print("-".repeat(80))
	print("Member seats %d, France holds %d, the other eight %d. %.0f%% of the seats" % [
		seats_total, player_seats, others_total, BK.PASS_SEAT_FRACTION * 100.0,
	])
	print("CAST carries it -- so %d of %d with France voting, %d of %d without." % [
		needed, seats_total,
		int(ceil(BK.PASS_SEAT_FRACTION * float(others_total))), others_total,
	])
	print("`abstain` differing from `against` is what makes abstention a third option")
	print("rather than a slower no. Against the whole council's strength instead of")
	print("the seats cast, those two columns would be identical for every row forever.")
	print("")
	print("%d of %d proposals are decided by France's own vote." % [pivotal_count, loader.bloc_proposals.size()])
	if pivotal_count == 0:
		print("NONE. The player's vote never changes an outcome, which makes the council a")
		print("cutscene. SUPPORT_THRESHOLD or PASS_SEAT_FRACTION has to move.")
	elif pivotal_count == loader.bloc_proposals.size():
		print("ALL of them, which is the other failure: if the player always decides, the")
		print("bloc is a second legislature they happen to control rather than one member")
		print("among many.")



## V1.3d's SIGMA SWEEP lived here and is DELETED at V1.3e.
##
## It swept bloc_constants.SUPPORT_SIGMA against the three-column test, and both
## the constant and the Gaussian it parameterised are gone -- members now appraise
## a proposal against their own books. The sweep carried its own inline copy of
## that Gaussian, which is precisely the dead-model-a-later-session-reasons-from
## hazard src/sim/diplomacy_constants.gd records for AGREEMENT_ACCEPT_MIN.
##
## Its successor is tools/foreign_policy_probe.gd table (c), which sweeps
## SUPPORT_THRESHOLD against FOUR columns rather than three -- V1.3d's own
## constructive-abstention property turned out to be unmeasured by the three.


## One month of the real game, the same chain main.gd runs. Copied from
## tools/coercion_probe.gd rather than shared, for the reason that file gives: a
## probe importing another probe's tick would break both when either changed its
## horizon.
func _tick(state, loader, i: int) -> void:
	state.month = (i + 1) % 12 + 1
	state.year = START_YEAR + (i + 1) / 12

	Economy.tick_month(state)
	Budget.tick_month(state)
	Bloc.tick_month(state, loader)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)


## Table (a). What a twelfth issue costs the eleven that are already measured.
func _dilution_table() -> void:
	print("\n########## (a) what `europe` costs the measured table ##########")
	print("ISSUE_KEYS is 11 and every row of BLOC_SALIENCE_BASE sums to 1.0, so today")
	print("the normalised weight IS the base weight at rest. Adding `europe` at w makes")
	print("the row sum 1+w, and opinion.gd's salience_weights() renormalises -- so every")
	print("existing weight in that row is scaled by 1/(1+w).")
	print("")
	print("S10's finding was a RATIO: public_finances carried ~0.10 of the national")
	print("agenda against ~0.50 for the five spending lines, which made fiscal discipline")
	print("strictly dominated. Roughly doubling that one row was the fix. What matters")
	print("here is therefore not that the weights shrink -- they must -- but whether the")
	print("ratio between them moves. Per-bloc dilution differs (the candidate rows are")
	print("not uniform), so the national roll-up is NOT preserved exactly and this table")
	print("is measuring how far off exact it lands.")
	print("")

	var zero_sat := {}
	for issue in OK.ISSUE_KEYS:
		zero_sat[issue] = 0.0
	zero_sat["europe"] = 0.0

	print("%-12s %8s %10s %14s %14s" % ["bloc", "size", "europe w", "scale on rest", "row sum before"])
	print("-".repeat(62))
	for bloc in OK.BLOC_KEYS:
		var base: Dictionary = OK.BLOC_SALIENCE_BASE[bloc]
		var before_sum := 0.0
		for issue in base:
			before_sum += float(base[issue])
		var w: float = float(EUROPE_CANDIDATE[bloc])
		print("%-12s %8.2f %10.3f %14.4f %14.4f" % [
			bloc, float(OK.BLOC_SIZE[bloc]), w, before_sum / (before_sum + w), before_sum,
		])
	print("-".repeat(62))

	var before := _national_agenda(false, zero_sat)
	var after := _national_agenda(true, zero_sat)

	print("")
	print("National agenda share -- size-weighted, which is what the polling panel's")
	print("\"what the country is thinking about\" list reads and what elections.gd's")
	print("attribution() ranks. Summed over the six blocs at rest.")
	print("")
	print("%-18s %12s %12s %12s" % ["issue", "before", "after", "change"])
	print("-".repeat(56))
	var keys: Array = OK.ISSUE_KEYS.duplicate()
	keys.append("europe")
	for issue in keys:
		var b: float = float(before.get(issue, 0.0))
		var a: float = float(after.get(issue, 0.0))
		print("%-18s %12.4f %12.4f %+12.4f" % [issue, b, a, a - b])
	print("-".repeat(56))

	var pf_before: float = float(before["public_finances"])
	var pf_after: float = float(after["public_finances"])
	var sp_before := 0.0
	var sp_after := 0.0
	for issue in SPENDING_ISSUES:
		sp_before += float(before[issue])
		sp_after += float(after[issue])

	print("")
	print("THE S10 RATIO -- public_finances : the five spending lines")
	print("  before  %.4f : %.4f  =  %.4f" % [pf_before, sp_before, pf_before / sp_before])
	print("  after   %.4f : %.4f  =  %.4f" % [pf_after, sp_after, pf_after / sp_after])
	print("  drift   %+.4f%% of the ratio" % (
		100.0 * ((pf_after / sp_after) / (pf_before / sp_before) - 1.0)
	))
	print("")

	var total_after := 0.0
	for issue in after:
		total_after += float(after[issue])
	print("Agenda still sums to %.6f (opinion.gd renormalises per bloc; the roll-up is" % total_after)
	print("a convex combination, so this must stay 1.0 or the model is broken).")
	print("")
	print("`europe` takes %.4f of the national agenda -- against public_finances at" % float(after["europe"]))
	print("%.4f, defence at %.4f and education at %.4f. For an issue that is the" % [
		pf_after, float(after["defence"]), float(after["education"]),
	])
	print("headline of a whole session, being above defence is the floor to clear.")
	print("")
	print("The absolute cost, stated plainly: every existing issue's pull on approval")
	print("shrinks by the scale column above -- arithmetically identical to a smaller")
	print("APPROVAL_SPAN. It is one scalar, not a re-tune, and tests/test_balance.gd's")
	print("three S10 assertions are what decide whether it is survivable. If they fail,")
	print("the response named in the plan is to lower THESE rows, not to touch")
	print("SALIENCE_GAIN or the public_finances row -- that would undo S10 inside a")
	print("diplomacy session.")


## The size-weighted national agenda at a given satisfaction vector, with or
## without the candidate europe row merged in. Mirrors opinion.gd's own roll-up
## (`national[issue] += size * weights[issue]`) rather than calling it, because
## _tick_nation() needs a NationState and this table needs neither a game nor a
## nation -- the same reason tools/cabinet_probe.gd rebuilds the roll-up locally.
func _national_agenda(with_europe: bool, sat: Dictionary) -> Dictionary:
	var national := {}
	for bloc in OK.BLOC_KEYS:
		var base: Dictionary = (OK.BLOC_SALIENCE_BASE[bloc] as Dictionary).duplicate()
		if with_europe:
			base["europe"] = float(EUROPE_CANDIDATE[bloc])
		var weights := Opinion.salience_weights(base, sat, OK.SALIENCE_GAIN)
		var size: float = float(OK.BLOC_SIZE[bloc])
		for issue in weights:
			national[issue] = float(national.get(issue, 0.0)) + size * float(weights[issue])
	return national
