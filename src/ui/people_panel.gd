extends PanelContainer

## Who the president actually deals with -- U6b's surface, rebuilt at V4.3
## around the character layer (docs/people-model.md 14).
##
## Reads simulation state and content, and never writes either. **There is no
## button on this panel and that is a design decision, not an omission.** Every
## act involving a person already has a home: a state visit is on the Diplomacy
## panel, a reshuffle on Politics, a booking on the Diary. A panel with no
## interactive control also cannot repeat the fold nation_panel.gd has paid for
## twice (V1.3e, V1.3g) -- a second button narrows an autowrapping label, the wrap
## grows the row, and the panel walks off the bottom of the window.
##
## V4.3's register is 1595 people and a flat list would be a wall nobody
## scrolls, so the panel GROUPS BY KIND (the political cast, the bench by kind)
## and inside a group sorts by STANDING -- the register's own weight, so the
## people the player's decisions have moved sit at the top of their group
## without a single hand-written name in this file. Wants print as one line
## each with their DERIVED satisfaction read (never stored), which is the
## whole point of a want: what it wants, and whether the world is giving it.
##
## Where it stops: People says WHO and WHAT THEY WANT, Politics says what
## they do -- seats, effectiveness, standing, cohabitation. The single
## overlap is the cabinet holder column, and both surfaces read `ns.cabinet`
## so they cannot disagree. No competence, discipline or any other number
## appears beside a name here: all of them belong to the PARTY, and printing
## one next to a person would imply the person carries it. See
## docs/people-model.md.

signal closed

const CK = preload("res://src/sim/cabinet_constants.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")

const PORTFOLIO_LABEL := {
	"health": "Health", "education": "Education", "defence": "Defence",
	"pensions": "Pensions", "infrastructure": "Infrastructure",
}

## The face a row carries, at the row's own scale: 22px beside 14px captions
## reads as a face, and 30px of height is under two rows of separation.
const FACE_SIZE := Vector2(22, 30)

## How many of each group's list the panel prints before the group folds
## behind its count -- the bench is 47-49 per nation and a group that prints
## itself whole is the wall the grouping exists to prevent. The top of the
## group by STANDING prints first, so the visible head is the people the
## game has actually moved.
const GROUP_HEAD := 8

## The kind groups in reading order, with the labels a player reads. The
## order is the CAST's order: the political register first, then the bench
## from closest to power (politicians, regional figures) outward (press,
## unions, courts, activism).
const KIND_ORDER := [
	["politician", "The politicians"],
	["regional_figure", "Regional figures"],
	["press_owner", "Press owners"],
	["union_leader", "Union leaders"],
	["judge", "The bench"],
	["activist", "Activists"],
]

## How each want object reads, in the same voice everywhere the panel prints
## one (the hover card shares these strings through the label helpers below).
const STANCE_LABEL := {
	"sponsor": "sponsors", "oppose": "opposes", "want": "wants",
	"demand": "demands", "defend": "defends",
}

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	# 700 for the register-growth reason the file's old comment carried: this
	# panel has no verb, so the only affordance is the scrollbar, and a window
	# short for no reason is one the player resizes by hand every time. Well
	# inside U5a's ~886px band.
	custom_minimum_size = Vector2(460, 700)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var nation = _loader.nations.get(ns.id)
	if nation == null:
		return

	_title.text = "The people of %s" % nation.nation_name

	for child in _body.get_children():
		child.queue_free()

	_build_executive(ns)
	_build_cabinet(ns)
	_build_parties(ns)
	_build_character_groups(ns)
	_build_abroad(ns)


## The two offices the player deals with daily. Both are live state rather than
## content: an amendment can change the head of state, and a censure changes the
## head of government, so this reads NationState and not the nation file.
func _build_executive(ns) -> void:
	PanelKit.heading(_body, "The executive")
	_face_row(ns.head_of_state_person_id, ns.head_of_state_title, _name_of(ns.head_of_state_person_id))
	_face_row(ns.pm_person_id, ns.head_of_government_title, _name_of(ns.pm_person_id))


## Named ministers do not exist, and this is where that shows. U6b's own probe
## measured a five-deep shadow bench per party and found the player meets 6-13
## distinct people in fourteen years -- roughly a fifth of what the bench would
## cost to author -- so the bench was cut before it was written and a portfolio
## still names the PARTY that holds it. docs/people-model.md §3.
func _build_cabinet(ns) -> void:
	PanelKit.heading(_body, "The cabinet")
	var by_id := {}
	for p in _loader.parties.get(ns.id, []):
		by_id[p.id] = p
	for f in CK.PORTFOLIO_KEYS:
		var pid: String = String(ns.cabinet.get(f, ""))
		if pid == "" or not by_id.has(pid):
			PanelKit.row(_body, PORTFOLIO_LABEL.get(f, f), "VACANT", PanelKit.Tone.BAD)
		else:
			PanelKit.row(_body, PORTFOLIO_LABEL.get(f, f), String(by_id[pid].party_name))


func _build_parties(ns) -> void:
	PanelKit.heading(_body, "The parties")
	for p in _loader.parties.get(ns.id, []):
		var seats := int(ns.seats_by_party.get(p.id, 0))
		var leader: String = String(ns.party_leader_override.get(p.id, p.leader_person_id))
		_face_row(leader, String(p.party_name), "%s · %d seats" % [_name_of(leader), seats])


## V4.3's body: the character register, grouped by kind, sorted by standing,
## head of each group visible and the rest behind the count. The leader
## override the parties section reads is the same register this builds from,
## so a challenge moves both surfaces in the same month.
func _build_character_groups(ns) -> void:
	var people: Array = _loader.people.get(ns.id, [])
	var by_kind: Dictionary = {}
	for person in people:
		if not by_kind.has(person.kind):
			by_kind[person.kind] = []
		by_kind[person.kind].append(person)

	for entry in KIND_ORDER:
		var kind: String = entry[0]
		var label: String = entry[1]
		var group: Array = by_kind.get(kind, [])
		if group.is_empty():
			continue
		# Standing first: the group's visible head is the people whose weight
		# the game has moved, and a name's position is earned, not authored.
		group.sort_custom(func(a, b):
			return float(ns.person_standing.get(a.id, 0.0)) > float(ns.person_standing.get(b.id, 0.0)))
		PanelKit.heading(_body, "%s (%d)" % [label, group.size()])
		var shown := 0
		for person in group:
			if shown >= GROUP_HEAD:
				var rest: int = group.size() - GROUP_HEAD
				PanelKit.line(_body, "… and %d more" % rest, PanelKit.Tone.DIM)
				break
			_person_row(ns, person)
			shown += 1


## One person of the character layer: the face, the name, the party edge (or
## the kind's own line), the wants with their satisfaction reads. The wants
## are the person's whole point -- a row without them is a name in a list.
func _person_row(ns, person) -> void:
	var right := _party_or_kind_line(ns, person)
	var standing := float(ns.person_standing.get(person.id, 0.0))
	if standing >= 0.05:
		right += " · standing %.2f" % standing
	_face_row(person.id, person.person_name, right)
	for want in person.wants:
		_want_row(ns, person, want)


## The affiliation line: the party the person sits in (override first, the
## authored edge second), or the kind where there is no party -- a judge's
## row says "judge" and not an empty string.
func _party_or_kind_line(ns, person) -> String:
	var party_id: String = String(ns.person_party_override.get(person.id, person.party_id))
	if party_id != "":
		for p in _loader.parties.get(ns.id, []):
			if p.id == party_id:
				return String(p.party_name)
		return party_id
	return person.kind.replace("_", " ")


## One want with its DERIVED satisfaction read. The read is the same one
## characters.gd prices (the world as it stands this month), so the panel
## cannot disagree with the machine about whether a want is served.
func _want_row(ns, person, want: Dictionary) -> void:
	var object := String(want["object"])
	var stance := String(want["stance"])
	var text := "%s %s" % [STANCE_LABEL.get(stance, stance), _object_text(object, want)]
	var served := _want_satisfied(ns, person, want)
	var tone := PanelKit.Tone.DIM
	if stance == "oppose":
		served = not served
	var mark := "served" if served else "denied"
	if not served:
		tone = PanelKit.Tone.BAD
	PanelKit.line(_body, "    %s — %s" % [text, mark], tone)


## What an object string reads as, for the want lines and the hover card.
func _object_text(object: String, want: Dictionary) -> String:
	if object.begins_with("programme:"):
		var entry_id := object.substr("programme:".length())
		for entry in _loader.programme:
			if String(entry["id"]) == entry_id:
				return String(entry["name"])
		return entry_id
	if object == "office:premiership":
		return "the premiership"
	if object.begins_with("office:portfolio:"):
		var key := object.substr("office:portfolio:".length())
		return "%s" % PORTFOLIO_LABEL.get(key, key).to_lower()
	if object.begins_with("office:party_leadership:"):
		var pid := object.substr("office:party_leadership:".length())
		for p in _loader.parties.get(_state.player().id, []):
			if p.id == pid:
				return "the leadership of %s" % String(p.party_name)
		return "a party leadership"
	if object.begins_with("meter:"):
		var meter := object.substr("meter:".length())
		var direction := "below" if want.has("below") else "above"
		var threshold := float(want.get("below", want.get("above", 0.0)))
		return "%s %s %.1f" % [meter.replace("_", " "), direction, threshold]
	return object


## The satisfaction read, duplicated from characters.gd's private helper
## because the UI may not reach into src/sim/'s privates -- but it MUST agree
## with the machine, so the strings and the reads are kept identical and
## tests/test_people.gd pins that this file contains no hand-written person
## list to drift from the register.
func _want_satisfied(ns, person, want: Dictionary) -> bool:
	var object := String(want["object"])
	if object.begins_with("programme:"):
		var entry_id := object.substr("programme:".length())
		for entry in ns.programme:
			if String(entry.get("entry_id", entry.get("id", ""))) == entry_id:
				var status := String(entry.get("status", ""))
				return status == "complete" or status == "active"
		return false
	if object == "office:premiership":
		return String(ns.pm_person_id) == person.id
	if object.begins_with("office:portfolio:"):
		var key := object.substr("office:portfolio:".length())
		var party_id: String = String(ns.person_party_override.get(person.id, person.party_id))
		return String(ns.cabinet.get(key, "")) == party_id
	if object.begins_with("office:party_leadership:"):
		var pid := object.substr("office:party_leadership:".length())
		return String(ns.party_leader_override.get(pid, _authored_leader(pid))) == person.id
	return false


func _authored_leader(party_id: String) -> String:
	for p in _loader.parties.get(_state.player().id, []):
		if p.id == party_id:
			return String(p.leader_person_id)
	return ""


## Everyone the Diplomacy panel can point at. Their titles are live state too --
## another nation's head of state can change while the player is not looking,
## which is exactly the sort of thing a roster is for.
func _build_abroad(ns) -> void:
	PanelKit.heading(_body, "Abroad")
	var ids: Array = _state.nations.keys()
	ids.sort()
	for id in ids:
		if String(id) == ns.id:
			continue
		var nation = _loader.nations.get(id)
		if nation == null:
			continue
		_face_row(nation.leader_person_id, String(nation.nation_name), "%s %s" % [
			nation.leader_title, _name_of(nation.leader_person_id),
		])


## A PanelKit row with the person's face in front of it -- V2.3. The wall this
## panel became (two executives, every party leader, nine foreign heads of
## state) is exactly the "wall of generated images" docs/tiers/v2.md §3's
## duotone rule exists for, which is why this panel is where the faces landed
## and not every sentence that names a person: a face beside a name is identity
## content, a face beside every mention is wallpaper. Rows whose person has no
## art yet get the silhouette through the same call and the register grows
## without this panel noticing.
func _face_row(person_id: String, left: String, right: String) -> HBoxContainer:
	var row := PanelKit.row(_body, left, right)
	var face := Portrait.framed_for(person_id, FACE_SIZE)
	row.add_child(face)
	row.move_child(face, 0)
	return row


func _name_of(person_id: String) -> String:
	var who: String = _loader.person_name(person_id)
	return who if who != "" else "—"
