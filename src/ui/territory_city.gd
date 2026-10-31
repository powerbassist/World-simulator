extends RefCounted

## One city, the map's answer -- what V2.2b's City panel showed for a clicked
## cross, for ANY nation (the register is public data, and a cross that answered no
## click would be drawn content the game cannot reach). V5.3-0 (b) folded the City
## tab into Territory: its ranked list is gone (a region's largest cities open from
## its row), and this detail is drawn inside the Territory tab, with a way back.
##
## A city's population is its share read through its region and the nation --
## never authored, city.gd's four-field rule -- so the figures multiply the same
## two shares by the LIVE national population and stay true as demography moves.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Companies = preload("res://src/sim/companies.gd")
const Region = preload("res://src/core/region.gd")
const Migration = preload("res://src/sim/migration.gd")
const Num = preload("res://src/ui/num.gd")


## {region, city, nation_id}, or {} when the register does not hold the id. The
## register is 112 regions of at most 21 cities, so region.gd's own linear scans
## are the whole index -- the player's nation alone would not reach a foreign city
## the map just clicked.
static func find(loader, city_id: String) -> Dictionary:
	for nation_id in loader.regions.keys():
		var city = Region.find_city(loader.regions[nation_id], city_id)
		if city != null:
			return {
				"region": Region.region_of_city(loader.regions[nation_id], city_id),
				"city": city,
				"nation_id": nation_id,
			}
	return {}


## The detail under `body`; returns the title the panel shows, "" when the city's
## nation is not in play.
static func build(body: Control, state, loader, found: Dictionary) -> String:
	var region = found["region"]
	var city = found["city"]
	var nation_id: String = found["nation_id"]
	var ns = state.nations.get(nation_id)
	var nation = loader.nations.get(nation_id)
	if ns == null or nation == null:
		return ""
	var pop: float = Migration.city_population(ns, region.id, city.id)
	PanelKit.row(body, Strings.t("Region"), "%s · %s" % [region.region_name, nation.nation_name])
	PanelKit.row(body, Strings.t("Population"), PanelKit.pop_text(pop))
	PanelKit.row(body, Strings.t("Share of its region"), "%s%%" % Num.f((Migration.city_share(ns, city.id) * 100.0), 1))

	PanelKit.heading(body, Strings.t("Named employers"))
	# A3. Majors keep a row apiece; the body tier -- which since A3 domiciles most
	# of a big city's firms -- is one aggregate line, the companies panel's own
	# shape. V4.7b: the filter reads the LIVE city, the same register fact every
	# headcount here reads -- the authored-city filter listed a relocated firm
	# under its old city while its payroll counted in the new one.
	var rows: Array = []
	var body_count := 0
	var body_jobs := 0.0
	for company in loader.companies.get(nation_id, []):
		if Companies.live_city_of(ns, company) != city.id:
			continue
		if Companies.is_major(company):
			rows.append([String(company.company_name), PanelKit.pop_text(Companies.headcount(ns, company))])
		else:
			body_count += 1
			body_jobs += Companies.headcount(ns, company)
	if rows.is_empty() and body_count == 0:
		PanelKit.line(body, Strings.t("No named employer is domiciled here."))
	else:
		if not rows.is_empty():
			PanelKit.ledger(body, rows)
		if body_count > 0:
			PanelKit.line(body, Strings.t("BODY · %d firms · %s jobs") % [body_count, PanelKit.pop_text(body_jobs)])
	return String(city.city_name)
