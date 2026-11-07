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
## What was told lives here, not in the save: a new session tells it once more, and the
## inbox's cards do not survive one either.

const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const Migration = preload("res://src/sim/migration.gd")
const RegionFund = preload("res://src/ui/region_fund.gd")
const Strings = preload("res://src/ui/strings.gd")

## What the Go acts on (acts_on.gd), before the region's id.
const SUBJECT := "region_arrival|"

## main's instance id -> {told: {region id: month}, card: the live card's id, region: its
## region id, wired: the Go's handler is connected}.
static var _told := {}


## {region, problem} for the region whose Regions.problem() ratio is the highest, or {}.
static func worst(state, ns) -> Dictionary:
	var list: Array = state.regions.get(ns.id, [])
	if list.is_empty():
		return {}
	var access := Regions.accessibility_for(ns, list, state.region_graph)
	var sites: Dictionary = state.project_sited_pct.get(ns.id, {})
	var out := {}
	for region in list:
		var p: Dictionary = Regions.problem(ns, list, region.id, access, sites, Migration.region_share(ns, region.id))
		if out.is_empty() or float(p["ratio"]) > float(out["problem"]["ratio"]):
			out = {"region": region, "problem": p}
	return out


## The month's check. Called at the month's end, whatever else the month shows.
static func check(main) -> void:
	var state = main._state
	var ns = state.player() if state != null else null
	var rule: Dictionary = main._loader.region_fund_rule.get("arrival", {})
	if ns == null or rule.is_empty():
		return
	var found := worst(state, ns)
	if found.is_empty() or float(found["problem"]["ratio"]) < float(rule["ratio"]):
		return
	var id := String(found["region"].id)
	var now := int(state.year) * 12 + int(state.month)
	var memory: Dictionary = _told.get_or_add(main.get_instance_id(), {"told": {}, "card": "", "region": "", "wired": false})
	if (memory["told"] as Dictionary).has(id) and now - int(memory["told"][id]) < int(rule["rearm_months"]):
		return
	for row in RegionFunds.open_funds(ns):
		if String(row["region_id"]) == id:
			return
	memory["told"][id] = now
	memory["region"] = id
	var inbox = main._hud.inbox
	if not bool(memory["wired"]):
		memory["wired"] = true
		inbox.card_action.connect(_on_go.bind(main))
	memory["card"] = inbox.push(String(found["region"].region_name), RegionFund.problem_text(found["problem"]),
		[{"label": Strings.t("Open"), "acts_on": SUBJECT + id}])


static func _on_go(card: String, _index: int, main) -> void:
	var memory: Dictionary = _told.get(main.get_instance_id(), {})
	if String(memory.get("card", "")) != card:
		return
	var panel = main._windows.content("region")
	panel._open_region = String(memory["region"])
	main._windows.open("region")
	panel.mark_dirty()
	main._hud.inbox.dismiss(card)
