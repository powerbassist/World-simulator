extends SceneTree

## Gameplay #157's measured band (docs/design/v5.2-bplus-spec.md "R4", the France
## month-6 row). Two France games from one start. After six months, one dismisses a
## portfolio of the largest coalition party the president does not lead (the
## president's own if there is none); the other is its undismissed twin. From then,
## the first bill whose division has the worked example's shape IN THE TWIN -- that
## party's line yes, its members' own view no, the only case where resolve_vote()
## counts rebels -- is tabled in both and divided at the next close (R2's tabling,
## the game's own month). The band: that party casts at least 1 fewer yes seat in
## the dismissed game, and the bill's yes margin is no higher there.
##
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/removal_probe.gd
##
## Exit 0 when the band holds, 1 when it misses or no bill had the shape.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Removal = preload("res://src/sim/removal.gd")
const Characters = preload("res://src/sim/characters.gd")
const President = preload("res://src/sim/president.gd")

const PLAYER := "FRA"
const START_YEAR := 2026
const DISMISS_AFTER_MONTHS := 6
const LAST_MONTH := 60


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	var dismissed = GameState.new_game(loader, PLAYER)
	var twin = GameState.new_game(loader, PLAYER)
	var party = null
	for i in range(LAST_MONTH):
		if i == DISMISS_AFTER_MONTHS:
			party = _dismiss(dismissed, loader)
			if party == null:
				printerr("removal_probe: no coalition party holds a portfolio to dismiss")
				quit(1)
				return
		if party != null:
			var law = _shaped_bill(twin, loader, party)
			if law != null and Legislature.open_law(dismissed, dismissed.player(), loader, law.id) != null:
				Legislature.propose(dismissed, loader, law)
				Legislature.propose(twin, loader, law)
				var a := _row(dismissed, _tick(dismissed, loader, i)["division"], party)
				var b := _row(twin, _tick(twin, loader, i)["division"], party)
				print("removal_probe: %s dismissed at %d-%02d; bill '%s' divides %04d-%02d" % [
					party.id, START_YEAR, DISMISS_AFTER_MONTHS + 1, law.id, twin.year, twin.month])
				for pair in [["twin", b], ["dismissed", a]]:
					var r: Dictionary = pair[1]
					print("  %-9s line %-3s rebels %3d  party yes %3d  bill yes %3d no %3d margin %+d" % [
						pair[0], r["line"], r["rebels"], r["party_yes"], r["yes"], r["no"], r["margin"]])
				var holds := int(a["party_yes"]) <= int(b["party_yes"]) - 1 and int(a["margin"]) <= int(b["margin"])
				print("removal_probe: band %s (party yes %d vs %d, margin %+d vs %+d)" % [
					"HOLDS" if holds else "MISSES", a["party_yes"], b["party_yes"], a["margin"], b["margin"]])
				quit(0 if holds else 1)
				return
		_tick(dismissed, loader, i)
		_tick(twin, loader, i)
	printerr("removal_probe: no bill had the shape by month %d" % LAST_MONTH)
	quit(1)


## The month after `i`, the game's own (src/sim/world_month.gd).
func _tick(state, loader, i: int) -> Dictionary:
	state.month = (i + 1) % 12 + 1
	state.year = START_YEAR + (i + 1) / 12
	return WorldMonth.tick_month(state, loader)


## The largest coalition party (by seats) the president does not lead that holds a
## portfolio, else the president's own; one of its portfolios dismissed. The party row.
func _dismiss(state, loader):
	var ns = state.player()
	var pick = null
	var fallback = null
	for p in loader.parties.get(PLAYER, []):
		if not ns.coalition_party_ids.has(p.id) or not ns.cabinet.values().has(p.id):
			continue
		if Characters.party_leader(ns, p.id, {p.id: p.leader_person_id}) == President.leader_id(ns):
			fallback = p
		elif pick == null or int(ns.seats_by_party.get(p.id, 0)) > int(ns.seats_by_party.get(pick.id, 0)):
			pick = p
	if pick == null:
		pick = fallback
	if pick == null:
		return null
	for f in ns.cabinet:
		if String(ns.cabinet[f]) == pick.id:
			if not bool(Removal.dismiss(state, loader, f).get("ok", false)):
				return null
			return pick
	return null


## The first open bill on which `party` votes yes as a line while its members' own
## view is no, read on the twin.
func _shaped_bill(state, loader, party):
	var ns = state.player()
	for law in Legislature.available(ns, loader.laws):
		if Legislature.vote_of(Legislature.support(ns, party, law)) == "yes" \
				and Legislature.vote_of(Legislature.spatial_support(ns, party, law)) == "no":
			return law
	return null


## The party's side of a division of that shape: its line, its rebels, the yes seats
## it cast (the line's seats less its rebels; none when the line itself turned no),
## and the bill's yes, no and margin.
func _row(state, division: Dictionary, party) -> Dictionary:
	var line := String(division.get("party_votes", {}).get(party.id, ""))
	var rebels := int(division.get("party_rebels", {}).get(party.id, 0))
	var seats := int(state.player().seats_by_party.get(party.id, 0))
	var yes := int(division.get("yes_seats", 0))
	var no := int(division.get("no_seats", 0))
	return {"line": line, "rebels": rebels, "party_yes": seats - rebels if line == "yes" else 0,
		"yes": yes, "no": no, "margin": yes - no}
