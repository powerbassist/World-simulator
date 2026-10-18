extends SceneTree

## The V4.5b instrument: the contested council, measured.
## godot --headless --script res://tools/council_probe.gd
## godot --headless --script res://tools/council_probe.gd -- --sweep <proposal_id>
## godot --headless --script res://tools/council_probe.gd -- --t      (table T only)
## godot --headless --script res://tools/council_probe.gd -- --only c12|c36  (sweep fast paths)
##
## Model: docs/orgs-model.md, "V4.5 -- the council, contested", which declared
## the bands BEFORE this file ran. Content is read, never named: every table
## walks the loaded register, so the probe that measured the nine shipped
## proposals measures V4.5b's full book with no code change -- and the sweep
## (table S) is how that book is PLACED, by measurement rather than by feel.
##
##   T   PER-PROPOSAL TALLIES. Every council org, every proposal in authored
##       order, at a FRA new-game: decision class, sponsor (+ drive), and three
##       divisions on fresh states -- FRA for / abstaining / against -- each
##       opened as the machine opens one (the live sponsor lobbies), then
##       divided at once. Verdict: carries-alone (carries with FRA against),
##       player-decides (for and against differ), lost-anyway (fails with FRA
##       for), inverted (fails with FRA for, carries against -- should be
##       impossible); `+abst` flags an abstention-window (abstain and against differ).
##       Unanimity rows list the vetoing ids when FRA votes for. Footer per org.
##   C1  THE PLAYER DECIDES. The idle FRA run on the real month, no player
##       council command, read over the FIRST TERM (months 1-60). At each opening
##       in that window, on duplicate_state() copies resolved at once, does ANY
##       single bargain (currency x member, asking FRA's preferred outcome) flip
##       the outcome to it? Band 0.20-0.50 on the
##       DISTINCT-proposal share (proposals ever decidable / proposals ever
##       opened) -- one proposal re-opening every few openings must not set the
##       band by repetition. The per-opening share is printed as context.
##   C2  SPENDING IS NOT FREE. The idle run (`never`) beside an `always` run of
##       the first term (60 months) that strikes a bargain only when a
##       counterfactual shows it flips the division to FRA's preference (favours
##       across all members first, then aid; members in id order). Bargains
##       struck, currency mix, mean cost, and mean FRA relations with the
##       bargained members AT MONTH 60 (per member and the gap). Band gap >= 5.0.
##   THE WINDOWS, from the band wording docs/orgs-model.md declared. C1 is "over
##   a term" and C2 "ends a term": both read months 1-60, the term a player
##   plays, under balance_probe.gd's in_government guard -- a president out of
##   office is not the player those bands are about, so FRA leaving office
##   inside months 1-60 marks C1/C2 MISS-INVALID. C3 and C6 are "in a 168-month
##   idle run": the council divides whoever governs France, so that run never
##   stops on the election; the month FRA left office is printed as context and
##   marks nothing invalid.
##   C3  UNANIMITY IS REACHABLE. The full 168-month idle run's unanimity
##       divisions: carried vs vetoed. Band >= 1 carried and >= 1 vetoed.
##   C4  RATIFICATION IS A FIGHT. Every unanimity proposal as a treaty bill in
##       FRA's new-game assembly: yes / (yes + no). Band >= 2 inside [0.40, 0.60].
##   C5  THE BURDEN_MAX RE-MEASURE. Every org's heaviest constraint proposals in
##       force (<= MAX_RULES_IN_FORCE each), FRA's books past every tolerance:
##       per-org burden, the RAW cross-org total, BURDEN_MAX, the clamped burden.
##       Recorded against V3.5's 1.33; no band.
##   C6  AGENDA REACH. The full 168-month idle run: per org, proposals never
##       opened. Band: none never opened.
##   DIAGNOSES (V4.5b1 T5; context lines, never bands): C1 splits the openings
##   (forecast already the preference / differs / one bargain flips it / no
##   single bargain can) and prints the ceiling a swing sweep could reach; C2
##   traces each strike's price against what DRIFT_RATE alone leaves by month
##   60; C6 says, per never-opened proposal, whether it sat in an AI chair's
##   window (and what beat it) or was out of reach (in force, ratifying,
##   capped by MAX_RULES_IN_FORCE, past the window).
##   S   THE SWEEP (`--sweep <id>` runs only this): table T's verdict for one
##       proposal over a 5x5 (economic, social) grid.
##
## Today's content misses several bands; a MISS here is the baseline, recorded,
## not a defect. The bands are what V4.5b's content is placed to reach.

const DataLoader = preload("res://src/core/data_loader.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const GameState = preload("res://src/core/game_state.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Council = preload("res://src/sim/council.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const Ratification = preload("res://src/sim/ratification.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const RK = preload("res://src/core/relations.gd")
const DiplomacyK = preload("res://src/sim/diplomacy_constants.gd")

# The systems this probe reads outside the month (the month is WorldMonth's).
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Calendar = preload("res://src/sim/calendar.gd")

const PLAYER := "FRA"
## balance_probe.gd's term: fourteen years from January 2026.
const MONTHS := 168
## The first term: the window C1 and C2 read ("over a term", "ends a term").
const TERM_MONTHS := 60
const START_YEAR := 2026

## The bands, as docs/orgs-model.md declared them.
const C1_MIN := 0.20
const C1_MAX := 0.50
const C2_MIN_GAP := 5.0
const C4_YES_MIN := 0.40
const C4_YES_MAX := 0.60
const C4_MIN_TREATIES := 2
## V3.5's measured raw cross-org burden at total defiance (tools/climate_probe.gd (d2)).
const C5_V35_RAW := 1.33

const SWEEP_AXIS := [-0.8, -0.4, 0.0, 0.4, 0.8]
## How far past a rule's value C5 drives a field, in tolerances: past 1.0 every
## rule contributes its whole severity; 2.0 so float noise cannot leave one short.
const C5_PUSH_TOLERANCES := 2.0

const V_CARRIES := "carries-alone"
const V_DECIDES := "player-decides"
const V_LOST := "lost-anyway"
## Fails with FRA for yet carries with FRA against -- should be impossible (the
## tally is monotone in FRA's vote); a row that reads it is a machine finding.
const V_INVERTED := "inverted"
const VERDICT_CODE := {V_CARRIES: "CA", V_DECIDES: "PD", V_LOST: "LA", V_INVERTED: "IN"}

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("loader errors: %s" % [_loader.errors])
		quit(1)
		return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--sweep")
	if at >= 0:
		if at + 1 >= args.size():
			printerr("--sweep needs a proposal id")
			quit(1)
			return
		quit(0 if _table_s(String(args[at + 1])) else 1)
		return

	var t0: int = Time.get_ticks_msec()
	# `--only c12` / `--only c36`: the constant sweeps' fast paths. C1/C2 read
	# only the first term, so their idle run stops at TERM_MONTHS (C1 is the
	# same: it reads months 1-60 of the 168); C3/C6 need the full idle run and
	# nothing else. Same tables, same bands, fewer of them.
	var only_at: int = args.find("--only")
	if only_at >= 0 and only_at + 1 < args.size():
		var which := String(args[only_at + 1])
		if which == "c12":
			var idle12: Dictionary = _run_term(false, true, TERM_MONTHS, false)
			var always12: Dictionary = _run_term(true, false, TERM_MONTHS, true)
			_table_c1(idle12)
			_table_c2(idle12, always12)
		elif which == "c36":
			var idle36: Dictionary = _run_term(false, true, MONTHS, false)
			_table_c3(idle36)
			_table_c6(idle36)
		else:
			printerr("--only takes c12 or c36")
			quit(1)
			return
		print("\n## runtime %.1f s" % [float(Time.get_ticks_msec() - t0) / 1000.0])
		quit(0)
		return
	_table_t()
	# `--t`: table T alone -- the placement loop re-reads it after every edit,
	# and the 168-month runs behind C1-C6 are what make a full pass take a minute.
	if args.has("--t"):
		quit(0)
		return
	# The idle run serves both windows: C1 reads its first term, C3/C6 all of it.
	# The always run only has a term to measure, so it ends there.
	var idle: Dictionary = _run_term(false, true, MONTHS, false)
	var always: Dictionary = _run_term(true, false, TERM_MONTHS, true)
	_table_c1(idle)
	_table_c2(idle, always)
	_table_c3(idle)
	_table_c4()
	_table_c5()
	_table_c6(idle)
	print("\n## runtime %.1f s" % [float(Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


# --- shared helpers ------------------------------------------------------------------

func _fresh():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


## `valid` false: the run the band reads stopped early (FRA left government),
## so the number measures a shorter term than the band was declared over.
func _band(id: String, ok: bool, number: String, valid := true) -> void:
	var verdict: String = "PASS" if ok else "MISS"
	if not valid:
		verdict = "MISS-INVALID"
	print("BAND %s: %s (%s)" % [id, verdict, number])


## Whether FRA wants this proposal adopted: its own government's appraisal
## against the threshold every AI member votes by -- the same sign a member's
## vote reads, so "preferred" means what FRA would vote if it voted honestly.
func _prefers_pass(state, p) -> bool:
	return Orgs.support(state, state.nations[PLAYER], p) >= BK.SUPPORT_THRESHOLD


## Open `p` on `state` the way orgs.gd's _tick_council() opens one (pending
## entry, then the live AI sponsor's lobbying), due to divide on the next tick.
## The opening stamp is the state's month; a forced division has no setup
## bargain whose stamp it could collide with.
##
## HAND-COPIED. src/sim/orgs.gd `_tick_council()` is the source of truth for
## the pending entry's shape and for the lobbying step. A field added to the
## pending entry there MUST be mirrored here, or table T and the sweep divide
## a pending the game never builds -- and nothing fails to say so.
func _open_as_the_machine_does(state, p) -> void:
	var org_id: String = p.org_id
	var sponsor: String = Council.live_sponsor(state, p)
	state.orgs[org_id]["pending"] = {
		"proposal_id": p.id, "name": p.proposal_name, "summary": p.summary,
		"org_id": org_id, "org_name": _loader.orgs_by_id[org_id].name,
		"months_left": 1, "player_vote": Orgs.VOTE_ABSTAIN,
		"opened_year": state.year, "opened_month": state.month,
		"sponsor": sponsor,
	}
	if sponsor != "" and not state.nations[sponsor].has_budget:
		var supports := {}
		for id in Orgs.members(state, org_id):
			if not state.nations[id].has_budget:
				supports[id] = Orgs.support(state, state.nations[id], p)
		state.orgs[org_id]["pending"]["lobbied"] = Council.lobby(state, _loader, sponsor, supports)


## One division of `p` on a fresh new-game with FRA casting `choice`.
func _divide_fresh(p, choice: String) -> Dictionary:
	var state = _fresh()
	_open_as_the_machine_does(state, p)
	Orgs.cast_vote(state, p.org_id, choice)
	Orgs.tick_month(state, _loader)
	var last: Dictionary = Orgs.last_vote(state, p.org_id)
	if String(last.get("proposal_id", "")) != p.id:
		push_error("council_probe: %s did not divide" % p.id)
	return last


## T's three divisions and the verdict they make.
func _tally(p) -> Dictionary:
	var f: Dictionary = _divide_fresh(p, Orgs.VOTE_FOR)
	var a: Dictionary = _divide_fresh(p, Orgs.VOTE_ABSTAIN)
	var x: Dictionary = _divide_fresh(p, Orgs.VOTE_AGAINST)
	var pf: bool = bool(f.get("passed", false))
	var pa: bool = bool(a.get("passed", false))
	var px: bool = bool(x.get("passed", false))
	var verdict: String = V_LOST
	if pf and px:
		verdict = V_CARRIES
	elif pf:
		verdict = V_DECIDES
	elif px:
		verdict = V_INVERTED
	return {"for": f, "abstain": a, "against": x, "verdict": verdict, "abst_window": pa != px}


func _seats(d: Dictionary) -> String:
	return "%s %3d/%3d/%3d" % ["P" if bool(d.get("passed", false)) else "-",
		int(d.get("seats_for", 0)), int(d.get("seats_against", 0)), int(d.get("seats_total", 0))]


# --- T: per-proposal tallies -----------------------------------------------------------

func _table_t() -> void:
	print("\n########## T per-proposal tallies (FRA new-game; for / abstain / against) ##########")
	print("cells: passed? seats_for/against/total.  +abst = abstain and against differ")
	var probe_state = _fresh()
	for org_id in Orgs.council_ids(probe_state):
		var proposals: Array = _loader.org_proposals.get(org_id, [])
		print("\n-- %s (%d proposals; FRA member: %s) --" % [org_id, proposals.size(),
			"yes" if probe_state.nations[PLAYER].orgs.has(org_id) else "NO"])
		print("%-28s %-9s %-11s %-16s %-16s %-16s %-21s %s" % [
			"proposal", "class", "sponsor", "FRA for", "FRA abstain", "FRA against", "verdict", "vetoes(FRA for)"])
		var counts := {V_CARRIES: 0, V_DECIDES: 0, V_LOST: 0, V_INVERTED: 0, "abstention-window": 0}
		for p in proposals:
			var decision: String = Council.decision_of(_loader, p)
			var sponsor: String = Council.live_sponsor(probe_state, p)
			var sp: String = "-"
			if sponsor != "":
				sp = "%s(%.2f)" % [sponsor, Council.drive(probe_state, _loader, sponsor)]
			var t: Dictionary = _tally(p)
			counts[t["verdict"]] += 1
			if bool(t["abst_window"]):
				counts["abstention-window"] += 1
			var vetoes: String = ""
			if decision == CouncilK.DECISION_UNANIMITY:
				vetoes = ",".join(PackedStringArray((t["for"] as Dictionary).get("vetoed_by", [])))
				if vetoes == "":
					vetoes = "none"
			print("%-28s %-9s %-11s %-16s %-16s %-16s %-21s %s" % [
				p.id, decision, sp, _seats(t["for"]), _seats(t["abstain"]), _seats(t["against"]),
				String(t["verdict"]) + ("+abst" if bool(t["abst_window"]) else ""), vetoes])
		print("footer %s: carries-alone %d, player-decides %d, lost-anyway %d, inverted %d, abstention-window %d" % [
			org_id, counts[V_CARRIES], counts[V_DECIDES], counts[V_LOST], counts[V_INVERTED], counts["abstention-window"]])


# --- the 168-month run -------------------------------------------------------------------

## `months` on the real month. `bargain_always`: C2's `always` player. `measure_c1`:
## test every opening for a deciding bargain on copies. Both act only inside the
## first term and only while FRA governs (the in_government guard). `stop_on_leaving`:
## break when FRA leaves office, balance_probe.gd's stop. Returns the division
## log, the openings, C1's rows, FRA's relations at month TERM_MONTHS, when FRA
## left office, and whether the first term is valid.
func _run_term(bargain_always: bool, measure_c1: bool, months: int, stop_on_leaving: bool) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var state = _fresh()
	var ns = state.player()
	var council_ids: Array = Orgs.council_ids(state)
	var divisions: Array = []
	var openings: Array = []
	var c1_rows: Array = []
	var bargained := {}
	var strikes: Array = []
	var opened_ids := {}
	var months_run := 0
	var left_office := -1
	var left_office_date := ""
	var term_relations := {}
	var rel_by_month: Array = []
	var agenda: Array = []
	for org_id in council_ids:
		opened_ids[org_id] = {}

	var year := START_YEAR
	var month := 1
	for i in range(months):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		# ---- THE REAL MONTH: src/sim/world_month.gd, the order main.gd runs. This
		# run issues no command, which is what "idle" means; its reads ride the step
		# hook at the slot each one needs.
		# C6's diagnosis: the agenda each AI chair is about to see, read on the books
		# Orgs.tick_month is about to read. Context only; a run that does not record
		# it is the same run.
		var previews := {}
		WorldMonth.tick_month(state, _loader, func(step: String, after: bool, _report: Dictionary) -> void:
			if step == "Orgs" and not after:
				if measure_c1:
					for org_id in council_ids:
						var pv: Dictionary = _agenda_preview(state, org_id)
						if not pv.is_empty():
							previews[org_id] = pv
			elif step == "Orgs" and after:
				for org_id in previews.keys():
					var pend_now: Dictionary = Orgs.pending(state, org_id)
					var pv: Dictionary = previews[org_id]
					pv["opened"] = String(pend_now.get("proposal_id", "")) if int(pend_now.get("opened_year", 0)) == year and int(pend_now.get("opened_month", 0)) == month else ""
					pv["at"] = i + 1
					agenda.append(pv)
			elif step == "Elections" and not after:
				state.day = 0
				for d in range(_days_in_month(month, year)):
					state.day = d + 1
					# No command books anything, so nothing can be due; say so if it is.
					for appointment in Calendar.due(state, year, month, state.day):
						push_error("council_probe: an appointment fell due in an idle run: %s" % [appointment])
		)
		# ---- end of the real month.

		# The month's divisions, read off each council's record.
		for org_id in council_ids:
			var last: Dictionary = Orgs.last_vote(state, org_id)
			if not last.is_empty() and int(last.get("year", 0)) == year and int(last.get("month", 0)) == month:
				divisions.append({
					"org_id": org_id, "proposal_id": String(last["proposal_id"]),
					"year": year, "month": month, "passed": bool(last["passed"]),
					"decision": String(last.get("decision", "")),
					"vetoed_by": (last.get("vetoed_by", []) as Array).duplicate(),
				})

		# The player's turn, between months: every proposal opened THIS month.
		for org_id in council_ids:
			var pend: Dictionary = Orgs.pending(state, org_id)
			if pend.is_empty() or int(pend.get("opened_year", 0)) != year or int(pend.get("opened_month", 0)) != month:
				continue
			var pid := String(pend["proposal_id"])
			opened_ids[org_id][pid] = true
			openings.append({"org_id": org_id, "proposal_id": pid, "year": year, "month": month})
			if not ns.orgs.has(org_id) or i + 1 > TERM_MONTHS or not ns.in_government:
				continue
			var p = Orgs.proposal_by_id(_loader, org_id, pid)
			if measure_c1:
				c1_rows.append(_c1_opening(state, org_id, p))
			if bargain_always:
				var strike: Dictionary = _strike_if_deciding(state, org_id, p)
				if not strike.is_empty():
					strike["at"] = i + 1
					strike["org_id"] = org_id
					strike["proposal_id"] = pid
					bargained[String(strike["member"])] = true
					strikes.append(strike)
				var said: String = "no deciding bargain (forecast is the preference, or none flips it)"
				if not strike.is_empty():
					said = "bargained %s(%s), cost %.2f relations" % [strike["member"], strike["currency"], float(strike["cost"])]
				print("  always %d-%02d %-15s %-28s %s" % [year, month, org_id, pid, said])

		months_run = i + 1
		# C2's diagnosis reads FRA's relations month by month in both runs.
		if i + 1 <= TERM_MONTHS:
			rel_by_month.append(_relations_of(state))
		if i + 1 == TERM_MONTHS:
			term_relations = _relations_of(state)
		# balance_probe.gd's guard (its _run(), `if not ns.in_government: break`).
		if not ns.in_government and left_office < 0:
			left_office = i + 1
			left_office_date = "%d-%02d" % [year, month]
			print("  (FRA out of government from %s, month %d%s)" % [left_office_date, left_office,
				"; run stops" if stop_on_leaving else "; the councils keep dividing"])
			if stop_on_leaving:
				break

	if term_relations.is_empty():
		term_relations = _relations_of(state)
	# FRA in office through the whole first term: what C1/C2 need to be valid.
	var term_valid: bool = left_office < 0 or left_office > TERM_MONTHS
	var label: String = "always" if bargain_always else "idle/never"
	print("## run %s: %d divisions, %d openings, %.1f s" % [label, divisions.size(), openings.size(),
		float(Time.get_ticks_msec() - t0) / 1000.0])
	print("## run %s end: in_government %s, has_executive %s, months run %d of %d, left office %s; first term (1-%d) %s" % [
		label, str(ns.in_government), str(ns.has_executive), months_run, months,
		("%s (month %d)" % [left_office_date, left_office]) if left_office > 0 else "never",
		TERM_MONTHS, "VALID" if term_valid else "INVALID -- FRA left office inside it"])
	return {"state": state, "divisions": divisions, "openings": openings, "c1": c1_rows,
		"bargained": bargained, "strikes": strikes, "opened_ids": opened_ids,
		"months_run": months_run, "left_office": left_office, "left_office_date": left_office_date,
		"term_relations": term_relations, "term_valid": term_valid,
		"rel_by_month": rel_by_month, "agenda": agenda}


## C6's DIAGNOSIS: if `org_id` will open a proposal on this month's
## Orgs.tick_month, what the AI chair's window holds and why every other
## proposal is not in it. {} when no opening is due, or a human/no chair.
##
## HAND-COPIED from src/sim/orgs.gd `_tick_council()` (the countdown and the
## pending gate) and `_presidency_pick()` (the window). Checked, not trusted:
## the run records what actually opened beside the predicted pick and C6
## prints every mismatch.
func _agenda_preview(state, org_id: String) -> Dictionary:
	var register: Dictionary = state.orgs[org_id]
	if not (register.get("pending", {}) as Dictionary).is_empty():
		return {}
	if maxi(0, int(register.get("months_to_next", 0)) - 1) > 0:
		return {}
	if not (register.get("tabled", {}) as Dictionary).is_empty():
		return {}
	var chair: String = Council.presiding_nation(state, _loader, org_id)
	if chair == "" or state.nations[chair].has_budget:
		return {}
	var all: Array = _loader.org_proposals.get(org_id, [])
	var rules: Dictionary = register.get("rules", {})
	var constrained := 0
	for r in rules.values():
		if not String((r as Dictionary).get("field", "")).is_empty():
			constrained += 1
	var status := {}
	var window: Array = []
	var start := int(register.get("next_index", 0))
	for offset in all.size():
		var p = all[(start + offset) % all.size()]
		if rules.has(p.id):
			status[p.id] = "in-force"
		elif String((register.get("ratifying", {}) as Dictionary).get("proposal_id", "")) == p.id:
			status[p.id] = "ratifying"
		elif not p.constraint.is_empty() and constrained >= BK.MAX_RULES_IN_FORCE:
			status[p.id] = "capped"
		elif window.size() < CouncilK.CHAIR_WINDOW:
			window.append(p.id)
			status[p.id] = "window"
		else:
			status[p.id] = "beyond-window"
	var best := ""
	var best_s := -INF
	var supports := {}
	for pid in window:
		var s: float = Orgs.support(state, state.nations[chair], Orgs.proposal_by_id(_loader, org_id, pid))
		supports[pid] = s
		if s > best_s:
			best_s = s
			best = pid
	return {"org_id": org_id, "chair": chair, "window": window, "supports": supports,
		"predicted": best, "status": status, "constrained": constrained}


## FRA's relations with every nation, as a plain map -- the month-60 snapshot C2 reads.
func _relations_of(state) -> Dictionary:
	var out := {}
	for id in state.nations.keys():
		if String(id) != PLAYER:
			out[String(id)] = RK.score(state, PLAYER, String(id))
	return out


func _days_in_month(m: int, y: int) -> int:
	if m == 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
		return 29
	return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]


## Resolve a copy of `state` now (months_left 1, one Orgs tick) and say whether
## `org_id`'s pending proposal carried.
func _resolve_copy(copy, org_id: String) -> bool:
	copy.orgs[org_id]["pending"]["months_left"] = 1
	Orgs.tick_month(copy, _loader)
	return bool(Orgs.last_vote(copy, org_id).get("passed", false))


## C1 at one opening. Baseline: the copy divided with no bargain. If that is
## not FRA's preference, try every (member, currency) single bargain asking the
## preference, each on its own copy.
func _c1_opening(state, org_id: String, p) -> Dictionary:
	var want: bool = _prefers_pass(state, p)
	var forecast: bool = _resolve_copy(state.duplicate_state(), org_id)
	var row := {"org_id": org_id, "proposal_id": p.id, "year": state.year, "month": state.month,
		"want": want, "forecast": forecast, "decidable": false, "by": "",
		"blockers": [], "need": INF, "need_all": INF, "n_all": 0}
	if forecast == want:
		return row
	_c1_blockers(state, org_id, p, want, row)
	var ask: String = CouncilK.ASK_FOR if want else CouncilK.ASK_AGAINST
	for id in Orgs.members(state, org_id):
		if id == PLAYER:
			continue
		for currency in CouncilK.CURRENCIES:
			var copy = state.duplicate_state()
			if not Council.bargain(copy, org_id, id, currency, ask):
				continue
			if _resolve_copy(copy, org_id) == want:
				row["decidable"] = true
				row["by"] = "%s %s" % [currency, id]
				return row
	return row


## C1's DIAGNOSIS (context, not the band): at an opening whose forecast is not
## FRA's preference, which members vote against that preference and by how much
## (`blockers`, "ID:gap" sorted by gap), and `need`: the smallest single-bargain
## swing that would flip the division -- INF when no single member can (two or
## more unanimity vetoers, a QMR margin wider than any one member's seats, or the
## only blocker is the sponsor, which bargain() refuses). This is what says
## whether a swing sweep can move C1 at all. The appraisal read is the vote's own
## (support + lobbied swing on the pending entry, against SUPPORT_THRESHOLD).
func _c1_blockers(state, org_id: String, p, want: bool, row: Dictionary) -> void:
	var pend: Dictionary = Orgs.pending(state, org_id)
	var sponsor := String(pend.get("sponsor", ""))
	var unanimity: bool = Council.decision_of(_loader, p) == CouncilK.DECISION_UNANIMITY
	var seats_for := 0
	var cast := 0
	var opp: Array = []
	for id in Orgs.members(state, org_id):
		var seats: int = Orgs.live_seats(state, org_id, id)
		var votes_for: bool
		var s := 0.0
		if id == PLAYER:
			continue # abstaining in the forecast: in neither count
		elif id == sponsor:
			votes_for = true
		else:
			s = Orgs.support(state, state.nations[id], p) + Council.swing(pend, id)
			votes_for = s >= BK.SUPPORT_THRESHOLD
		cast += seats
		if votes_for:
			seats_for += seats
		if votes_for != want and id != sponsor:
			opp.append([id, absf(s - BK.SUPPORT_THRESHOLD), seats])
	opp.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var parts: Array = []
	for o in opp:
		parts.append("%s:%.3f" % [o[0], float(o[1])])
	row["blockers"] = parts
	var need := INF
	for o in opp:
		var flips := false
		if unanimity:
			# want pass: every vetoer must turn, so one bargain needs exactly one.
			# want fail: any one member turned against vetoes.
			flips = (opp.size() == 1) if want else true
		else:
			var sf: int = seats_for + int(o[2]) if want else seats_for - int(o[2])
			var carried: bool = cast > 0 and float(sf) >= BK.PASS_SEAT_FRACTION * float(cast)
			flips = carried == want
		if flips:
			need = minf(need, float(o[1]))
	row["need"] = need
	# The same question with one bargain PER MEMBER (the machine allows one per
	# member per division, so a player can work several): the smallest largest
	# swing over the cheapest set of members that flips it, and how many. Opp is
	# sorted by gap, so the first prefix that flips minimises the largest gap.
	# Context for the author, NOT the band -- the band is read on the single
	# bargain, as the probe declared before it ran.
	var need_all := INF
	var n_all := 0
	var sf_all: int = seats_for
	for k in opp.size():
		var o: Array = opp[k]
		sf_all += int(o[2]) if want else -int(o[2])
		var done := false
		if unanimity:
			done = (k == opp.size() - 1) if want else true
		else:
			done = (cast > 0 and float(sf_all) >= BK.PASS_SEAT_FRACTION * float(cast)) == want
		if done:
			need_all = float(o[1])
			n_all = k + 1
			break
	row["need_all"] = need_all
	row["n_all"] = n_all


## C2's `always` player at one opening. Strikes a bargain ONLY when a
## counterfactual shows it decides: the forecast (a copy divided now, C1's
## method) is not FRA's preference, and the same bargain struck on a copy flips
## that copy to it. Currency outer, member inner: every member in id order is
## tried with a favour first (the cheapest currency), then every member with
## aid; the first flipping bargain is struck on the live state. None flips:
## nothing is struck -- a bargain that changes no outcome is not what C2 prices.
## Returns {member, currency, cost} or {}.
func _strike_if_deciding(state, org_id: String, p) -> Dictionary:
	var want: bool = _prefers_pass(state, p)
	if _resolve_copy(state.duplicate_state(), org_id) == want:
		return {}
	var ask: String = CouncilK.ASK_FOR if want else CouncilK.ASK_AGAINST
	for currency in [CouncilK.CURRENCY_FAVOUR, CouncilK.CURRENCY_AID]:
		for id in Orgs.members(state, org_id):
			if id == PLAYER:
				continue
			var copy = state.duplicate_state()
			if not Council.bargain(copy, org_id, id, String(currency), ask):
				continue
			if _resolve_copy(copy, org_id) != want:
				continue
			var before: float = RK.score(state, PLAYER, String(id))
			if not Council.bargain(state, org_id, String(id), String(currency), ask):
				push_error("council_probe: a bargain struck on the copy was refused live")
				return {}
			return {"member": String(id), "currency": String(currency),
				"cost": before - RK.score(state, PLAYER, String(id))}
	return {}


# --- C1 .. C6 ---------------------------------------------------------------------------------

func _table_c1(idle: Dictionary) -> void:
	print("\n########## C1 the player decides (idle run, first term months 1-%d; one bargain on a copy, resolved at once) ##########" % TERM_MONTHS)
	print("%-8s %-15s %-28s %-6s %-9s %-10s %s" % ["opened", "org", "proposal", "wants", "forecast", "decidable", "by"])
	var decidable := 0
	var rows: Array = idle["c1"]
	var per := {}
	for r in rows:
		var key: String = "%s/%s" % [r["org_id"], r["proposal_id"]]
		if not per.has(key):
			per[key] = [0, 0]
		per[key][0] += 1
		if bool(r["decidable"]):
			decidable += 1
			per[key][1] += 1
		var diag: String = ""
		if bool(r["want"]) != bool(r["forecast"]):
			diag = "need %s (one per member: %s); against FRA's preference: %s" % [
				"none-single" if float(r["need"]) == INF else "%.3f" % float(r["need"]),
				"none" if float(r["need_all"]) == INF else "%d at <= %.3f" % [int(r["n_all"]), float(r["need_all"])],
				" ".join(PackedStringArray(r["blockers"]))]
		print("%d-%02d  %-15s %-28s %-6s %-9s %-10s %-16s %s" % [int(r["year"]), int(r["month"]), r["org_id"], r["proposal_id"],
			"pass" if bool(r["want"]) else "fail", "pass" if bool(r["forecast"]) else "fail",
			"YES" if bool(r["decidable"]) else ("-" if bool(r["want"]) == bool(r["forecast"]) else "no"), r["by"], diag])
	print("openings per proposal (opened / decidable):")
	var keys: Array = per.keys()
	keys.sort()
	var ever := 0
	for key in keys:
		if int(per[key][1]) > 0:
			ever += 1
		print("  %-45s %d / %d" % [key, int(per[key][0]), int(per[key][1])])
	var n: int = rows.size()
	var share: float = float(decidable) / float(n) if n > 0 else 0.0
	var distinct: float = float(ever) / float(keys.size()) if not keys.is_empty() else 0.0
	print("per-opening: divisions (FRA's councils) %d, decidable %d, share %.3f (context, not the band)" % [n, decidable, share])
	print("DISTINCT: proposals ever opened %d, ever decidable %d, share %.3f" % [keys.size(), ever, distinct])
	_c1_diagnosis(rows, keys.size())
	# The band reads the DISTINCT share: one proposal re-opening every few openings
	# must not set it by repetition.
	_band("C1", distinct >= C1_MIN and distinct <= C1_MAX, "distinct %.3f" % distinct, bool(idle["term_valid"]))


## C1's diagnosis summary (context): how the openings split, and the ceiling a
## swing sweep can reach -- the distinct share if the largest single swing were
## each multiple of today's strongest currency (IOU_SWING). A ceiling below the
## band says no swing value passes C1 and the miss is structural.
func _c1_diagnosis(rows: Array, distinct_opened: int) -> void:
	var same := 0
	var differ := 0
	var flipped := 0
	var structural := 0
	for r in rows:
		if bool(r["want"]) == bool(r["forecast"]):
			same += 1
			continue
		differ += 1
		if bool(r["decidable"]):
			flipped += 1
		if float(r["need"]) == INF:
			structural += 1
	print("C1 diagnosis: openings %d = forecast already FRA's preference %d + differs %d; of those differing, flipped by one bargain %d, no single bargain can (>=2 vetoers / margin) %d" % [
		rows.size(), same, differ, flipped, structural])
	for mult in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]:
		var cap: float = CouncilK.IOU_SWING * float(mult)
		var ids := {}
		var ids_all := {}
		for r in rows:
			if bool(r["want"]) == bool(r["forecast"]):
				continue
			var key: String = "%s/%s" % [r["org_id"], r["proposal_id"]]
			if float(r["need"]) <= cap:
				ids[key] = true
			if float(r["need_all"]) <= cap:
				ids_all[key] = true
		var d: float = float(distinct_opened) if distinct_opened > 0 else 1.0
		print("  ceiling at max swing %.3f (IOU_SWING x%.2f): distinct decidable <= %d / %d = %.3f single bargain; %d = %.3f one per member" % [
			cap, float(mult), ids.size(), distinct_opened, float(ids.size()) / d,
			ids_all.size(), float(ids_all.size()) / d])


func _table_c2(idle: Dictionary, always: Dictionary) -> void:
	print("\n########## C2 spending is not free (first term; FRA relations with the bargained members at month %d) ##########" % TERM_MONTHS)
	var valid: bool = bool(idle["term_valid"]) and bool(always["term_valid"])
	var strikes: Array = always["strikes"]
	var mix := {}
	var cost := 0.0
	for st in strikes:
		mix[st["currency"]] = int(mix.get(st["currency"], 0)) + 1
		cost += float(st["cost"])
	var mix_keys: Array = mix.keys()
	mix_keys.sort()
	var mix_parts: PackedStringArray = []
	for k in mix_keys:
		mix_parts.append("%s %d" % [k, int(mix[k])])
	var mean_cost: float = cost / float(strikes.size()) if not strikes.is_empty() else 0.0
	print("bargains struck %d; currency mix: %s; mean relations cost per bargain %.2f" % [strikes.size(),
		", ".join(mix_parts) if not mix_parts.is_empty() else "-", mean_cost])
	var mids: Array = (always["bargained"] as Dictionary).keys()
	mids.sort()
	if mids.is_empty():
		print("the always run struck no bargain -- nothing to compare")
		_band("C2", false, "n/a", valid)
		return
	var sum_never := 0.0
	var sum_always := 0.0
	print("%-6s %8s %8s %8s" % ["member", "never", "always", "gap"])
	for id in mids:
		var rn: float = float((idle["term_relations"] as Dictionary).get(String(id), 0.0))
		var ra: float = float((always["term_relations"] as Dictionary).get(String(id), 0.0))
		sum_never += rn
		sum_always += ra
		print("%-6s %8.2f %8.2f %8.2f" % [id, rn, ra, rn - ra])
	var mean_never: float = sum_never / float(mids.size())
	var mean_always: float = sum_always / float(mids.size())
	var gap: float = mean_never - mean_always
	print("bargained members %d; mean never %.2f, always %.2f, gap %.2f" % [mids.size(), mean_never, mean_always, gap])
	_c2_diagnosis(idle, always, mids)
	_band("C2", gap >= C2_MIN_GAP, "%.2f" % gap, valid)


## C2's DIAGNOSIS (context, not the band): each strike's month and price, how
## the bargained division actually went three months later, and the gap (never
## minus always) in FRA's relations with that member before the strike, just
## after it and at month TERM_MONTHS -- beside what DRIFT_RATE alone would have
## left of the price by then. The difference between the drift-only residual
## and the measured one is every other channel (the two worlds diverging).
func _c2_diagnosis(idle: Dictionary, always: Dictionary, mids: Array) -> void:
	var never_rel: Array = idle["rel_by_month"]
	var always_rel: Array = always["rel_by_month"]
	var keep: float = 1.0 - DiplomacyK.DRIFT_RATE
	print("C2 diagnosis (DRIFT_RATE %.3f: a price struck at month m keeps (1-DRIFT_RATE)^(%d-m) of itself by month %d)" % [
		DiplomacyK.DRIFT_RATE, TERM_MONTHS, TERM_MONTHS])
	print("  %-5s %-15s %-28s %-6s %-7s %6s %-9s %9s %9s %9s %9s" % ["month", "org", "proposal", "member", "curr",
		"cost", "division", "gap@m-1", "gap@m", "drift@60", "gap@60"])
	var paid := {}
	var drift_left := {}
	for st in always["strikes"]:
		var at: int = int(st["at"])
		var id := String(st["member"])
		var outcome: String = "?"
		for d in always["divisions"]:
			var idx: int = (int(d["year"]) - START_YEAR) * 12 + int(d["month"]) - 1
			if idx > at and String(d["org_id"]) == String(st["org_id"]) and String(d["proposal_id"]) == String(st["proposal_id"]):
				outcome = "carried" if bool(d["passed"]) else "failed"
				break
		var before: float = _gap_at(never_rel, always_rel, at - 1, id)
		var after: float = _gap_at(never_rel, always_rel, at, id)
		var predicted: float = float(st["cost"]) * pow(keep, TERM_MONTHS - at)
		paid[id] = float(paid.get(id, 0.0)) + float(st["cost"])
		drift_left[id] = float(drift_left.get(id, 0.0)) + predicted
		print("  %-5d %-15s %-28s %-6s %-7s %6.2f %-9s %9.2f %9.2f %9.2f %9.2f" % [at, st["org_id"], st["proposal_id"],
			id, st["currency"], float(st["cost"]), outcome, before, after, predicted,
			_gap_at(never_rel, always_rel, TERM_MONTHS, id)])
	for id in mids:
		var c: float = float(paid.get(String(id), 0.0))
		var rd: float = float(drift_left.get(String(id), 0.0))
		var ra: float = _gap_at(never_rel, always_rel, TERM_MONTHS, String(id))
		var share: float = (c - rd) / (c - ra) if absf(c - ra) > 0.0001 else 0.0
		print("  %s: paid %.2f; drift alone leaves %.2f at month %d, measured %.2f; drift's share of the decay %.2f, other channels %.2f" % [
			id, c, rd, TERM_MONTHS, ra, share, rd - ra])
		var traj: PackedStringArray = []
		for m in range(3, TERM_MONTHS + 1, 3):
			traj.append("m%d %.1f" % [m, _gap_at(never_rel, always_rel, m, String(id))])
		print("    gap trajectory: %s" % " ".join(traj))


## never - always relations for `id` at the end of month `m` (1-based); 0 outside the record.
func _gap_at(never_rel: Array, always_rel: Array, m: int, id: String) -> float:
	if m < 1 or m > never_rel.size() or m > always_rel.size():
		return 0.0
	return float((never_rel[m - 1] as Dictionary).get(id, 0.0)) - float((always_rel[m - 1] as Dictionary).get(id, 0.0))


func _table_c3(idle: Dictionary) -> void:
	print("\n########## C3 unanimity is reachable (full %d-month idle run's unanimity divisions) ##########" % int(idle["months_run"]))
	_left_office_context(idle)
	var carried := 0
	var vetoed := 0
	var per := {}
	for d in idle["divisions"]:
		if String(d["decision"]) != CouncilK.DECISION_UNANIMITY:
			continue
		var key: String = "%s/%s" % [d["org_id"], d["proposal_id"]]
		if not per.has(key):
			per[key] = [0, 0]
		if bool(d["passed"]):
			carried += 1
			per[key][0] += 1
		else:
			vetoed += 1
			per[key][1] += 1
		print("  %d-%02d %-40s %s %s" % [int(d["year"]), int(d["month"]), key,
			"CARRIED" if bool(d["passed"]) else "VETOED", ",".join(PackedStringArray(d["vetoed_by"]))])
	var keys: Array = per.keys()
	keys.sort()
	for key in keys:
		print("  %-40s carried %d, vetoed %d" % [key, per[key][0], per[key][1]])
	print("unanimity divisions %d: carried %d, vetoed %d" % [carried + vetoed, carried, vetoed])
	_band("C3", carried >= 1 and vetoed >= 1, "carried %d, vetoed %d" % [carried, vetoed])


func _table_c4() -> void:
	print("\n########## C4 ratification is a fight (treaty bills in FRA's new-game assembly) ##########")
	var state = _fresh()
	var ns = state.player()
	var parties: Array = _loader.parties.get(ns.id, [])
	var inside := 0
	var n := 0
	for org_id in Orgs.council_ids(state):
		for p in _loader.org_proposals.get(org_id, []):
			if Council.decision_of(_loader, p) != CouncilK.DECISION_UNANIMITY:
				continue
			n += 1
			var r: Dictionary = Legislature.resolve_vote(ns, parties, Ratification.treaty_bill(p))
			var yes: int = int(r["yes_seats"])
			var no: int = int(r["no_seats"])
			var share: float = float(yes) / float(yes + no) if yes + no > 0 else 0.0
			var hit: bool = share >= C4_YES_MIN and share <= C4_YES_MAX
			if hit:
				inside += 1
			print("  %-15s %-28s yes %3d no %3d abstain %3d  share %.3f %s" % [org_id, p.id, yes, no,
				int(r["abstain_seats"]), share, "IN" if hit else ""])
	print("unanimity proposals %d, inside [%.2f, %.2f]: %d" % [n, C4_YES_MIN, C4_YES_MAX, inside])
	_band("C4", inside >= C4_MIN_TREATIES, "%d" % inside)


func _table_c5() -> void:
	print("\n########## C5 the BURDEN_MAX re-measure (heaviest constraints in force, FRA past every tolerance) ##########")
	var state = _fresh()
	var ns = state.player()
	var council_ids: Array = Orgs.council_ids(state)
	var adopted: Array = []
	for org_id in council_ids:
		var rows: Array = []
		var all: Array = _loader.org_proposals.get(org_id, [])
		for i in all.size():
			if not all[i].constraint.is_empty():
				rows.append([all[i], i])
		# Heaviest first; authored order breaks a tie, so the pick is deterministic.
		rows.sort_custom(func(a, b):
			var sa: float = float(a[0].constraint["severity"])
			var sb: float = float(b[0].constraint["severity"])
			return sa > sb or (sa == sb and int(a[1]) < int(b[1])))
		for k in mini(rows.size(), BK.MAX_RULES_IN_FORCE):
			var p = rows[k][0]
			state.orgs[org_id]["rules"][p.id] = {
				"name": p.proposal_name, "field": String(p.constraint["field"]),
				"op": String(p.constraint["op"]), "value": float(p.constraint["value"]),
				"tolerance": float(p.constraint["tolerance"]), "severity": float(p.constraint["severity"]),
				"transfer_pct_gdp": p.transfer_pct_gdp,
				"since_year": state.year, "since_month": state.month,
			}
			adopted.append([org_id, p.id])
	# Past every tolerance, in each rule's breach direction. Two rules on one field
	# pulling opposite ways would leave the later one's push standing; the table
	# prints each contribution against its severity, so a short one shows.
	for pair in adopted:
		var rule: Dictionary = state.orgs[pair[0]]["rules"][pair[1]]
		var op := String(rule["op"])
		var past: float = float(rule["value"])
		if op == "<" or op == "<=":
			past += C5_PUSH_TOLERANCES * float(rule["tolerance"])
		else:
			past = maxf(0.0, past - C5_PUSH_TOLERANCES * float(rule["tolerance"]))
		_write_field(ns, String(rule["field"]), past)

	var raw := 0.0
	print("  %-15s %-28s %9s %12s" % ["org", "rule", "severity", "contribution"])
	for pair in adopted:
		var rule: Dictionary = state.orgs[pair[0]]["rules"][pair[1]]
		var c: float = float(Orgs.rule_breach(state, ns, String(pair[0]), rule)["contribution"])
		raw += c
		print("  %-15s %-28s %9.2f %12.4f" % [pair[0], pair[1], float(rule["severity"]), c])
	for org_id in council_ids:
		print("  org_burden %-15s %.4f" % [org_id, Orgs.org_burden(state, ns, org_id)])
	print("  RAW cross-org %.4f   BURDEN_MAX %.2f   clamped Orgs.burden %.4f   (V3.5: %.2f)" % [
		raw, BK.BURDEN_MAX, Orgs.burden(state, ns, council_ids), C5_V35_RAW])
	print("RECORDED C5 (%.4f)" % raw)


## Set the constrained field orgs.gd's _read_field() reads, on the probe's own state.
func _write_field(ns, field: String, value: float) -> void:
	match field:
		"deficit_pct_gdp": ns.deficit_pct_gdp = value
		"debt_to_gdp_pct": ns.debt_eur_bn = float(ns.gdp_eur_bn) * value / 100.0
		"total_spending_pct_gdp": ns.total_spending_pct_gdp = value
		"spending_defence": ns.spending_pct_gdp["defence"] = value
		"spending_infrastructure": ns.spending_pct_gdp["infrastructure"] = value
		"tax_corporate": ns.tax_rates_pct["corporate"] = value
		"tax_vat": ns.tax_rates_pct["vat"] = value
		"co2e_per_capita_t": ns.co2e_per_capita_t = value
		_:
			push_error("council_probe: no writer for constraint field '%s'" % field)


func _table_c6(idle: Dictionary) -> void:
	print("\n########## C6 agenda reach (full idle run: proposals never opened in %d of %d months) ##########" % [int(idle["months_run"]), MONTHS])
	_left_office_context(idle)
	var never := 0
	var opened_ids: Dictionary = idle["opened_ids"]
	var ids: Array = opened_ids.keys()
	ids.sort()
	for org_id in ids:
		var missing: Array = []
		var all: Array = _loader.org_proposals.get(org_id, [])
		for p in all:
			if not (opened_ids[org_id] as Dictionary).has(p.id):
				missing.append(p.id)
		never += missing.size()
		print("  %-15s opened %d of %d; never: %s" % [org_id, all.size() - missing.size(), all.size(),
			", ".join(PackedStringArray(missing)) if not missing.is_empty() else "-"])
	_c6_diagnosis(idle, opened_ids)
	_band("C6", never == 0, "%d never opened" % never)


## C6's diagnosis (context): for every proposal that never opened, at the
## AI-chair openings of the run, how often it sat in the chair's window (and
## what beat it there, with the chair's appraisal of each), and how often it
## was out of reach: in force, ratifying, capped by MAX_RULES_IN_FORCE, or
## eligible but past the window.
func _c6_diagnosis(idle: Dictionary, opened_ids: Dictionary) -> void:
	var agenda: Array = idle["agenda"]
	var mismatch := 0
	for pv in agenda:
		if String(pv["opened"]) != String(pv["predicted"]):
			mismatch += 1
			print("  preview MISMATCH month %d %s: predicted %s, opened %s" % [int(pv["at"]), pv["org_id"], pv["predicted"], pv["opened"]])
	print("C6 diagnosis: %d AI-chair openings previewed, %d mismatches against what opened (CHAIR_WINDOW %d, MAX_RULES_IN_FORCE %d)" % [
		agenda.size(), mismatch, CouncilK.CHAIR_WINDOW, BK.MAX_RULES_IN_FORCE])
	var ids: Array = opened_ids.keys()
	ids.sort()
	for org_id in ids:
		var capped_openings := 0
		var n := 0
		for pv in agenda:
			if String(pv["org_id"]) != org_id:
				continue
			n += 1
			if int(pv["constrained"]) >= BK.MAX_RULES_IN_FORCE:
				capped_openings += 1
		if n > 0:
			print("  %-15s AI-chair openings %d; at the constraint cap (%d binding rules in force) at %d of them" % [
				org_id, n, BK.MAX_RULES_IN_FORCE, capped_openings])
		for p in _loader.org_proposals.get(org_id, []):
			if (opened_ids[org_id] as Dictionary).has(p.id):
				continue
			var counts := {"window": 0, "in-force": 0, "ratifying": 0, "capped": 0, "beyond-window": 0}
			var beaten: Array = []
			for pv in agenda:
				if String(pv["org_id"]) != org_id:
					continue
				var st := String((pv["status"] as Dictionary).get(p.id, "?"))
				counts[st] = int(counts.get(st, 0)) + 1
				if st == "window":
					var sup: Dictionary = pv["supports"]
					beaten.append("m%d %s %.2f<%s %.2f" % [int(pv["at"]), pv["chair"], float(sup[p.id]),
						pv["predicted"], float(sup[pv["predicted"]])])
			print("    never %-30s constraint %-3s window %d, beyond-window %d, capped %d, in-force %d, ratifying %d" % [
				p.id, "yes" if not p.constraint.is_empty() else "no", int(counts["window"]), int(counts["beyond-window"]),
				int(counts["capped"]), int(counts["in-force"]), int(counts["ratifying"])])
			if not beaten.is_empty():
				print("      in the window, beaten: %s" % "; ".join(PackedStringArray(beaten)))


## Context for the full-run bands: the council divides whoever governs France,
## so leaving office invalidates nothing here -- but a reader should know.
func _left_office_context(run: Dictionary) -> void:
	if int(run["left_office"]) > 0:
		print("context: FRA left office %s (month %d); the councils kept dividing" % [run["left_office_date"], int(run["left_office"])])
	else:
		print("context: FRA held office all %d months" % int(run["months_run"]))


# --- S: the sweep ------------------------------------------------------------------------------

func _table_s(proposal_id: String) -> bool:
	var p = null
	for org_id in _loader.org_proposals.keys():
		for q in _loader.org_proposals[org_id]:
			if q.id == proposal_id:
				p = q
	if p == null:
		printerr("--sweep: no proposal '%s'" % proposal_id)
		return false
	print("\n########## S sweep %s (%s, %s) ##########" % [p.id, p.org_id, Council.decision_of(_loader, p)])
	print("cells: CA carries-alone, PD player-decides, LA lost-anyway; * = abstention-window;")
	print("       a unanimity row appends how many members veto with FRA for (gate G3 reads it)")
	print("authored position: economic %.2f, social %.2f" % [float(p.position.get("economic", 0.0)), float(p.position.get("social", 0.0))])
	var unanimity: bool = Council.decision_of(_loader, p) == CouncilK.DECISION_UNANIMITY
	var kept: Dictionary = (p.position as Dictionary).duplicate()
	var head: String = "%-12s" % "soc \\ eco"
	for e in SWEEP_AXIS:
		head += "%8.1f" % float(e)
	print(head)
	for s in SWEEP_AXIS:
		var line: String = "%-12.1f" % float(s)
		for e in SWEEP_AXIS:
			p.position = {"economic": float(e), "social": float(s)}
			var t: Dictionary = _tally(p)
			var code: String = String(VERDICT_CODE[t["verdict"]])
			code += "*" if bool(t["abst_window"]) else ""
			if unanimity:
				code += str(((t["for"] as Dictionary).get("vetoed_by", []) as Array).size())
			line += "%8s" % code
		print(line)
	p.position = kept
	return true
