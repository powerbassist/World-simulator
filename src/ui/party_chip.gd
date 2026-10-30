extends RefCounted

## A person's party, said and shown -- V5.2 close R3 (the author at the gate: "we
## dont know what party are the people we meet"). The party's NAME is the reading;
## the swatch only repeats it, so nothing is told by colour alone.
##
## The colour is the hemicycle's (panel_charts.gd): a party's slot is its order in
## the nation's data, so the chip on a request card and the party's arc in the
## Assembly chart never disagree. One rule, here; the chart calls it.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const Strings = preload("res://src/ui/strings.gd")
const Characters = preload("res://src/sim/characters.gd")


## The colour of the `index`-th party in its nation's data order.
static func colour_at(index: int) -> Color:
	return ChartStyle.SERIES[mini(index, ChartStyle.SERIES.size() - 1)]


## {name, colour} of `person_id`'s party in `ns`, or {} for a person with no party
## (or one the content no longer carries) -- a word, then, never a swatch.
##
## The party as the registers stand: a defection's override, else the authored
## edge (Person.party_id), else the party they LEAD (Characters.party_leader, the
## challenge's override included). A party's leader carries no party_id of their
## own in the data -- the party names them -- so without the last step every
## leader asking for an audience read "No party" (the first after-frame here).
static func of(loader, ns, person_id: String) -> Dictionary:
	var person = loader.person_by_id.get(person_id)
	if person == null:
		return {}
	# An override is the register's word even when it is "" (left to sit alone):
	# the sim's own reading (Characters._party_of), so leadership is not asked then.
	var overridden: bool = ns.person_party_override.has(person_id)
	var party_id := String(ns.person_party_override[person_id]) if overridden else String(person.party_id)
	var parties: Array = loader.parties.get(String(ns.id), [])
	if party_id == "" and not overridden:
		var authored := {}
		for party in parties:
			authored[String(party.id)] = String(party.leader_person_id)
		for party in parties:
			if Characters.party_leader(ns, String(party.id), authored) == person_id:
				party_id = String(party.id)
	for i in parties.size():
		if String(parties[i].id) == party_id:
			return {"name": String(parties[i].party_name), "colour": colour_at(i)}
	return {}


## The chip: a swatch and the party's name, or "No party" alone. Caption size, so it
## sits under a name or a heading without competing with it.
static func make(party: Dictionary) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.name = "PartyChip"  # i18n: ok a node name, found by tests
	chip.add_theme_constant_override("separation", 6)
	if not party.is_empty():
		var swatch := ColorRect.new()
		swatch.name = "Swatch"  # i18n: ok a node name, found by tests
		swatch.color = party["colour"]
		swatch.custom_minimum_size = Vector2(ChartStyle.SWATCH, ChartStyle.SWATCH)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(swatch)
	var label := Label.new()
	label.name = "Party"  # i18n: ok a node name, found by tests
	label.theme_type_variation = UiTheme.CAPTION
	label.text = String(party["name"]) if not party.is_empty() else Strings.t("No party")  # i18n: row-ok a party's proper name, from the data
	chip.add_child(label)
	return chip
