extends RefCounted

## The register's arrivals in the inbox (V5.3 c' register slice 2, the parent's gate; pass 2 on
## #428): what UnitBuild.tick_month notes and no other surface says.
##   region_warning     a card: the region's figure against the nation's; its Open puts the
##                      register on that region, the type's band_units placed (register_door.gd);
##   overrun_landed     a card: what the builders ask and by when; its Open shows the Building tab;
##   overrun_defaulted  a note: no answer by its date, so the overrun was paid;
##   lapse_warning      a note: the Union's money that lapses unless voted in time.
## RegionArrival's shape: a card waits and never touches the clock; out of government none comes;
## one live card a subject (a second arrival beside an unanswered one is dropped); a card's Open
## that cannot show its tab (a scene holds the screen) keeps the card.
##
## What a card opens lives on main as a meta, not in a static: a load swaps in a fresh main
## (GameReload.swap). The inbox is not saved, so restore_after_load() raises again what still
## waits: a warning stamped within the rearm months whose region is still in the band and not
## building, and every overrun ask (UnitOverrun.asks). The sim's stamp says when a warning came,
## not whether it was answered, so a warning left alone comes back after a load.

const Units = preload("res://src/sim/units.gd")
const UK = preload("res://src/sim/units_constants.gd")
const UnitWarnings = preload("res://src/sim/unit_warnings.gd")
const UnitOverrun = preload("res://src/sim/unit_overrun.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")

## What the Open acts on (acts_on.gd), before "type|region" or the programme's id.
const SUBJECT := "register_warning|"
const OVERRUN := "register_overrun|"
const CARDS := "register_warning_cards"


## The month's end: the month's units notes.
static func arrive(main, report: Dictionary) -> void:
	if not _ours(main):
		return
	var ns = main._state.player()
	_settle(main, ns)
	for note in report.get("units", []):
		match String(note.get("kind", "")):
			UnitWarnings.KIND:
				_warn(main, String(note["type"]), String(note["region"]), float(note["figure"]), float(note["national"]), int(main._state.month))
			"overrun_landed":
				_ask(main, String(note["id"]))
			"overrun_defaulted":
				main._hud.inbox.push(Strings.t("Overrun paid"), Strings.t("%s: no answer by its date, so the builders' %s bn were paid.") % [
					_programme_name(main, _programme(ns, String(note["id"]))), Num.f(float(note["eur_m"]) / 1000.0, 2)])
			"lapse_warning":
				main._hud.inbox.push(Strings.t("Union money lapsing"), Strings.t("%s bn of the Union's envelope is lost unless voted by the end of %d.") % [
					Num.f(float(note["eur_m"]) / 1000.0, 2), int(note["year"])])


## A main built from a save: what still waits, raised again (the inbox is not saved).
static func restore_after_load(main) -> void:
	if not _ours(main):
		return
	var ns = main._state.player()
	var now := UnitPrice.now(main._state)
	var keys: Array = ns.unit_warned.keys()
	keys.sort()
	for key in keys:
		var parts := String(key).split("|")
		var type_id := parts[0]
		var region := parts[1] if parts.size() > 1 else ""
		if not main._loader.unit_types.has(type_id) or now - int(ns.unit_warned[key].get("month", 0)) >= UK.UNIT_WARN_REARM_MONTHS:
			continue
		if not Units.band(ns, main._loader, type_id).has(region) or _building(ns, type_id, region) or _tabled(ns, type_id, region):
			continue
		var month := int(ns.unit_warned[key].get("month", now))
		_warn(main, type_id, region, Units.shown_figure(ns, main._loader, type_id, region), Units.national_figure(ns, main._loader, type_id),
			(month - 1) % 12 + 1)
	for copy in UnitOverrun.asks(main._state, ns, main._loader):
		_ask(main, String(copy["id"]))


## An overrun card whose ask was answered on the Building tab goes (its Open would show nothing).
static func _settle(main, ns) -> void:
	var cards: Dictionary = main.get_meta(CARDS, {})
	for card in cards.keys():
		if String(cards[card]["kind"]) == "overrun":
			var p := _programme(ns, String(cards[card]["id"]))
			if p.is_empty() or p.has("answer"):
				main._hud.inbox.dismiss(String(card))
				cards.erase(card)


static func _ours(main) -> bool:
	var ns = main._state.player() if main._state != null else null
	# Out of government the register's verbs are not the player's to take (RegionArrival's rule).
	return ns != null and bool(ns.in_government)


static func _warn(main, type_id: String, region: String, figure: float, national: float, month: int) -> void:
	if not main._loader.unit_types.has(type_id):
		return
	var row: Dictionary = Units.row(main._loader, type_id)
	var unit := Strings.row("units", type_id, "figure.unit", String((row.get("figure", {}) as Dictionary).get("unit", "")))
	_push(main, SUBJECT + type_id + "|" + region, Strings.row_name("units", row), Strings.t("%s: %s %s; the nation %s.") % [
		_region_name(main, region), Num.f(figure, 2), unit, Num.f(national, 2)],
		{"kind": "warning", "type": type_id, "region": region, "month": month})


static func _ask(main, programme_id: String) -> void:
	var p := _programme(main._state.player(), programme_id)
	if p.is_empty() or not p.has("ask"):
		return
	var due := int(p["ask"]["due"])
	_push(main, OVERRUN + programme_id, Strings.t("Overrun ask"), Strings.t("%s: the builders need %s bn more. Answer by %s, or it is paid.") % [
		_programme_name(main, p), Num.f(float(p["ask"]["eur_m"]) / 1000.0, 2), DateText.month_year((due - 1) % 12 + 1, (due - 1) / 12)],
		{"kind": "overrun", "id": programme_id})


## One live card a subject: closed cards leave the map, a second one beside a live one is dropped.
static func _push(main, subject: String, title: String, body: String, opens: Dictionary) -> void:
	var inbox = main._hud.inbox
	if not main.has_meta(CARDS):
		main.set_meta(CARDS, {})
		inbox.card_action.connect(_on_open.bind(main))
	var cards: Dictionary = main.get_meta(CARDS)
	for card in cards.keys():
		if inbox.lane_of(String(card)) == "":
			cards.erase(card)
		elif String(cards[card]["subject"]) == subject:
			return
	var open := [{"label": Strings.t("Open"), "acts_on": subject}]
	var card: String = inbox.push(title, body, open)
	opens["subject"] = subject
	cards[card] = opens


static func _on_open(card: String, _index: int, main) -> void:
	var cards: Dictionary = main.get_meta(CARDS, {})
	if not cards.has(card):
		return
	var w: Dictionary = cards[card]
	var tab := "register" if String(w["kind"]) == "warning" else "programmes"
	var panel = main._windows.content(tab)
	if panel == null:
		return
	if String(w["kind"]) == "warning":
		panel.open_from_warning(String(w["type"]), String(w["region"]), int(w["month"]))
	main._windows.open(tab)
	# Refused (a scene holds the screen): the card stays for later, as RegionArrival's does.
	if not main._windows.is_open(tab):
		return
	cards.erase(card)
	main._hud.inbox.dismiss(card)


static func _programme(ns, programme_id: String) -> Dictionary:
	for p in ns.unit_programmes:
		if String(p["id"]) == programme_id:
			return p
	return {}


static func _building(ns, type_id: String, region: String) -> bool:
	for p in ns.unit_programmes:
		if String(p.get("type", "")) == type_id and String(p.get("state", "")) == UK.STATE_BUILDING:
			for r in p.get("rows", []):
				if String(r.get("region", "")) == region:
					return true
	return false


static func _tabled(ns, type_id: String, region: String) -> bool:
	for p in (ns.tabled_bill.get("finance", {}) as Dictionary).get("units", []):
		if String(p.get("type", "")) == type_id:
			for r in p.get("rows", []):
				if String(r.get("region", "")) == region:
					return true
	return false


static func _programme_name(main, p: Dictionary) -> String:
	if p.is_empty():
		return ""
	var names: Array = []
	for r in p.get("rows", []):
		names.append(_region_name(main, String(r.get("region", ""))))
	return "%s, %s" % [Strings.row_name("units", Units.row(main._loader, String(p["type"]))), ", ".join(names)]  # i18n: row-ok a name and its regions


static func _region_name(main, id: String) -> String:
	for r in main._loader.regions.get(main._state.player().id, []):
		if String(r.id) == id:
			return String(r.region_name)
	return id
