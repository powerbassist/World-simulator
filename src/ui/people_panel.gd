extends PanelContainer

## Who the president actually deals with -- U6b's one new surface.
##
## Reads simulation state and content, and never writes either. **There is no
## button on this panel and that is a design decision, not an omission.** Every
## act involving a person already has a home: a state visit is on the Diplomacy
## panel, a reshuffle on Politics, a booking on the Diary. A panel with no
## interactive control also cannot repeat the fold nation_panel.gd has paid for
## twice (V1.3e, V1.3g) -- a second button narrows an autowrapping label, the wrap
## grows the row, and the panel walks off the bottom of the window.
##
## The body scrolls from the first line rather than after it first overflows,
## because this panel grows with the REGISTER: docs/tiers/v1.md §4 and §5 inherit
## data/people/ and will add to it, and a surface that folds the moment its
## content grows is a surface that was sized to today's content.
##
## Where it stops: People says WHO, Politics says what they do -- seats,
## effectiveness, standing, cohabitation. The single overlap is the cabinet
## holder column, and both surfaces read `ns.cabinet` so they cannot disagree.
## No competence, discipline or any other number appears beside a name here: all
## of them belong to the PARTY, and printing one next to a person would imply the
## person carries it. See docs/people-model.md.

signal closed

const CK = preload("res://src/sim/cabinet_constants.gd")
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

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	# 700 rather than 520, and the screenshot pass is why: a new game's register runs
	# to the executive, five cabinet portfolios, six parties and ten foreign leaders,
	# and at 520 the window opened with the Abroad list cut through the middle of a
	# row while three hundred pixels of the usable band sat empty underneath it. This
	# panel has no verb, so the fold mark cannot say so on its behalf -- the only
	# affordance is the scrollbar, and a window that is short for no reason is a
	# window the player has to fix by hand every time they open it. 700 is calendar's
	# figure and well inside U5a's ~886px band.
	#
	# Height is the RIGHT answer here and the wrong one for a fold: a fold is a verb
	# below the line, which V1.3g proved height does not fix. This is a readout that
	# was simply smaller than the band it is allowed to occupy. The general version --
	# a window growing to the band whenever its content wants more -- stays deleted;
	# see docs/panel-system.md section 7.
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
		_face_row(p.leader_person_id, String(p.party_name), "%s · %d seats" % [_name_of(p.leader_person_id), seats])


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
