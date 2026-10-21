extends RefCounted

## V4.9b. Election night's count: the regions of the player's nation declare
## one at a time, smallest first, and the running national figures move as
## each comes in -- the verdict already decided, revealed in the order a real
## night reveals it. Built from results Elections.tick_month() returned and
## the regional tilt Elections.regional_shares() derives; it decides nothing.
##
## The count is a continuous `counted` in [0, n]: whole numbers are regions
## declared, the fraction rolls the figures toward the next declaration. At n
## the shares returned ARE the result's own dictionary, so the settled panel
## reads exactly the numbers the result carries, not a sum that agrees with
## them to the last bit.
##
## Smallest first because that is how a night runs: the big regions are where
## the count takes longest, so the lead is decided late -- and here, where they
## are also where the population weight is, the running figure moves most at
## the end.

const Elections = preload("res://src/sim/elections.gd")

## [{id, name, weight}], in declaration order.
var order: Array = []
## Per result: its national shares, and the running shares after k regions
## (k = 0 .. n), precomputed so a frame of the count is a lerp, not a sum.
var _national: Array = []
var _running: Array = []
var _counted_weight: Array = []


func _init(state, results: Array) -> void:
	var ns = state.player()
	var region_list: Array = state.regions.get(ns.id, [])
	var regions: Array = []
	for region in region_list:
		regions.append({
			"id": region.id,
			"name": region.region_name,
			"weight": float(ns.region_pop_share.get(region.id, 0.0)),
			"jobless_index": region.unemployment_rel,
		})
	regions.sort_custom(func(a, b):
		if a["weight"] != b["weight"]:
			return a["weight"] < b["weight"]
		return String(a["id"]) < String(b["id"])
	)
	order = regions
	var total := 0.0
	for r in regions:
		total += float(r["weight"])
	# No population shares at all (a data gap on a new nation): every region
	# counts the same, rather than a count whose bars read full from frame one.
	if total <= 0.0:
		for r in regions:
			r["weight"] = 1.0
		total = float(regions.size())
	var jobs_salience: float = float(ns.issue_salience.get("jobs", 0.0))

	var cumulative := [0.0]
	for r in regions:
		cumulative.append(float(cumulative[-1]) + float(r["weight"]))
	for k in cumulative.size():
		_counted_weight.append(float(cumulative[k]) / total if total > 0.0 else 1.0)

	for result in results:
		var national: Dictionary = result.get("vote_share", {})
		_national.append(national)
		var regional: Dictionary = Elections.regional_shares(
			national, String(result.get("incumbent_party_id", "")), regions, jobs_salience)
		var steps: Array = []
		var sums := {}
		for party_id in national.keys():
			sums[party_id] = 0.0
		steps.append(sums.duplicate())
		for i in regions.size():
			var r: Dictionary = regions[i]
			var shares: Dictionary = regional.get(r["id"], national)
			for party_id in national.keys():
				sums[party_id] = float(sums[party_id]) + float(r["weight"]) * float(shares[party_id])
			var running := {}
			for party_id in national.keys():
				running[party_id] = float(sums[party_id]) / float(cumulative[i + 1]) if float(cumulative[i + 1]) > 0.0 else 0.0
			steps.append(running)
		_running.append(steps)


func size() -> int:
	return order.size()


## The running vote shares of result `index` with `counted` regions declared.
func shares_at(index: int, counted: float) -> Dictionary:
	var n := size()
	if counted >= float(n):
		return _national[index]
	var k := clampi(floori(counted), 0, n - 1)
	var frac: float = clampf(counted - float(k), 0.0, 1.0)
	var a: Dictionary = _running[index][k]
	var b: Dictionary = _running[index][k + 1]
	var out := {}
	for party_id in a.keys():
		out[party_id] = lerpf(float(a[party_id]), float(b[party_id]), frac)
	return out


## The share of the electorate counted so far, 0 to exactly 1.
func counted_weight(counted: float) -> float:
	var n := size()
	if counted >= float(n):
		return 1.0
	var k := clampi(floori(counted), 0, n - 1)
	return lerpf(float(_counted_weight[k]), float(_counted_weight[k + 1]), clampf(counted - float(k), 0.0, 1.0))


## Regions fully declared at `counted`, and the name of the last of them.
func declared(counted: float) -> int:
	return clampi(floori(counted), 0, size())


func latest(counted: float) -> String:
	var k := declared(counted)
	return "" if k == 0 else String(order[k - 1]["name"])  # i18n: row-ok a party's name, a proper noun
