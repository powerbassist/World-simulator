extends RefCounted

## The workspace's domains and the tabs each one holds -- V5.1-c2.2, from the
## sixth artboard of c's layout board. Navigation, not content: which surface a
## player finds under which heading is the shell's call, so the table is code
## beside the shell, as `_build_action_bar()`'s clusters were. Nothing in it
## depends on the nation played.
##
## A domain with no registered tab is hidden (the author's call 1, 2026-10-21).
## Social and Defence are listed so the order is settled; they show the day V5.3
## and V6 register a tab under them.
##
## A window that is in no row is its own one-tab domain, titled by its window --
## the fallback that keeps a surface added without a row reachable rather than
## lost.

const ICONS := "res://assets/icons/material/"

## In sidebar order. `title` is an English msgid: the caller wraps it in tr().
const TABLE := [
	{"id": "agenda", "title": "Agenda", "icon": "event.svg", "tabs": ["agenda", "calendar"]},  # i18n: msgid title
	{"id": "presidency", "title": "Presidency", "icon": "account_balance.svg", "tabs": ["overview", "outliner", "events"]},  # i18n: msgid title
	{"id": "government", "title": "Government", "icon": "groups.svg", "tabs": ["politics", "people"]},  # i18n: msgid title
	{"id": "parliament", "title": "Parliament", "icon": "gavel.svg", "tabs": ["legislature"]},  # i18n: msgid title
	{"id": "finances", "title": "Finances", "icon": "payments.svg", "tabs": ["budget", "tax", "projects"]},  # i18n: msgid title
	{"id": "economy", "title": "Economy", "icon": "monitoring.svg", "tabs": ["economy", "commodities"]},  # i18n: msgid title
	{"id": "territory", "title": "Territory", "icon": "map.svg", "tabs": ["region", "city"]},  # i18n: msgid title
	{"id": "energy", "title": "Energy", "icon": "bolt.svg", "tabs": ["energy"]},  # i18n: msgid title
	{"id": "industry", "title": "Industry", "icon": "factory.svg", "tabs": ["companies"]},  # i18n: msgid title
	{"id": "diplomacy", "title": "Diplomacy", "icon": "public.svg", "tabs": ["diplomacy", "orgs"]},  # i18n: msgid title
	{"id": "opinion", "title": "Opinion", "icon": "campaign.svg", "tabs": ["society", "campaign"]},  # i18n: msgid title
	{"id": "social", "title": "Social", "icon": "diversity_3.svg", "tabs": []},  # i18n: msgid title
	{"id": "defence", "title": "Defence", "icon": "", "tabs": []},  # i18n: msgid title
	{"id": "glossary", "title": "Glossary", "icon": "menu_book.svg", "tabs": ["glossary"]},  # i18n: msgid title
]

## Windows that are scenes, not tabs: something that happens to the player and
## owns the screen while it does. The summit opens over the workspace, in no
## domain (board 5).
const SCENES := ["summit", "audience"]


static func is_scene(window_id: String) -> bool:
	return SCENES.has(window_id)


## The domain a tab belongs to, or "" for a window in no row.
static func domain_of(window_id: String) -> String:
	for row in TABLE:
		if (row["tabs"] as Array).has(window_id):
			return String(row["id"])
	return ""


## The domain's tabs that are registered, in the table's order.
static func tabs(domain_id: String, registered: Array) -> Array:
	var out: Array = []
	for row in TABLE:
		if String(row["id"]) == domain_id:
			for tab in row["tabs"]:
				if registered.has(tab):
					out.append(tab)
	return out


## The English msgid of a domain's title, or "" for an unknown id.
static func title(domain_id: String) -> String:
	for row in TABLE:
		if String(row["id"]) == domain_id:
			return String(row["title"])
	return ""


static func icon_path(domain_id: String) -> String:
	for row in TABLE:
		if String(row["id"]) == domain_id and not String(row["icon"]).is_empty():
			return ICONS + String(row["icon"])
	return ""


## The domains the sidebar shows: those with at least one registered tab, in
## the table's order.
static func visible(registered: Array) -> Array:
	var out: Array = []
	for row in TABLE:
		if not tabs(String(row["id"]), registered).is_empty():
			out.append(String(row["id"]))
	return out
