extends RefCounted

## The regional warning's arrival (V5.3 c' register slice 2, the parent's gate): the sim's
## note (UnitWarnings.tick, {kind "region_warning", type, region, figure, national}) ended a
## quiet month with nothing on screen. It lands as one inbox card -- RegionArrival's shape:
## it waits, never touches the clock -- and its Open puts the register on that region, the
## type's band_units placed, with the warning's answers (register_door.gd).
##
## What a card opens lives on main as a meta, not in a static: a load swaps in a fresh main
## (GameReload.swap), and the inbox's cards go with the old one.

const Units = preload("res://src/sim/units.gd")
const UnitWarnings = preload("res://src/sim/unit_warnings.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## What the Open acts on (acts_on.gd), before "type|region".
const SUBJECT := "register_warning|"
const CARDS := "register_warning_cards"


## The month's end: one card a warning note in the month's report.
static func arrive(main, report: Dictionary) -> void:
	var inbox = main._hud.inbox
	for note in report.get("units", []):
		if String(note.get("kind", "")) != UnitWarnings.KIND:
			continue
		var type_id := String(note["type"])
		var region := String(note["region"])
		if not main._loader.unit_types.has(type_id):
			continue
		if not main.has_meta(CARDS):
			main.set_meta(CARDS, {})
			inbox.card_action.connect(_on_open.bind(main))
		var row: Dictionary = Units.row(main._loader, type_id)
		var unit := Strings.row("units", type_id, "figure.unit", String((row.get("figure", {}) as Dictionary).get("unit", "")))
		var body := Strings.t("%s: %s %s; the nation %s.") % [
			_region_name(main, region), Num.f(float(note["figure"]), 2), unit, Num.f(float(note["national"]), 2)]
		var card: String = inbox.push(Strings.row_name("units", row), body,
			[{"label": Strings.t("Open"), "acts_on": SUBJECT + type_id + "|" + region}])
		(main.get_meta(CARDS) as Dictionary)[card] = {"type": type_id, "region": region, "month": int(main._state.month)}


static func _on_open(card: String, _index: int, main) -> void:
	var cards: Dictionary = main.get_meta(CARDS, {})
	if not cards.has(card):
		return
	var w: Dictionary = cards[card]
	var register = main._windows.content("register")
	if register == null:
		return
	register.open_from_warning(String(w["type"]), String(w["region"]), int(w["month"]))
	main._windows.open("register")
	cards.erase(card)
	main._hud.inbox.dismiss(card)


static func _region_name(main, id: String) -> String:
	for r in main._loader.regions.get(main._state.player().id, []):
		if String(r.id) == id:
			return String(r.region_name)
	return id
