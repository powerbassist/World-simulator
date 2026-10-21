extends SceneTree

## V1.1e. The second chamber: where its composition comes from, what its refusal does,
## and the four properties the design rests on. Model: docs/upper-house-model.md.
##
## The load-bearing assertions are the ones about what does NOT happen:
##
##   - the chamber's composition is IDENTICAL to the Assembly's at new game, because the
##     ideological tilt was measured and deleted. What makes it a check is that it votes
##     on spatial_support() where the Assembly votes on support(), and the difference is
##     the coalition bonus -- so this is asserted with exact equality, and a later session
##     re-adding a tilt turns it red and has to say why;
##   - src/sim/chambers.gd is a LEAF: it does not name legislature.gd, it does not know a
##     law exists, and it never calls a vote;
##   - resolve_vote() is UNTOUCHED by the second chamber -- about twenty-five call sites
##     read it, and the upper house reaching into it would be a second writer of the
##     project's central verb;
##   - a bill the chamber HOLDS is in flight: no cooldown, not re-proposable, and it
##     arrives on its own without a command from the player;
##   - a bill the chamber BLOCKS is dead and carries a cooldown;
##   - an ABSENT `government.upper` block is a legal, authored state -- Luxembourg -- and
##     a unicameral nation needs no branch anywhere;
##   - and Article 49.3 is the way PAST the second chamber, which is a property nobody
##     authored and which falls out of _force() skipping the chamber and not the court.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const CK = preload("res://src/sim/chambers_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")
const Government = preload("res://src/sim/government.gd")

const PLAYER := "FRA"

var _loader: DataLoader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_authored_for_all_ten()
	_test_luxembourg_is_unicameral()
	_test_composition_is_identical_at_new_game()
	_test_seats_are_derived_not_stored()
	_test_the_chamber_votes_unwhipped()
	_test_chambers_is_a_leaf()
	_test_resolve_vote_is_untouched()
	_test_a_held_bill_is_in_flight()
	_test_a_held_bill_arrives_on_its_own()
	_test_a_blocked_bill_is_dead()
	_test_power_over_reads_the_class_of_bill()
	_test_the_lag_survives_an_election()
	_test_both_harnesses_still_tick_the_legislature()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_upper_house: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _state():
	return GameState.new_game(_loader, PLAYER)


func _parties() -> Array:
	return _loader.parties.get(PLAYER, [])


## Every law in the file, by id.
func _law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


# ---------------------------------------------------------------------------

func _test_authored_for_all_ten() -> void:
	var state = _state()
	var with_chamber := 0
	for ns in state.nations.values():
		if not ns.has_upper_house:
			continue
		with_chamber += 1
		if ns.upper_chamber_name == "":
			_fail("%s has a second chamber with no name" % ns.id)
		if ns.upper_seats < CK.MIN_SEATS or ns.upper_seats > CK.MAX_SEATS:
			_fail("%s upper_seats %d is outside the guard rails" % [ns.id, ns.upper_seats])
		if not CK.KNOWN_VERDICTS.has(ns.upper_ordinary):
			_fail("%s upper_ordinary '%s' is not a verdict" % [ns.id, ns.upper_ordinary])
		if not CK.KNOWN_VERDICTS.has(ns.upper_amendment):
			_fail("%s upper_amendment '%s' is not a verdict" % [ns.id, ns.upper_amendment])
	# Thirteen of the EU-29, plus Bosnia's House of Peoples and Belarus's Council of
	# the Republic at V4.11 -- a content count, re-measured with the roster.
	if with_chamber != 15:
		_fail("expected fifteen bicameral nations of forty-one, got %d" % with_chamber)


## Luxembourg's Chambre des Deputes is unicameral and the Conseil d'Etat's opposition
## formelle is an advisory opinion forcing a second vote rather than a chamber. An absent
## block is the legal, authored state -- `government.executive`'s shape -- and the caller
## needs no branch, which is what power_over() returning VERDICT_NONE buys.
func _test_luxembourg_is_unicameral() -> void:
	var state = _state()
	var lux = state.nations["LUX"]
	if lux.has_upper_house:
		_fail("LUX has a second chamber; the Chambre des Deputes is unicameral")
		return
	if not Chambers.seats(lux).is_empty():
		_fail("a unicameral nation returned a chamber")
	for law in _loader.laws:
		if Chambers.power_over(lux, law) != CK.VERDICT_NONE:
			_fail("a unicameral nation claims a power over %s" % law.id)
			return


## EXACT EQUALITY, and it is the assertion this session's shape rests on. The tilt was
## designed, swept and deleted -- a bloc anchor put the nationalist right at 267 of
## France's 348 senators, and anchoring on the chamber's own centre made it MORE
## permissive rather than less. See src/sim/chambers_constants.gd.
func _test_composition_is_identical_at_new_game() -> void:
	var state = _state()
	var ns = state.player()
	var share: Dictionary = Chambers.target_share(ns, _parties())
	var total := 0.0
	for party in _parties():
		total += float(ns.seats_by_party.get(party.id, 0))
	for party in _parties():
		var expected: float = float(ns.seats_by_party.get(party.id, 0)) / total
		if absf(float(share.get(party.id, 0.0)) - expected) > 1e-12:
			_fail("the second chamber is TILTED away from the Assembly for %s: %f vs %f"
				% [party.id, float(share.get(party.id, 0.0)), expected])
	for party in _parties():
		if absf(float(ns.upper_share.get(party.id, 0.0)) - float(share.get(party.id, 0.0))) > 1e-12:
			_fail("upper_share was not seeded at the target for %s" % party.id)


## Chambers.seats() derives them from the share the way Defence.allies() derives an
## alliance from the pacts. The save format asserts the absence separately; this asserts
## the derivation agrees with the allocator, so a later session storing seats has two
## reds to answer rather than one.
func _test_seats_are_derived_not_stored() -> void:
	var ns = _state().player()
	var derived := Chambers.seats(ns)
	var expected := ElectoralSystems.pr_national(ns.upper_share, ns.upper_seats, 0.0)
	if derived != expected:
		_fail("Chambers.seats() is not pr_national over upper_share")
	var total := 0
	for party_id in derived:
		total += int(derived[party_id])
	if total != ns.upper_seats:
		_fail("the chamber holds %d seats and should hold %d" % [total, ns.upper_seats])


## THE WHOLE CHECK, in one assertion. The Assembly carries a bill on the coalition bonus
## and the second chamber has no government in it, so it votes on the bill alone. If this
## ever reads zero the second chamber is a second reading and the session has no content.
func _test_the_chamber_votes_unwhipped() -> void:
	var state = _state()
	var ns = state.player()
	var refused := 0
	for law in _loader.laws:
		var lower := Legislature.resolve_vote(ns, _parties(), law, false)
		if not bool(lower["passed"]):
			continue
		if not bool(Legislature.resolve_upper(ns, _parties(), law)["passed"]):
			refused += 1
	if refused < 1:
		_fail("the Senat refuses NOTHING the Assembly carries -- there is no second chamber")

	# And the reason, asserted rather than described: a coalition party's line in the
	# Assembly carries a bonus the same party does not get in the second chamber.
	var law = _law("emissions_standards")
	if law == null:
		_fail("emissions_standards is not in data/laws -- the coalition-bonus check would measure nothing")
		return
	var moved := 0
	for party in _parties():
		if absf(Legislature.support(ns, party, law) - Legislature.spatial_support(ns, party, law)) > 1e-9:
			moved += 1
	if moved < 1:
		_fail("no party's support differs from its spatial support -- the bonus is not live")


func _test_chambers_is_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/chambers.gd")
	if src.is_empty():
		_fail("could not read src/sim/chambers.gd")
		return
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if line.contains("legislature.gd") and not line.contains("legislature_constants.gd"):
			_fail("chambers.gd preloads legislature.gd -- the dependency runs one way")
		if line.contains("res://src/core/law.gd"):
			_fail("chambers.gd preloads law.gd -- it does not know a law exists")
	if src.contains("resolve_vote"):
		_fail("chambers.gd names resolve_vote -- vote resolution is legislature.gd's job")


## About twenty-five call sites read resolve_vote(). The second chamber reuses the two
## public functions beside it instead, which is what let this session change the central
## verb's OUTCOME without changing the function every test in the suite calls.
func _test_resolve_vote_is_untouched() -> void:
	var state = _state()
	var ns = state.player()
	for law in _loader.laws:
		var result := Legislature.resolve_vote(ns, _parties(), law, false)
		for key in ["upper_passed", "held_by_upper", "blocked_by_upper", "struck_down"]:
			if result.has(key):
				_fail("resolve_vote() returned '%s' -- the second chamber reached into it" % key)
				return


## HELD, not defeated: in flight, off the open list, and carrying no cooldown, because the
## bill has not been beaten. Referendum.is_pending()'s treatment at V1.7c.
func _test_a_held_bill_is_in_flight() -> void:
	var state = _state()
	var ns = state.player()
	var law = _held_law(ns)
	if law == null:
		_fail("no law in the content is both carried by the Assembly and refused by the Senat")
		return

	var result := Legislature.propose(state, _loader, law)
	if not bool(result.get("held_by_upper", false)):
		_fail("%s was not held: %s" % [law.id, result])
		return
	if bool(result["passed"]):
		_fail("a held bill reported passed")
	if ns.passed_law_ids.has(law.id):
		_fail("a held bill set its `once` flag")
	if ns.law_cooldown_months.has(law.id):
		_fail("a held bill was put on cooldown -- it has not been beaten")
	# The ultra pass-2 shape: {"months", "origin"} -- and the origin is
	# "player", because the override price the release charges is the
	# GOVERNMENT's insistence priced, and this hold is the government's.
	var held: Dictionary = ns.held_bills.get(law.id, {})
	if int(held.get("months", 0)) != CK.UPPER_HOLD_MONTHS:
		_fail("the hold was not %d months" % CK.UPPER_HOLD_MONTHS)
	if String(held.get("origin", "")) != "player":
		_fail("propose()'s hold must carry origin \"player\" -- the release prices it, the assembly's holds release free")
	for open_law in Legislature.available(ns, _loader.laws):
		if open_law.id == law.id:
			_fail("a held bill is still proposable -- the player could restart the clock")


## It arrives on its own, priced. No second division and no command from the player, which
## is what a suspensive veto is.
func _test_a_held_bill_arrives_on_its_own() -> void:
	var state = _state()
	var ns = state.player()
	var law = _held_law(ns)
	if law == null:
		return
	Legislature.propose(state, _loader, law)

	# THE LAW'S OWN CHARGE IS SUBTRACTED OUT, which is what isolates the override.
	# Read on "workers" as a bare before/after until the V2.8 review, and that law
	# authors bloc_offset.workers = -0.10, so the law's charge plus an override
	# applied with the WRONG SIGN summed to -0.05 and matched -UPPER_OVERRIDE_OFFSET
	# by coincidence: the test was green against a release that PAID the player.
	# Every bloc this law names is scored, so the sign cannot hide in any one of them.
	var authored: Dictionary = law.effects.get("bloc_offset", {})
	var before: Dictionary = {}
	for bloc in ns.bloc_offset.keys():
		before[bloc] = float(ns.bloc_offset[bloc])

	for i in range(CK.UPPER_HOLD_MONTHS):
		Legislature.tick_month(state, _loader)
	if ns.held_bills.has(law.id):
		_fail("the hold did not expire after %d ticks" % CK.UPPER_HOLD_MONTHS)
	if law.once and not ns.passed_law_ids.has(law.id):
		_fail("a released bill did not take effect")

	for bloc in before.keys():
		var moved := float(ns.bloc_offset.get(bloc, 0.0)) - float(before[bloc])
		var charged := moved - float(authored.get(bloc, 0.0))
		if absf(charged + CK.UPPER_OVERRIDE_OFFSET) > 1e-9:
			_fail("overriding the second chamber cost %f on %s, expected %f"
				% [charged, String(bloc), -CK.UPPER_OVERRIDE_OFFSET])


## An `absolute` refusal kills the bill and cools it down. Reached by hand rather than
## through France, whose ordinary row is suspensive -- the point is the branch, not the
## nation.
func _test_a_blocked_bill_is_dead() -> void:
	var state = _state()
	var ns = state.player()
	var law = _held_law(ns)
	if law == null:
		return
	ns.upper_ordinary = CK.VERDICT_ABSOLUTE
	var result := Legislature.propose(state, _loader, law)
	if not bool(result.get("blocked_by_upper", false)):
		_fail("an absolute chamber did not block: %s" % result)
		return
	if ns.held_bills.has(law.id):
		_fail("a blocked bill was held -- it is dead, not delayed")
	if law.cooldown_months > 0 and not ns.law_cooldown_months.has(law.id):
		_fail("a blocked bill carries no cooldown")


## Two rows, and which one applies is the CLASS of bill. France delays an ordinary bill
## under Art. 45 and cannot be overridden on a revision under Art. 89.
func _test_power_over_reads_the_class_of_bill() -> void:
	var ns = _state().player()
	if ns.upper_ordinary == ns.upper_amendment:
		_fail("France's two rows are the same; Art. 45 and Art. 89 are not the same rule")
	for law in _loader.laws:
		var expected: String = ns.upper_amendment if law.constitutional else ns.upper_ordinary
		if Chambers.power_over(ns, law) != expected:
			_fail("power_over() read the wrong row for %s" % law.id)
			return


## The lag is the second half of the check. Renewed by hand at the shipped rate, the
## chamber must still differ from an Assembly that has turned over.
func _test_the_lag_survives_an_election() -> void:
	var state = _state()
	var ns = state.player()
	var before: Dictionary = ns.upper_share.duplicate()

	# A landslide: give one party everything and renew.
	var winner: String = _parties()[0].id
	for party in _parties():
		ns.seats_by_party[party.id] = ns.assembly_seats if party.id == winner else 0
	Chambers.renew(ns, _parties())

	if absf(float(ns.upper_share.get(winner, 0.0)) - 1.0) < 1e-9:
		_fail("a landslide swept the second chamber outright -- there is no lag")
	if absf(float(ns.upper_share.get(winner, 0.0)) - float(before.get(winner, 0.0))) < 1e-9:
		_fail("the second chamber did not renew at all -- it is frozen")
	var total := 0.0
	for party_id in ns.upper_share:
		total += float(ns.upper_share[party_id])
	if absf(total - 1.0) > 1e-9:
		_fail("the renewed chamber's shares sum to %f, not 1.0" % total)


## tests/test_events.gd reads four files and fails if any omits Events.tick_month. The
## held-bill countdown rides on Legislature.tick_month() precisely so it needs no such
## check of its own -- and this asserts that premise rather than trusting it.
func _test_both_harnesses_still_tick_the_legislature() -> void:
	# THREE files, not tests/test_events.gd's four: Budget.project() runs Economy and
	# Budget alone -- it is a fiscal projection, not a month of the game -- so a held
	# bill is invisible to it BY DESIGN and asserting otherwise would be asking the
	# projection to legislate. The difference is stated rather than the list copied.
	# Since the world-month refactor the three run ONE month, src/sim/world_month.gd
	# (tests/test_world_month.gd holds them to it), so that is the file read.
	for path in ["res://src/sim/world_month.gd"]:
		var src := FileAccess.get_file_as_string(path)
		if src.is_empty():
			_fail("could not read %s" % path)
			continue
		if not src.contains("Legislature.tick_month"):
			_fail("%s does not call Legislature.tick_month -- the hold is invisible to it" % path)


## The first law the Assembly carries and the Senat refuses. Found in the content rather
## than named, so a content edit cannot leave these tests quietly measuring nothing.
func _held_law(ns):
	for law in _loader.laws:
		if law.constitutional:
			continue
		if not bool(Legislature.resolve_vote(ns, _parties(), law, false)["passed"]):
			continue
		if bool(Legislature.resolve_upper(ns, _parties(), law)["passed"]):
			continue
		return law
	return null
