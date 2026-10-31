extends RefCounted

## Where the player's decisions land -- V5.3-0 (b), the author's call 6 ("Un onglet
## + où tombent tes décisions"): every site the player put on the map, by region,
## each with the tab whose verbs act on it. Read off the registers that already
## hold a region: a plant's `region_id` (energy.gd), a campaign effort's site
## (`campaign_sites`), and a public work's site, which is content read through
## Projects.site_region. Nothing here is stored: the map and these rows read one
## truth.

const Strings = preload("res://src/ui/strings.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const EnergyPanel = preload("res://src/ui/energy_panel.gd")


## region id -> [{label, tab}], in the order public works, plants, campaign.
static func by_region(ns, loader) -> Dictionary:
	var out := {}
	for pid in Projects.building(ns) + Projects.completed(ns):
		var region := Projects.site_region(loader, ns.id, String(pid))
		if region != "":
			var name := Strings.noun("project-actions", loader.project_actions, "project", "project_id", String(pid), "project_name", Projects.name_of(loader, String(pid)))
			_add(out, region, name, "projects")
	for plant_id in ns.plants.keys():
		var region := String((ns.plants[plant_id] as Dictionary).get("region_id", ""))
		if region != "":
			_add(out, region, EnergyPanel.plant_label(ns, String(plant_id), loader), "energy")
	for effort_id in ns.campaign_sites.keys():
		var region := String(ns.campaign_sites[effort_id])
		if region != "":
			var name := Strings.noun("campaign-actions", loader.campaign_actions, "campaign", "effort_id", String(effort_id), "effort_name", Campaign.name_of(loader, String(effort_id)))
			_add(out, region, name, "campaign")
	return out


static func _add(out: Dictionary, region: String, label: String, tab: String) -> void:
	if not out.has(region):
		out[region] = []
	(out[region] as Array).append({"label": label, "tab": tab})
