extends RefCounted

## The Regions arrival -- the block 0 gate's G6, "nothing points at the Regions tab": the
## tab held a verb (the fund, the priority) that no surface ever sent the player to. So when
## the nation's worst region passes the data's threshold (data/region-actions/fund.json,
## `arrival`), one quiet card says so in Regions.problem()'s own figure, with a Go on that
## region.
##
## IT SPENDS NONE OF THE 4 + 6 A YEAR (docs/design/decision-surfaces.md): the card waits in
## the inbox and never touches the clock. It is one card, for the worst region only: a
## nation's spread is standing, and a card per region past the line would be the noise that
## document found. It comes back after the rule's months, and not while a fund runs there.
##
## What was told lives here, not in the save: a load or a new game is a new state and
## starts over (the briefing's own rule), and the inbox's cards do not survive one either.

const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const Migration = preload("res://src/sim/migration.gd")
const RegionFund = preload("res://src/ui/region_fund.gd")
const Strings = preload("res://src/ui/strings.gd")

## What the Go acts on (acts_on.gd), before the region's id.
const SUBJECT := "region_arrival|"

## main's instance id -> {state_id, told: {region id: month}, cards: {live card id: region
## id}, wired: the Go's handler is connected}.
static var _told := {}


## {region, problem} for the region whose Regions.problem() ratio is the highest, or {}.
static func worst(state, ns) -> Dictionary:
	var list: Array = state.regions.get(ns.id, [])
	if list.is_empty():
		return {}
	# Every month, on the month's last frame: the nation's unemployment once, not per region.
	var rates: Dictionary = Regions.unemployment_by_region(ns, list, Regions.accessibility_for(ns, list, state.region_graph),
		state.project_sited_pct.get(ns.id, {}))
	var out := {}
	for region in list:
		var p: Dictionary = Regions.problem_of(ns, float(rates.get(region.id, 0.0)),
			Regions.gdp_per_head_index(ns, list, region.id, Migration.region_share(ns, region.id)))
		if out.is_empty() or float(p["ratio"]) > float(out["problem"]["ratio"]):
			out = {"region": region, "problem": p}
	return out


## The month's check. Called at the month's end, whatever else the month shows.
static func check(main) -> void:
	var state = main._state
	var ns = state.player() if state != null else null
	var rule: Dictionary = main._loader.region_fund_rule.get("arrival", {})
	# Out of government the region's verbs are not the player's to take.
	if ns == null or rule.is_empty() or not bool(ns.in_government):
		return
	var found := worst(state, ns)
	if found.is_empty() or float(found["problem"]["ratio"]) < float(rule["ratio"]):
		return
	var id := String(found["region"].id)
	var now := int(state.year) * 12 + int(state.month)
	var memory: Dictionary = _told.get_or_add(main.get_instance_id(), {"state_id": 0, "told": {}, "cards": {}, "wired": false})
	if int(memory["state_id"]) != state.get_instance_id():
		memory["state_id"] = state.get_instance_id()
		memory["told"] = {}
		memory["cards"] = {}
	if (memory["told"] as Dictionary).has(id) and now - int(memory["told"][id]) < int(rule["rearm_months"]):
		return
	# Its last card still waits unanswered: it says the same, so no second one.
	var inbox = main._hud.inbox
	for card in memory["cards"]:
		if String(memory["cards"][card]) == id and inbox.lane_of(String(card)) != "":
			return
	for row in RegionFunds.open_funds(ns):
		if String(row["region_id"]) == id:
			return
	memory["told"][id] = now
	if not bool(memory["wired"]):
		memory["wired"] = true
		inbox.card_action.connect(_on_go.bind(main))
	var card: String = inbox.push(String(found["region"].region_name), RegionFund.problem_text(found["problem"]),
		[{"label": Strings.t("Open"), "acts_on": SUBJECT + id}])
	memory["cards"][card] = id


static func _on_go(card: String, _index: int, main) -> void:
	var cards: Dictionary = (_told.get(main.get_instance_id(), {}) as Dictionary).get("cards", {})
	if not cards.has(card):
		return
	var panel = main._windows.content("region")
	main._windows.open("region")
	# The panel's own pick: it refocuses the row, so a region low in the list comes into
	# view, and centres the map. A pick on the open region would close it.
	panel._open_region = ""
	panel._pick(String(cards[card]))
	panel.mark_dirty()
	cards.erase(card)
	main._hud.inbox.dismiss(card)
