extends SceneTree

## People probe: godot --headless --script res://tools/people_probe.gd
##
## U6b's named measurement, and it runs BEFORE a single name is authored.
## data/people/ does not exist when this file is written; the bench is
## synthesised in memory from loader.parties, because the derivation needs *ids*
## and a name is the last thing a roster needs. That ordering is the whole point:
## U6a's own probe deleted the constant it was written to tune, and this one is
## allowed to delete the minister bench before it costs 72 authored names and the
## largest tools/check_names.sh exposure the project has ever had.
##
##   (P1) THE REACHABILITY CEILING -- how many portfolios can ONE party hold at
##        once? Every bench slot above that number is unreachable at any seat
##        split, so authoring it is writing content with no caller. Reported two
##        ways: a STATIC ceiling over every internally-compatible coalition
##        (a superset of what Government.form() can produce, so a safe bound) and
##        the ceiling actually OBSERVED across 168-month runs. V1.3f's error was
##        measuring the static table and shipping a world that only new games
##        have; the fix is not to prefer one reading but to print both.
##
##   (P2) DISTINCT PEOPLE SEEN -- THE KILL SWITCH. Over 168 months of a playing
##        player, how many distinct people ever reach an in-place surface? If a
##        stable coalition means the president meets eight people in fourteen
##        years, a five-deep bench is dead content and the honest response is to
##        cut it, not to author it and hope. Accepted only at or above
##        PEOPLE_SEEN_MIN.
##
##        The People window is EXCLUDED from this count, deliberately. It lists
##        the whole register, so counting it makes every authored person
##        trivially "seen" and the measurement circular -- a directory cannot be
##        the justification for the thing it directories.
##
##   (P2b) IDENTITY CHURN -- the escalation trigger the plan named first. A
##        derived minister is a function of (portfolio, party, bench order), so
##        Cabinet.assign() moving a portfolio between parties can make a person
##        appear to change department mid-term with no election. If that is
##        common the derived model produces a nonsense career and the response is
##        to STORE the assignment after all -- a model change, declared in
##        advance rather than discovered.
##
##   (P3) BANNED-LIST PRE-FLIGHT. Once data/people/ exists, word-boundary-match
##        every authored surname against tools/banned_names.txt, so the exposure
##        is found here rather than by a red check_names.sh. Skipped silently
##        before the register is written, which is the only state this probe's
##        first run sees.
##
## Not a test. tests/test_people.gd asserts the invariants; this prints the
## spread a human reads. Kept in tools/ and excluded from run_tests.sh, same as
## balance_probe.gd, calendar_probe.gd, bloc_probe.gd and the rest.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Elections = preload("res://src/sim/elections.gd")

const MONTHS := 168
const START_YEAR := 2026

## The three nations with an opinion model. The other seven get no bench at all
## -- docs/cabinet-model.md's own "no opinion model for the nine, so there is
## nothing for a minister to be competent AT", one scale wider.
const PLAYABLE := ["DEU", "FRA", "GBR"]

## The band P2 is judged against, fixed HERE, before the sweep runs, so the
## numbers can falsify the bench rather than be fitted to it.
##
## Derived rather than felt: two executives plus one distinct minister per
## portfolio, across roughly three elections and the censures between them,
## should clear twelve comfortably. Below it, more than two thirds of a
## five-deep bench never reaches a screen however long the game is played.
const PEOPLE_SEEN_MIN := 12

## How often a derived minister may change department with no intervening
## election before the derivation itself is the wrong model. Not a tuned
## constant and it never reaches src/ -- it is the threshold on an escalation
## trigger, fixed before the measurement like the band above.
const CHURN_MAX_PER_RUN := 6

## Budget deltas lifted from tools/balance_probe.gd's REGIMES, in the same
## nation-relative percentage points, because P2 needs a player who ACTS. A
## do-nothing player re-elects the same government forever and would measure the
## floor of the cast rather than its size -- U6a's probe made exactly this
## correction twice and this file is written to not make it a third time.
const RUN_REGIMES := {
	"hands_off": {},
	"managed": {
		"spending_pct_gdp": {"defence": -1.4},
		"tax_rates_pct": {"vat": 3.0},
	},
	"austerity": {
		"spending_pct_gdp": {
			"health": -2.5, "education": -2.0, "defence": -1.0,
			"pensions": -3.5, "infrastructure": -2.0,
		},
		"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
	},
}

## A player who reshuffles. Every RESHUFFLE_EVERY months the largest coalition
## partner takes a portfolio it does not hold -- the cheapest legal way to move
## a portfolio between parties, which is the only thing that can produce P2b's
## churn at all.
const RESHUFFLE_EVERY := 18

## The deepest bench the synthesiser hands out. Deliberately ABOVE any plausible
## authored value so P1's ceiling is measured rather than clipped by this number.
const SYNTH_BENCH := 5


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	_ceiling_table(loader)
	_seen_table(loader)
	_banned_preflight(loader)
	quit(0)


## The synthetic register: every party fields a SHADOW CABINET -- one
## spokesperson per portfolio, keyed by portfolio rather than ordered by rank.
## Exactly the shape data/people/<NATION>.json will carry, with the names left
## out.
##
## The first version of this probe handed each party a flat ORDERED bench and
## picked by rank within the portfolios that party currently held. P2b measured
## that dead: adding one portfolio to a party renumbers every minister it
## already has, so a person changes department for a reason that has nothing to
## do with them -- 22 such moves in one fourteen-year run. Keyed by portfolio,
## churn is not damped but STRUCTURALLY IMPOSSIBLE, which is the shape V1.3f's
## AGENDA_AMITY_TARGET correction took and the shape this project prefers.
##
## It is also the more legible model by a distance: a party has a health
## spokesperson, and when the party takes Health that person becomes Health
## Minister. That is how an opposition front bench actually works, and it needs
## no explaining on a screen.
func _synth_bench(loader) -> Dictionary:
	var out := {}
	for nation_id in PLAYABLE:
		var parties: Array = loader.parties.get(nation_id, [])
		for p in parties:
			var by_portfolio := {}
			for f in CK.PORTFOLIO_KEYS:
				by_portfolio[f] = "%s_%s_%s" % [nation_id, p.id, f]
			out[p.id] = by_portfolio
	return out


## The derivation, carried locally because src/core/people.gd does not exist
## yet. Ported verbatim to that file at L2 -- if the two ever disagree, this
## probe measured something the game does not do.
##
## The party leader is NOT on the bench and cannot be a minister: a leader leads,
## and five spokespeople shadow five departments. That removes the "one person,
## one office" exclusion the rank model needed, along with the way that exclusion
## made a bench shorter for the governing party than for its partners.
func _minister(bench_by_party: Dictionary, ns, portfolio: String) -> String:
	var pid: String = String(ns.cabinet.get(portfolio, ""))
	if pid == "":
		return ""
	var by_portfolio: Dictionary = bench_by_party.get(pid, {})
	return String(by_portfolio.get(portfolio, ""))


## (P1) -----------------------------------------------------------------------
func _ceiling_table(loader) -> void:
	print("\n########## (P1) the reachability ceiling ##########")
	print("How many portfolios can ONE party hold at once? Every bench slot above")
	print("that is unreachable at any seat split -- content with no caller, and")
	print("~%d authored names per party per slot." % PLAYABLE.size())
	print("")
	print("`static` enumerates every internally-compatible coalition (no")
	print("excluded_partners violation), which is a SUPERSET of what")
	print("Government.form() can produce and therefore a safe upper bound.")
	print("`observed` is the largest count any party actually reached across the")
	print("%d-month runs P2 drives." % MONTHS)
	print("")
	print("%-8s %8s %10s %10s" % ["nation", "parties", "static", "observed"])
	print("-".repeat(40))

	var observed := _observed_ceilings(loader)
	var static_max := {}
	for nation_id in PLAYABLE:
		var parties: Array = loader.parties.get(nation_id, [])
		var state = GameState.new_game(loader, nation_id)
		var ns = state.player()
		var best := 0
		var n: int = parties.size()
		for mask in range(1, 1 << n):
			var subset: Array[String] = []
			for i in range(n):
				if mask & (1 << i):
					subset.append(String(parties[i].id))
			if not _compatible(subset, parties):
				continue
			ns.coalition_party_ids = subset
			var ent: Dictionary = Cabinet.entitlement(ns, parties)
			for pid in ent.keys():
				best = maxi(best, int(ent[pid]))
		static_max[nation_id] = best
		print("%-8s %8d %10d %10d" % [
			nation_id, parties.size(), best, int(observed.get(nation_id, 0)),
		])

	print("")
	print("A single-party government holds every portfolio, so the static ceiling")
	print("is %d wherever one party alone is a legal coalition." % CK.PORTFOLIO_KEYS.size())
	print("")
	print("PRE-COMMITMENT: the authored bench is sized to the OBSERVED ceiling,")
	print("and the static ceiling is recorded rather than authored against. The")
	print("fallback makes that safe by construction -- a rank past the end of a")
	print("bench returns \"\" and the caller prints the PARTY name, which is what")
	print("government_panel.gd prints today. Over-running a bench degrades to the")
	print("current game; it cannot fail loudly, and it cannot fail silently either,")
	print("because tests/test_people_panel.gd asserts that exact fallback.")


## Symmetric, the way src/sim/government.gd reads a cordon: a subset is legal
## only if no member lists another member in excluded_partners.
func _compatible(subset: Array[String], parties: Array) -> bool:
	var by_id := {}
	for p in parties:
		by_id[p.id] = p
	for a in subset:
		if not by_id.has(a):
			continue
		for b in subset:
			if a == b:
				continue
			if by_id[a].excluded_partners.has(b):
				return false
			if by_id.has(b) and by_id[b].excluded_partners.has(a):
				return false
	return true


func _observed_ceilings(loader) -> Dictionary:
	var out := {}
	for nation_id in PLAYABLE:
		var best := 0
		for regime_name in RUN_REGIMES.keys():
			var r := _run(loader, nation_id, String(regime_name))
			best = maxi(best, int(r["max_simultaneous"]))
		out[nation_id] = best
	return out


## (P2) -----------------------------------------------------------------------
func _seen_table(loader) -> void:
	print("\n\n########## (P2) distinct people seen -- the kill switch ##########")
	print("Over %d months, how many distinct people reach an IN-PLACE surface?" % MONTHS)
	print("Counted: the head of state, the head of government, the five derived")
	print("ministers, and a censured predecessor. NOT counted: the People window,")
	print("which lists the register and would make every authored person")
	print("trivially seen.")
	print("")
	print("Accepted at or above %d. Below it the bench is CUT -- U6a's currency" % PEOPLE_SEEN_MIN)
	print("deletion one session on, and cabinet-model.md's deferral is recorded as")
	print("still-correct rather than reversed.")
	print("")
	print("%-8s %-12s %6s %7s %6s %6s %6s %8s" % [
		"nation", "regime", "seen", "median", "mins", "elecs", "churn", "vacant%",
	])
	print("-".repeat(70))

	var worst := 999
	var worst_label := ""
	var worst_churn := 0
	for nation_id in PLAYABLE:
		for regime_name in RUN_REGIMES.keys():
			var r := _run(loader, nation_id, String(regime_name))
			var seen: int = int(r["seen"])
			if seen < worst:
				worst = seen
				worst_label = "%s/%s" % [nation_id, regime_name]
			worst_churn = maxi(worst_churn, int(r["churn"]))
			print("%-8s %-12s %6d %7d %6d %6d %6d %7.1f%%" % [
				nation_id, regime_name, seen, int(r["median_month"]),
				int(r["distinct_ministers"]), int(r["elections"]), int(r["churn"]),
				float(r["vacant_pct"]),
			])

	print("")
	print("`median` is how many of the seven in-place slots are filled by a")
	print("distinct person in the median month -- a cast that is large only")
	print("because a censure churned it is a different thing from one the player")
	print("meets, and one number cannot say which.")
	print("")
	print("`vacant%` is the share of months with a WHOLLY empty cabinet. It is")
	print("printed because the first run's worst reading was a government that had")
	print("collapsed rather than a roster that was thin, and a cast size with no")
	print("vacancy column beside it cannot tell those apart.")
	print("")
	if worst < PEOPLE_SEEN_MIN:
		print("KILL SWITCH FIRED at %s: %d distinct people against a floor of %d." % [
			worst_label, worst, PEOPLE_SEEN_MIN,
		])
		print("The minister bench is CUT. U6b ships as the register, the re-key and")
		print("the People window; ministers stay party-named and V1.1d's deferral is")
		print("recorded as still correct.")
	else:
		print("Band cleared. Worst case %s at %d distinct people." % [worst_label, worst])
		print("The bench is authored, sized to P1's observed ceiling.")

	print("")
	print("---- (P2b) identity churn, the first escalation trigger ----")
	print("A derived minister changing department with NO intervening election is")
	print("the nonsense career the derivation could produce. Worst run: %d." % worst_churn)
	if worst_churn > CHURN_MAX_PER_RUN:
		print("ABOVE the pre-committed ceiling of %d. The derivation is the wrong" % CHURN_MAX_PER_RUN)
		print("model and the honest response is to STORE the assignment --")
		print("ns.cabinet_person, on a SAVE_VERSION that is already moving to 14.")
	else:
		print("At or below the pre-committed ceiling of %d. Derivation held." % CHURN_MAX_PER_RUN)


## One 168-month run. Returns the distinct-people count, the per-month median,
## the ceiling any one party reached, and the churn count.
func _run(loader, nation_id: String, regime_name: String) -> Dictionary:
	var state = GameState.new_game(loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	var party_list: Array = loader.parties.get(nation_id, [])
	var bench_by_party := _synth_bench(loader)

	var delta: Dictionary = RUN_REGIMES[regime_name]
	if not delta.is_empty():
		Budget.commit(state, _resolve_pending(state.player(), delta))

	var seen := {}
	var ministers_seen := {}
	var filled_per_month: Array[int] = []
	var max_simultaneous := 0
	var elections := 0
	var churn := 0
	var vacant_months := 0
	var last_portfolio_of := {}
	var last_election_month := -1
	# Counted off last_election changing rather than off months_in_term hitting
	# zero. The first run of this probe used the latter and reported ZERO
	# elections for every nation across fourteen years, which is impossible --
	# elections.gd advances the term before this loop ever reads it. A counter
	# whose value is impossible invalidates everything gated on it, and churn
	# was gated on it.
	var last_election_seen := {}

	for i in range(MONTHS):
		_tick(state, loader, i)
		var ns = state.player()

		var le: Dictionary = ns.last_election
		if not le.is_empty() and le != last_election_seen:
			elections += 1
			last_election_month = i
			last_election_seen = le.duplicate()

		if i > 0 and i % RESHUFFLE_EVERY == 0:
			_reshuffle(state, ns, party_list)

		var pm_id := _pm_id(ns, bench_by_party)
		var hos_id := _hos_id(loader, ns, bench_by_party)
		var here := {}
		if pm_id != "":
			seen[pm_id] = true
			here[pm_id] = true
		if hos_id != "":
			seen[hos_id] = true
			here[hos_id] = true

		var counts := {}
		var vacant := 0
		for f in CK.PORTFOLIO_KEYS:
			var pid: String = String(ns.cabinet.get(f, ""))
			if pid == "":
				vacant += 1
			else:
				counts[pid] = int(counts.get(pid, 0)) + 1
			var person := _minister(bench_by_party, ns, String(f))
			if person == "":
				continue
			seen[person] = true
			ministers_seen[person] = true
			here[person] = true
			# Churn: the same person, a different department, no election since.
			# Structurally impossible under the shadow-cabinet keying, and still
			# measured -- an invariant nobody checks is an invariant nobody has.
			var was: String = String(last_portfolio_of.get(person, ""))
			if was != "" and was != String(f) and last_election_month < i - 1:
				churn += 1
			last_portfolio_of[person] = String(f)
		for pid in counts.keys():
			max_simultaneous = maxi(max_simultaneous, int(counts[pid]))
		if vacant == CK.PORTFOLIO_KEYS.size():
			vacant_months += 1

		filled_per_month.append(here.size())

	return {
		"seen": seen.size(),
		"distinct_ministers": ministers_seen.size(),
		"median_month": _median(filled_per_month),
		"max_simultaneous": max_simultaneous,
		"elections": elections,
		"churn": churn,
		"vacant_pct": 100.0 * float(vacant_months) / float(MONTHS),
	}


## The largest coalition partner takes a portfolio it does not already hold --
## the cheapest legal way to move one between parties, and the only thing in the
## game that can produce P2b's churn.
func _reshuffle(state, ns, party_list: Array) -> void:
	if ns.coalition_party_ids.is_empty():
		return
	var taker := String(ns.coalition_party_ids[0])
	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) == taker:
			continue
		if Cabinet.can_assign(ns, String(f), taker):
			Cabinet.assign(state, String(f), taker, party_list)
			return


## The synthetic stand-ins for the two fields L3 re-keys. A leader is not on the
## shadow bench, so both resolve to the party LEADER's own placeholder -- which
## reproduces FRA exactly, where the President is the governing party's leader,
## and is why the shadow model needs no "one person, one office" exclusion: a
## leader is structurally not a spokesperson.
func _leader_id(nation_id: String, party_id: String) -> String:
	return "%s_%s_lead" % [nation_id, party_id]


func _pm_id(ns, _bench_by_party: Dictionary) -> String:
	var pid := String(ns.pm_party_id)
	if pid == "":
		return ""
	return _leader_id(String(ns.id), pid)


func _hos_id(loader, ns, _bench_by_party: Dictionary) -> String:
	var nation = loader.nations.get(ns.id, null)
	if nation == null:
		return ""
	var pid := String(nation.leader_party_id)
	if pid == "":
		return "%s_hos" % ns.id
	return _leader_id(String(ns.id), pid)


## (P3) -----------------------------------------------------------------------
func _banned_preflight(loader) -> void:
	print("\n\n########## (P3) banned-list pre-flight ##########")
	var dir := DirAccess.open("res://data/people")
	if dir == null:
		print("data/people/ does not exist yet -- skipped.")
		print("")
		print("This is the state the FIRST run of this probe sees, and it is the")
		print("point of the ordering: P1 and P2 decide whether names are authored")
		print("at all, so there is nothing to pre-flight until after they have run.")
		print("Re-run at L1, once the register exists.")
		return

	var banned: Array[String] = []
	var f := FileAccess.open("res://tools/banned_names.txt", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			banned.append(line)

	var hits := 0
	var checked := 0
	for nation_id in loader.nations.keys():
		var path := "res://data/people/%s.json" % nation_id
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var raw: Array = parsed.get("people", [])
		for entry in raw:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var person_name := String(entry.get("person_name", ""))
			checked += 1
			for b in banned:
				# Word-boundary, matching check_names.sh's own `grep -InFw`, so a
				# banned short name that is an honest substring of an invented one
				# is not reported here either.
				if _word_match(person_name, b):
					print("HIT  %s: '%s' contains banned '%s'" % [nation_id, person_name, b])
					hits += 1

	print("%d authored people checked against %d banned entries: %d hit(s)." % [
		checked, banned.size(), hits,
	])
	if hits == 0:
		print("Clean. tools/check_names.sh is still the gate -- this only finds the")
		print("problem earlier, and it does not see the ids or the titles.")


func _word_match(haystack: String, needle: String) -> bool:
	var words := haystack.replace("-", " ").replace(".", " ").split(" ", false)
	var needle_words := needle.replace("-", " ").replace(".", " ").split(" ", false)
	if needle_words.is_empty():
		return false
	for i in range(words.size() - needle_words.size() + 1):
		var all := true
		for j in range(needle_words.size()):
			if String(words[i + j]).to_lower() != String(needle_words[j]).to_lower():
				all = false
				break
		if all:
			return true
	return false


## main.gd's _on_month_elapsed() order. Copied rather than shared, the way every
## other probe in tools/ copies it -- a probe that drifts from the game's own
## month is measuring a different game.
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
	Defence.tick_month(state)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)


## tools/balance_probe.gd's own, verbatim: a delta in percentage points against
## the nation's own starting rates, since V1.2a made starting policy per-nation.
func _resolve_pending(ns, delta: Dictionary) -> Dictionary:
	var pending := {}
	if delta.has("tax_rates_pct"):
		var rates := {}
		for key in delta["tax_rates_pct"]:
			var start: float = float(ns.start_tax_rates_pct.get(key, 0.0))
			rates[key] = clampf(start + float(delta["tax_rates_pct"][key]), 0.0, 100.0)
		pending["tax_rates_pct"] = rates
	if delta.has("spending_pct_gdp"):
		var spending := {}
		for key in delta["spending_pct_gdp"]:
			var start: float = float(ns.start_spending_pct_gdp.get(key, 0.0))
			spending[key] = clampf(start + float(delta["spending_pct_gdp"][key]), 0.0, 100.0)
		pending["spending_pct_gdp"] = spending
	return pending


func _median(xs: Array) -> int:
	if xs.is_empty():
		return 0
	var sorted := xs.duplicate()
	sorted.sort()
	return int(sorted[sorted.size() / 2])
