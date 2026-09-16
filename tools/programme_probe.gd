extends SceneTree

## Headless probe: godot --path "<repo>" --headless --script res://tools/programme_probe.gd
## (add `-- --json` for the stable-key summary). Dev-only, never ships.
##
## V4.1 Task 4, the sweep harness for the programme credit channel. The bands
## P1-P5 and the grid were declared in docs/programme-model.md §6 before this
## file existed; this header declares the HARNESS half of the measurement, also
## before the sweep ran (V1.7c's discipline, the same split V4.0 made):
##
##   TIMELINE. The state is a fresh FRA game ticked through the term's own
##   months 1..16 (agency_probe starts at month 2; this one starts at 1 because
##   the register's clock must run from term start -- the authored Maastricht
##   timeout of 6 then concludes in month 6, the read month). The programme is
##   chosen at new game, when months_in_term is 0 and Programme.is_term_start()
##   is true. The tick order is main.gd's with Programme.tick_month immediately
##   before Opinion.tick_month -- the wiring under test.
##
##   THE ONE SCRIPTED INPUT. No authored entry completes naturally on the
##   fresh-game cycle inside the window (unemployment starts 7.4 against a 7.0
##   goal; growth 0.08 against a 2.0 goal), so the `complete` and `chosen`
##   arms share ONE write -- growth_annual_pct := 2.5 at month 6, in the slot
##   between Media and Programme, where the economy has already ticked and the
##   register is about to be judged. The conclusion path the write buys --
##   trigger judged on the live field, status stamped, concluded_this_month,
##   pulse read by Opinion -- is entirely the sim's; tests/test_programme.gd
##   drives the same trigger the same way at unit scale. The write's own
##   approval effect rides BOTH write arms and cancels in the difference;
##   the probes that read bands read arm-vs-arm, never arm-vs-idle across
##   the write.
##
##   ARMS. Five, and the pairing is the measurement: idle: nothing (P3's
##   clause, and `fail`'s control). chosen: prog_industrial_renewal, NO write
##   -- its goal is never met, so it isolates register PRESENCE and must read
##   exactly 0.0 against idle (P3). write-only: the shared write with NO
##   programme -- the write's own approval path, which P1 subtracts. complete:
##   prog_industrial_renewal + the shared write -- completes in month 6.
##   fail: prog_maastricht_letter, no write -- the idle deficit stays over 3.0
##   and the clock concludes it in month 6. P1 reads complete - write-only
##   (both arms carry the write; the register itself prices nothing, which P3
##   asserts), P2 reads fail - idle, P3 reads chosen - idle. NO arm carries an
##   authored `immediate`: prog_jobs_first's +0.05 workers bloc_offset rides
##   the x40 APPROVAL_SPAN and is worth ~+0.15 headline points compounding to
##   ~+0.49 by month 6 -- measured here first as a confound and then designed
##   out; an immediate in either P1 arm would be half the band. Each style
##   names its one entry in its own literal: the loader knows the ids, and
##   tests/test_programme.gd's scanner fails any tools/ file that hand-writes
##   three of them in one bracket chunk.
##
##   PREDICTED SHAPE, written before the run: a conclusion landing in month 6
##   has exactly one month of inertia behind it at the read, so the channel
##   delta at month 6 is 0.25 x PROGRAMME_SPAN (single-term float-exact: the
##   S-term enters one multiplication deep), both bands cross at span 4.0, and
##   the band is one-sided-up -- no upper clause is declared. The span-0 row
##   anchors the slope, the way V4.0's did.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Programme = preload("res://src/sim/programme.gd")
const PK = preload("res://src/sim/programme_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const Media = preload("res://src/sim/media.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Energy = preload("res://src/sim/energy.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")

const START_YEAR := 2026
const MONTHS := 16           # The term: Jan 2026 -> the May 2027 election.
const DECAY_MONTHS := 24     # P5's run: the half-life must land inside this.
const BAND_POINTS_M6 := 1.0  # P1/P2's pre-declared bar, programme-model §6.
const WRITE_MONTH := 6       # The shared write, and the conclusion month.
const WRITE_GROWTH := 2.5    # Fires prog_industrial_renewal's >= 2.0 goal.
const STOCK_BOUND := 1.0     # programme_constants.STOCK_MIN/MAX, as a check.

const STYLES := {
	"idle": {"entry": "", "write": false},
	"chosen": {"entry": "prog_industrial_renewal", "write": false},
	"write-only": {"entry": "", "write": true},
	"complete": {"entry": "prog_industrial_renewal", "write": true},
	"fail": {"entry": "prog_maastricht_letter", "write": false},
}


func _init() -> void:
	var as_json := "--json" in OS.get_cmdline_user_args()
	var summaries := {}
	for id in STYLES:
		summaries[String(id)] = _run_style(STYLES[id], MONTHS)
	# P5's run: the completed arm again, held 8 months past the vote so the
	# stock's decay crosses its half with no second conclusion anywhere near.
	var decay_trace: Array = _run_style(STYLES["complete"], DECAY_MONTHS)["stock_trace"]

	var idle: Dictionary = summaries["idle"]
	for id in summaries:
		var s: Dictionary = summaries[id]
		s["delta_m6_vs_idle"] = float(s["approval_m6"]) - float(idle["approval_m6"])

	var p1: float = float(summaries["complete"]["delta_m6_vs_idle"]) \
		- float(summaries["write-only"]["delta_m6_vs_idle"])
	var p2: float = float(summaries["fail"]["delta_m6_vs_idle"])
	var p3: float = float(summaries["chosen"]["delta_m6_vs_idle"])
	var stock_abs_max := 0.0
	var idle_stock_zero := true
	for id in summaries:
		for v in summaries[id]["stock_trace"]:
			stock_abs_max = maxf(stock_abs_max, absf(float(v)))
		for v in summaries[id]["pulse_trace"]:
			stock_abs_max = maxf(stock_abs_max, absf(float(v)))
		if id == "idle":
			for v in summaries[id]["stock_trace"]:
				if float(v) != 0.0:
					idle_stock_zero = false

	var half_life := _half_life_months(decay_trace)
	var nominal := log(2.0) / PK.PROGRAMME_DECAY_RATE

	# The input assertions: a measurement whose input did not happen is void
	# (V1.3f's measuring-the-wrong-state, in the harness's own dress).
	var input_ok := true
	input_ok = input_ok and String(summaries["complete"]["register_status_m16"]) == PK.STATUS_COMPLETE \
		and int(summaries["complete"]["concluded_month"]) == WRITE_MONTH
	input_ok = input_ok and String(summaries["chosen"]["register_status_m16"]) == PK.STATUS_ACTIVE
	input_ok = input_ok and String(summaries["fail"]["register_status_m16"]) == PK.STATUS_FAIL \
		and int(summaries["fail"]["concluded_month"]) == WRITE_MONTH
	input_ok = input_ok and String(summaries["write-only"]["register_status_m16"]) == "none"
	if not input_ok:
		printerr("probe input did not land: conclusions must fall in month %d and the chosen arm must never conclude" % WRITE_MONTH)
		quit(1)
		return

	var chosen_stock_zero := true
	for v in summaries["chosen"]["stock_trace"]:
		if float(v) != 0.0:
			chosen_stock_zero = false
	var p1_pass := p1 >= BAND_POINTS_M6
	var p2_pass := p2 <= -BAND_POINTS_M6
	var p3_pass := absf(p3) <= 0.3 and idle_stock_zero and chosen_stock_zero
	var p4_pass := stock_abs_max <= STOCK_BOUND + 1e-9
	var p5_pass := half_life > 0 and absf(float(half_life) - nominal) <= 1.0
	var verdict := "PASS" if (p1_pass and p2_pass and p3_pass and p4_pass and p5_pass) else "FAIL"

	var span_note := ""
	if PK.PROGRAMME_SPAN <= 0.0:
		span_note = " (PROGRAMME_SPAN is 0.0: the channel is INERT, all deltas collapse, FAIL is the correct reading)"

	if as_json:
		print(JSON.stringify({
			"schema": "programme-probe/v1",
			"programme_span": PK.PROGRAMME_SPAN,
			"decay_rate": PK.PROGRAMME_DECAY_RATE,
			"band_points_m6": BAND_POINTS_M6,
			"styles": summaries,
			"channel_p1_delta_m6": p1,
			"channel_p2_delta_m6": p2,
			"p3_chosen_delta_m6": p3,
		"chosen_stock_exactly_zero": chosen_stock_zero,
			"stock_abs_max": stock_abs_max,
			"idle_stock_exactly_zero": idle_stock_zero,
			"decay_half_life_months": half_life,
			"decay_nominal_months": nominal,
			"p1_pass": p1_pass,
			"p2_pass": p2_pass,
			"p3_pass": p3_pass,
			"p4_pass": p4_pass,
			"p5_pass": p5_pass,
			"verdict": verdict,
		}))
	else:
		_print_table(summaries, p1, p2, p3, stock_abs_max, half_life, nominal, verdict)
		print(span_note)
	quit(0)


func _print_table(summaries: Dictionary, p1: float, p2: float, p3: float,
		stock_abs_max: float, half_life: int, nominal: float, verdict: String) -> void:
	print("")
	print("=== PROGRAMME PROBE — one term (FRA Standard, %d months, span %.2f) ===" % [MONTHS, PK.PROGRAMME_SPAN])
	print("%-10s %8s %8s %9s %9s  %-14s %s" % [
		"style", "appr m6", "appr m16", "d_m6", "d_m16", "register m16", "stock trace m1..m16"])
	for id in summaries:
		var s: Dictionary = summaries[id]
		var bits: Array = []
		for v in s["stock_trace"]:
			bits.append("%.3f" % float(v))
		print("%-10s %8.2f %8.2f %+9.3f %+9.3f  %-14s %s" % [
			id, float(s["approval_m6"]), float(s["approval_m16"]),
			float(s["delta_m6_vs_idle"]),
			float(s["approval_m16"]) - float(summaries["idle"]["approval_m16"]),
			String(s["register_status_m16"]), " ".join(bits),
		])
	print("")
	print("channel P1 (complete - write-only, write isolated) at m6: %+.3f  (band >= +%.1f)" % [p1, BAND_POINTS_M6])
	print("channel P2 (fail - idle, no write)              at m6: %+.3f  (band <= -%.1f)" % [p2, BAND_POINTS_M6])
	print("P3 chosen-but-unconcluded vs idle at m6:              %+.3f  (band <= +-0.3)" % p3)
	print("P4 max |stock| over every trace:                      %.6f  (bound 1.0)" % stock_abs_max)
	print("P5 decay half-life: %d months, nominal ln(2)/%.2f = %.2f (tolerance +-1)" % [
		half_life, PK.PROGRAMME_DECAY_RATE, nominal])
	print("VERDICT: programme channel %s" % verdict)


## One scripted run of the term. `months` sizes the window (16 for the sweep,
## 24 for the decay read); everything else is the harness's declared shape.
func _run_style(style: Dictionary, months: int) -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return {}

	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1

	var ns = state.player()

	# The choice at new game: months_in_term is 0, is_term_start() is true, and
	# choose() is the same verb the agenda panel issues. An empty entry id is
	# the idle arm's "nothing chosen".
	var entry_id := String(style["entry"])
	if entry_id != "":
		var result := Programme.choose(state, ns, entry_id, loader)
		if not bool(result.get("applied", false)):
			printerr("programme choose refused for '%s': %s" % [entry_id, str(result.get("reason", ""))])
			quit(1)
			return {}

	var stock_trace: Array = []
	var pulse_trace: Array = []
	var year := START_YEAR
	var month := 0
	var result_record := {}
	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		# main.gd's order, with Programme immediately before Opinion -- the
		# wiring under test. Elections runs last, which is the term-boundary
		# guarantee the wiring comment in main.gd states.
		var access_by_nation: Dictionary = {}
		for member_id in state.nations.keys():
			access_by_nation[member_id] = Regions.accessibility_for(
				state.nations[member_id], state.regions.get(member_id, []), state.region_graph)
		Energy.tick_month(state, loader, access_by_nation)
		Economy.tick_month(state)
		Budget.tick_month(state)
		Orgs.tick_month(state, loader)
		Inflation.tick_month(state)
		Media.tick_month(state, loader)
		# The harness's one scripted input, in the slot between the economy
		# having settled and the register being judged. Both write arms carry
		# it; every band read is arm-vs-arm across it.
		if bool(style["write"]) and month == WRITE_MONTH:
			ns.growth_annual_pct = WRITE_GROWTH
		Programme.tick_month(state, loader)
		pulse_trace.append(Programme.programme_pulse(ns))
		Opinion.tick_month(state)
		stock_trace.append(float(ns.programme_stock))
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)

		Discipline.tick_month(state, loader)
		Legislature.tick_month(state, loader)
		Dissolution.tick_month(state)
		Diplomacy.tick_month(state, loader)
		Defence.tick_month(state)
		Companies.tick_month(state, loader)
		Migration.tick_month(state, loader)
		Investment.tick_month(state)
		Projects.tick_month(state, loader)
		Campaign.tick_month(state, loader)
		Pledges.tick_month(state, loader)
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		Events.tick_month(state, loader)
		_answer_event(state, loader, ns, year, month)
		Cabinet.tick_month(state, loader)

		# The day loop for calendar parity; nothing is booked, so due() is the
		# one is_empty() check the harness's U6a note describes.
		state.day = 0
		for d in range(_days_in_month(month, year)):
			state.day = d + 1
			Calendar.due(state, year, month, state.day)
		Calendar.tick_month(state)

		for r in Elections.tick_month(state, loader):
			if r["kind"] == "executive":
				result_record = r

	var register: Dictionary = {}
	if not ns.programme.is_empty():
		register = ns.programme[0]
	var concluded_month := -1
	if not register.is_empty() and int(register.get("concluded_term_month", -1)) >= 0 \
			and String(register.get("status", "")) != PK.STATUS_ACTIVE:
		concluded_month = _month_of_conclusion(state, register)

	var vote_share: float = -1.0
	if not result_record.is_empty():
		vote_share = float(result_record.get("incumbent_vote_share", -1.0))

	return {
		"approval_m6": _approval_at(state, 6),
		"approval_m16": _approval_at(state, mini(months, 16)),
		"stock_trace": stock_trace,
		"pulse_trace": pulse_trace,
		"register_status_m16": String(register.get("status", "")) if not register.is_empty() else "none",
		"concluded_month": concluded_month,
		"vote_share": vote_share,
	}


## The register stamps the conclusion as (terms_served, months_in_term); this
## reverses the stamp to a probe month for the input assertions. Months 1..N
## tick before Elections increments the counter, so months_in_term m during a
## tick is probe month m + 1 -- except month 1 itself, where the counter has
## not moved yet. A conclusion in this harness can only be stamped at month 1's
## value 0 (probe month 1) or later values m (probe month m + 1).
func _month_of_conclusion(state, register: Dictionary) -> int:
	var m := int(register["concluded_term_month"])
	return 1 if m == 0 else m + 1


## First month, after the pulse, where the stock is at or under half its peak.
## Returns -1 if the window ends first.
func _half_life_months(trace: Array) -> int:
	if trace.size() <= WRITE_MONTH:
		return -1
	var peak := float(trace[WRITE_MONTH - 1])
	if peak == 0.0:
		return -1
	for j in range(WRITE_MONTH, trace.size()):
		if absf(float(trace[j])) <= 0.5 * absf(peak):
			return (j + 1) - WRITE_MONTH
	return -1


## History holds one snapshot per simulated month in order; month 6 is index 5.
func _approval_at(state, month_index: int) -> float:
	var history: Array = state.history
	if history.size() >= month_index:
		return float(history[month_index - 1].get("overall_approval_pct", 0.0))
	return 0.0


## Events answered on arrival, every arm, the harness's "soft" rule (V2.9b's):
## the non-default choice best for bloc-weighted approval. A fault the player
## always clears, so the arm comparison never rides an expired card.
func _answer_event(state, loader, ns, year: int, month: int) -> void:
	if not Events.is_pending(ns):
		return
	var ev = Events.pending_event(ns, loader)
	if ev == null:
		return
	var pick: Dictionary = {}
	var pick_score := 0.0
	for c in ev.choices:
		if bool(c["is_default"]):
			continue
		var score := 0.0
		var terms: Dictionary = (c["effects"] as Dictionary).get("bloc_offset", {})
		for bloc in terms:
			score += float(K.BLOC_SIZE.get(bloc, 0.0)) * float(terms[bloc])
		if pick.is_empty() or score > pick_score:
			pick = c
			pick_score = score
	if pick.is_empty():
		return
	Events.choose(state, loader, String(pick["id"]))


func _days_in_month(m: int, y: int) -> int:
	if m == 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
		return 29
	return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
