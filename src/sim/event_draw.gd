extends RefCounted

## Which event a draw picks -- Events' leaf, beside event_chooser.gd and
## event_hooks.gd. Two picks, both pure functions over candidates events.gd hands in
## (it owns every gate and the delivery):
##   - the standing hazard's weighted winner inside one pulsing category, moved here
##     whole from events.gd at V5.3 B7 when the quiet-month call needed the room
##     (AGENTS.md's size ratchet), its arithmetic unchanged;
##   - the quiet-month call's pick (V5.3 B7, docs/design/v5.3-b7-density.md section 4;
##     the author's calls 2 and 3, 2026-11-10): a minor event whose answers really
##     differ, drawn by likelihood.
##
## "Really differ" is the band's own rule (tools/density_count.gd, the probe that
## measures B7) on the two axes the parent's ruling names: two answers whose bloc
## arrows differ, or whose money differs by QUIET_MONEY_BN. The arrow is defined HERE
## and the probe reads it, so the call and the count cannot drift apart. The money is
## a first-order estimate -- spending and other revenue as points of GDP, a tax at its
## average yield per point of rate -- where the probe books the choice on a copy of
## the world; the two agree away from the 0.5 bn line, and the shipped book's minor
## events sit far from it (tests/test_quiet_month.gd checks them against the probe's
## rule). Approval, the band's third strip axis, is not a filter: an event whose blocs
## move a little each way reads as no arrow, and the call wants a choice the player
## can see.

const Cycle = preload("res://src/sim/cycle.gd")
const K = preload("res://src/sim/events_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")


## The weighted winner inside one pulsing category. One hash per (nation,
## category, sorted eligible roster, month) walked against the cumulative authored
## weights -- a pure function like the hazard, so a reload mid-month picks the
## same winner. The key carries the SORTED roster of eligible ids, not the
## category alone (the category is in the key too): what the roster adds is a
## RE-KEY whenever the eligible set changes as gates open and close, so a
## category's winners do not ride one stream through a changing book -- with no
## stored draw anywhere, which is the pin test_save_load.gd holds.
static func weighted_pick(ns, fired: Array, month_index: int):
	var total := 0.0
	var roster: Array[String] = []
	for ev in fired:
		total += float(ev.weight)
		roster.append(String(ev.id))
	if total <= 0.0:
		return fired[0]
	roster.sort()
	var draw: float = Cycle.unit(
		"%s|%s|draw|%s" % [ns.id, String(fired[0].category), "|".join(roster)],
		month_index
	) * total
	for ev in fired:
		draw -= float(ev.weight)
		if draw < 0.0:
			return ev
	return fired[fired.size() - 1]


## The quiet-month call's event: among `pool` (the minor hazard events whose gates
## pass this month), those whose answers differ, one drawn by likelihood -- the
## hazard's own weighing of how often an event happens. Keyed like the weighted pick,
## on the sorted roster, so a reload mid-month calls the same event. null when no
## event in the pool differs.
static func quiet_pick(ns, pool: Array, month_index: int):
	var picks: Array = []
	var roster: Array[String] = []
	var total := 0.0
	for ev in pool:
		if meaningful(ns, ev):
			picks.append(ev)
			roster.append(String(ev.id))
			total += float(ev.likelihood)
	if picks.is_empty() or total <= 0.0:
		return null
	roster.sort()
	var draw: float = Cycle.unit("%s|quiet|%s" % [ns.id, "|".join(roster)], month_index) * total
	for ev in picks:
		draw -= float(ev.likelihood)
		if draw < 0.0:
			return ev
	return picks[picks.size() - 1]


## Whether two of an event's answers differ on a bloc arrow or on money.
static func meaningful(ns, ev) -> bool:
	var answers: Array = []
	for choice in ev.choices:
		answers.append(choice.get("effects", {}))
	return answers_differ(ns, answers)


## Whether two of these answers -- effects dictionaries, an event choice's or a
## process ask's -- differ on a bloc arrow, on the balance a year, or on a one-off
## price on the debt (`debt_eur_bn`, which a process ask carries): the band's money
## axis is either (tools/density_count.gd).
static func answers_differ(ns, answers: Array) -> bool:
	var strips: Array = []
	for effects in answers:
		var arrows := {}
		var offsets: Dictionary = effects.get("bloc_offset", {})
		for bloc in offsets:
			arrows[bloc] = arrow(float(offsets[bloc]))
		strips.append({"arrows": arrows, "money": money_bn(ns, effects), "debt": float(effects.get("debt_eur_bn", 0.0))})
	for i in strips.size():
		for j in range(i + 1, strips.size()):
			if absf(float(strips[i]["money"]) - float(strips[j]["money"])) >= K.QUIET_MONEY_BN \
					or absf(float(strips[i]["debt"]) - float(strips[j]["debt"])) >= K.QUIET_MONEY_BN:
				return true
			for bloc in strips[i]["arrows"].keys() + strips[j]["arrows"].keys():
				if int(strips[i]["arrows"].get(bloc, 0)) != int(strips[j]["arrows"].get(bloc, 0)):
					return true
	return false


## A bloc offset's arrow on the effects strip: under OFFSET_SLIGHT none, then one,
## from OFFSET_CLEAR two, signed. tools/density_count.gd counts with this.
static func arrow(offset: float) -> int:
	var size := absf(offset)
	if size < OpinionK.OFFSET_SLIGHT:
		return 0
	var grade := 1 if size < OpinionK.OFFSET_CLEAR else 2
	return grade if offset > 0.0 else -grade


## A choice's first-order move on the public balance, EUR bn a year (positive is a
## better balance): spending and other revenue in points of GDP, a tax rate at the
## line's average yield per point today. A tax not levied today yields nothing here.
static func money_bn(ns, effects: Dictionary) -> float:
	var pct := float(effects.get("other_revenue_pct_gdp", 0.0))
	var spending: Dictionary = effects.get("spending_pct_gdp", {})
	for line in spending:
		pct -= float(spending[line])
	var taxes: Dictionary = effects.get("tax_rates_pct", {})
	for key in taxes:
		var rate := float(ns.tax_rates_pct.get(key, 0.0))
		if rate > 0.0:
			pct += float(taxes[key]) * float(ns.revenue_pct_gdp.get(key, 0.0)) / rate
	return pct * float(ns.gdp_eur_bn) / 100.0
