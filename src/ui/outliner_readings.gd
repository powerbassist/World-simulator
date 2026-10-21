extends RefCounted

const CommoditiesPanel = preload("res://src/ui/commodities_panel.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Strings = preload("res://src/ui/strings.gd")
const Industry = preload("res://src/sim/industry.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")

## V4.8b. The outliner of pinned things as a REGISTER, the shape strip_readings.gd
## gave the strip: SECTIONS is the list, CAPTIONS its words, INPUTS the NationState
## fields each section reads, and read(section, state, loader) answers one. The
## outliner window draws whatever this returns and knows no section by name; a new
## pinned thing is an entry here, never a branch in the panel.
##
## "Pinned" is whatever the machine already marks as waiting on the player or
## drifting against them -- nothing here is chosen by the player, so there is no
## new save field and no sim-side verb (the author's V4.8b call, 2026-10-17):
##   agenda  the programme entries the content pins (`pinned` in data/programme/);
##   firms   a failing major inside its rescue window, a standing foreign bid --
##           the two states pending.gd already puts a mark on;
##   goods   every good under the commodities window's own shortage line;
##   people  those who hold a grudge against the term or have turned against it.
##
## An empty section is hidden, not a row of zeros: the em-dash rule from panel_kit
## applied to a list. Static and read-only over GameState.

const SECTIONS: Array[String] = ["agenda", "firms", "goods", "people"]

const CAPTIONS := {
	"agenda": "Agenda", "firms": "Firms in trouble",  # i18n: msgid
	"goods": "Supplies short", "people": "People you watch",  # i18n: msgid
}

## The NationState fields each section reads, perturbed by tests/test_outliner.gd.
const INPUTS := {
	"agenda": ["programme"],
	"firms": ["companies"],
	"goods": ["commodity_state"],
	"people": ["person_grudges", "person_loyalty"],
}

## A grudge or loyalty under this has not been moved by the term (V4.3's figure;
## it lived on the strip as "People" until V4.8b moved the reading here).
const MOVED_AT := 0.05

## Rows a section shows before it says "+N more": the window is a margin note, and
## the window each row opens holds the full list.
const ROW_CAP := 6


static func read(section: String, state, loader) -> Dictionary:
	var ns = state.player()
	var rows: Array = []
	var title: String = Strings.t(String(CAPTIONS.get(section, section)))
	match section:
		"agenda":
			rows = _agenda(ns, loader)
		"firms":
			rows = _firms(state, ns, loader)
		"goods":
			rows = _goods(ns, loader)
		"people":
			rows = _people(ns, loader)
			title = Strings.t("%s · %d moved") % [title, moved_count(ns)]
	return {"title": title, "rows": _capped(rows), "visible": not rows.is_empty()}


## How many people the term has MOVED (a non-zero grudge or loyalty), not how many
## exist -- the register is 1595 and a permanent "1595" says nothing.
static func moved_count(ns) -> int:
	var moved := 0
	for pid in ns.person_grudges.keys():
		if float(ns.person_grudges[pid]) >= MOVED_AT:
			moved += 1
	for pid in ns.person_loyalty.keys():
		if absf(float(ns.person_loyalty[pid])) >= MOVED_AT and float(ns.person_grudges.get(pid, 0.0)) < MOVED_AT:
			moved += 1
	return moved


static func _row(text: String, tone: int, window: String) -> Dictionary:
	return {"text": text, "tone": tone, "window": window}


static func _capped(rows: Array) -> Array:
	if rows.size() <= ROW_CAP:
		return rows
	var out: Array = rows.slice(0, ROW_CAP)
	out.append(_row(Strings.t("+%d more") % (rows.size() - ROW_CAP), PanelKit.Tone.DIM, String(rows[0]["window"])))
	return out


static func _agenda(ns, loader) -> Array:
	var rows: Array = []
	if loader == null:
		return rows
	for live in ns.programme:
		if String(live["status"]) != ProgrammeK.STATUS_ACTIVE:
			continue
		var terms: Dictionary = Programme.terms_of(loader, String(live["entry_id"]))
		if terms.is_empty() or not bool(terms.get("pinned", false)):
			continue
		var progress: Dictionary = Programme.progress_of(ns, terms)
		var fraction := PanelKit.progress_fraction(
			float(progress["current_value"]), float(progress["goal_value"]), String(progress["progressbar"]))
		var text := "%s — %.0f%%" % [String(terms.get("name", String(live["entry_id"]))), fraction * 100.0]
		var clock := StripReadings.programme_clock_text(terms, live)
		if not clock.is_empty():
			text += " · %s" % clock
		rows.append(_row(text, PanelKit.Tone.PLAIN, "agenda"))
	return rows


static func _firms(state, ns, loader) -> Array:
	var rows: Array = []
	if loader == null:
		return rows
	var bid: Dictionary = Industry.pending_bid(state, ns, loader)
	if not bid.is_empty():
		rows.append(_row(Strings.t("%s bids %.1f bn for %s — %d months left") % [
			loader.nation_name(String(bid["bidder_nation"])), float(bid["price_eur_bn"]),
			loader.firm_name(ns.id, String(bid["company_id"])), int(bid["months_left"])],
			PanelKit.Tone.BAD, "companies"))
	for failure in Industry.failing(state, ns, loader):
		rows.append(_row(Strings.t("%s failing — rescue window, %d months left") % [
			loader.firm_name(ns.id, String(failure["company_id"])), int(failure["months_left"])],
			PanelKit.Tone.BAD, "companies"))
	return rows


## Worst first, ties by id -- the strip's Supplies figure and the commodities
## window's SHORTAGES section order, so the three cannot disagree about "worst".
static func _goods(ns, loader) -> Array:
	var rows: Array = []
	if loader == null or ns.commodity_state.is_empty():
		return rows
	for item in CommoditiesPanel.shortages(ns, loader.commodity_goods.keys()):
		var good = loader.commodity_goods.get(item["id"])
		rows.append(_row(Strings.t("%s — %.0f%% of demand") % [
			String(good.name) if good != null else String(item["id"]), float(item["coverage"]) * 100.0],
			PanelKit.Tone.BAD, "commodities"))
	return rows


## Worried about: a grudge the term has earned, or a loyalty that has turned
## against it. A person who merely likes the government is moved (moved_count) but
## not a worry, so is not a row. Largest grudge first, ties by id.
static func _people(ns, loader) -> Array:
	var rows: Array = []
	if loader == null:
		return rows
	var worried: Array = []
	for pid in ns.person_grudges.keys():
		var grudge := float(ns.person_grudges[pid])
		if grudge >= MOVED_AT:
			worried.append({"id": String(pid), "weight": grudge, "text": Strings.t("grudge %.2f") % grudge})
	for pid in ns.person_loyalty.keys():
		var loyalty := float(ns.person_loyalty[pid])
		if loyalty <= -MOVED_AT and float(ns.person_grudges.get(pid, 0.0)) < MOVED_AT:
			worried.append({"id": String(pid), "weight": -loyalty, "text": Strings.t("loyalty %.2f") % loyalty})
	worried.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(float(a["weight"]), float(b["weight"])):
			return float(a["weight"]) > float(b["weight"])
		return String(a["id"]) < String(b["id"]))
	for item in worried:
		var who: String = loader.person_name(String(item["id"]))
		rows.append(_row("%s — %s" % [who if who != "" else "—", item["text"]], PanelKit.Tone.BAD, "people"))
	return rows
