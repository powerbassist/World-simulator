extends SceneTree

## Dissolution probe: godot --headless --script res://tools/dissolution_probe.gd
##
## V1.1c's measurement, taken BEFORE the dissolution schema was written. Sweeps
## a snap legislative election's result across the approval range a player can
## actually hold while still in office (27-50; only the May 2027 executive vote
## can end a run below that), and reports the coalition it returns.
##
## Elections.resolve() and Government.form() are pure and deterministic, so this
## sets bloc_approval directly rather than simulating months of ticks -- the
## question is "what does a snap return at this approval", not "how does a
## regime get there".
##
## Not a test, not shipped -- see balance_probe.gd's own note for why this class
## of file lives in tools/ and stays out of run_tests.sh.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Elections = preload("res://src/sim/elections.gd")
const Government = preload("res://src/sim/government.gd")
const K = preload("res://src/sim/opinion_constants.gd")

const APPROVAL_LEVELS := [27.0, 30.0, 35.0, 40.0, 44.0, 47.0, 50.0]


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	print("  approval  incumbent seats  coalition seats  minority/majority")

	var party_list: Array = loader.parties.get("FRA", [])
	var results := {}

	for approval in APPROVAL_LEVELS:
		var state = GameState.new_game(loader, "FRA")
		state.year = 2026
		state.month = 2
		var ns = state.player()

		for bloc in K.BLOC_KEYS:
			ns.bloc_approval[bloc] = approval
		ns.overall_approval_pct = approval

		var result := Elections.resolve(ns, party_list, "two_round", 0.0, "national", state.year, state.month)
		ns.seats_by_party = result["seats"]
		ns.censure_barred_party_ids = []
		Government.form(ns, party_list)

		results[approval] = ns.coalition_seats
		print("  %6.1f    %6d           %6d           %s" % [
			approval, result["incumbent_seats"], ns.coalition_seats,
			"minority" if ns.is_minority else "majority",
		])

	var lo: float = results[APPROVAL_LEVELS[0]]
	var hi: float = results[APPROVAL_LEVELS[APPROVAL_LEVELS.size() - 1]]
	var spread := absf(hi - lo)
	print("")
	print("  starting assembly coalition: %d" % _starting_coalition(loader, party_list))
	print("  coalition at approval 50: %d" % int(hi))
	print("  coalition at approval 27: %d" % int(lo))
	print("  spread: %d seats" % int(spread))
	if spread >= 40.0:
		print("  >= 40: gamble already resolves. Section 4 (coalition swing) NOT needed.")
	else:
		print("  < 40: gamble does not resolve. Section 4 (coalition swing) required.")

	quit(0)


func _starting_coalition(loader, party_list: Array) -> int:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.player()
	return ns.coalition_seats
