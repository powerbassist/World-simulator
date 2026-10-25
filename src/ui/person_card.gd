extends PanelContainer

## The shared hover card for any person the UI names -- V4.3's one-card
## surface, built once and shown by whoever names a person (the People
## panel's rows wire it today; a later surface adopts it with one show_for
## call rather than a readout of its own). The card reads the loader and the
## person-state registers and never writes either.
##
## SHARED BY CONSTRUCTION, not by convention: the register is 1595 people and
## every surface that hand-rolls its own person readout is a second copy of
## the same facts waiting to disagree -- the two-readouts-of-one-record
## failure this column keeps catching. The card is the ONLY reader of a
## person's traits and wants outside the People panel, and both read the
## same content so they cannot diverge.
##
## NO PORTRAIT HERE, deliberately: the card's parent surface supplies the
## face at its own scale (Portrait.framed_for). A card that drew its own
## would double every face on the People panel -- a face beside a name is
## identity, a face beside a face is wallpaper.

const Labels = preload("res://src/ui/labels.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Relations = preload("res://src/core/relations.gd")
const President = preload("res://src/sim/president.gd")

const KIND_LABEL := {
	"politician": "Politician", "regional_figure": "Regional figure",  # i18n: msgid
	"union_leader": "Union leader", "press_owner": "Press owner",  # i18n: msgid
	"judge": "Judge", "activist": "Activist", "executive": "Executive",  # i18n: msgid
}

const TRAIT_LABEL := {
	"ambitious": "Ambitious", "loyal": "Loyal", "principled": "Principled",  # i18n: msgid
	"pragmatic": "Pragmatic", "vain": "Vain", "stubborn": "Stubborn",  # i18n: msgid
	"networked": "Networked", "fervent": "Fervent",  # i18n: msgid
}

## The want voice, SHARED with the People panel (the panel calls these, not
## its own copies): one table, one object reader, so a want cannot read one
## way on the panel and another on the card -- the two-readouts-of-one-record
## failure this file's header refuses. The standard review's 80-scoring find
## was exactly that split (the card printed raw "oppose programme:..." where
## the panel printed "opposes The Full Term").
const STANCE_LABEL := {
	"sponsor": "sponsors", "oppose": "opposes", "want": "wants",
	"demand": "demands", "defend": "defends",
}

const PORTFOLIO_LABEL := Labels.PORTFOLIO


static func stance_label(stance: String) -> String:
	return String(STANCE_LABEL.get(stance, stance))


## What a want's object string reads as, in the panel's own voice. `ns` is in
## hand for the player's nation id (the party lookup); loader supplies the
## programme register and the parties.
static func object_text(loader, ns, object: String, want: Dictionary) -> String:
	if object.begins_with("programme:"):
		var entry_id := object.substr("programme:".length())
		for entry in loader.programme:
			if String(entry["id"]) == entry_id:
				return Strings.row_name("programme", entry)
		return entry_id
	if object == "office:premiership":
		return Strings.t("the premiership")
	if object.begins_with("office:portfolio:"):
		var key := object.substr("office:portfolio:".length())
		return "%s" % Strings.t(String(PORTFOLIO_LABEL.get(key, key))).to_lower()
	if object.begins_with("office:party_leadership:"):
		var pid := object.substr("office:party_leadership:".length())
		for p in loader.parties.get(ns.id, []):
			if p.id == pid:
				return Strings.t("the leadership of %s") % String(p.party_name)
		return Strings.t("a party leadership")
	# V5.2b b3: a visiting head's ask, "measure:<FRA>DEU>" -- the played nation's
	# measure on their nation, lifted ("wants your measure on Germany lifted").
	if object.begins_with("measure:"):
		var parts := Relations.directed_parts(object.substr("measure:".length()))
		var on = loader.nations.get(String(parts[1])) if parts.size() == 2 else null
		return Strings.t("your measure on %s lifted") % (String(on.nation_name) if on != null else Strings.t("their nation"))  # i18n: row-ok a nation's shown name
	if object.begins_with("meter:"):
		var meter := object.substr("meter:".length())
		var threshold := float(want.get("below", want.get("above", 0.0)))
		return (Strings.t("%s below %s") if want.has("below") else Strings.t("%s above %s")) % [meter.replace("_", " "), Num.f(threshold, 1)]
	return object

var _body: VBoxContainer
var _shows := 0


func _ready() -> void:
	# Small and unstyled to read as a tooltip: the card is an annotation, not
	# a window, and giving it window furniture would make it compete with the
	# surface it annotates.
	custom_minimum_size = Vector2(260, 0)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	margin.add_child(_body)


## Fill and show for one person. `position` is the parent surface's cursor
## position in ITS coordinate space -- the card is reparented by whoever
## shows it, so it never computes a screen position itself.
func show_for(person_id: String, loader, ns, position: Vector2) -> void:
	var person = loader.person_by_id.get(person_id, null)
	if person == null:
		visible = false
		return

	# remove_child first: a queue_free'd row stays a child, and so in the minimum
	# size, until the frame ends -- the card kept 2-2.6x its content's height from
	# the second show on.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	var title := Label.new()
	title.theme_type_variation = UiTheme.LEAD
	title.text = person.person_name
	_body.add_child(title)

	PanelKit.line(_body, tr(KIND_LABEL.get(person.kind, person.kind)), PanelKit.Tone.DIM)

	var party_id: String = String(ns.person_party_override.get(person.id, person.party_id))
	if party_id != "":
		for p in loader.parties.get(ns.id, []):
			if p.id == party_id:
				PanelKit.line(_body, String(p.party_name), PanelKit.Tone.DIM)
				break

	if not person.traits.is_empty():
		var traits: Array[String] = []
		for t in person.traits:
			traits.append(tr(String(TRAIT_LABEL.get(t, t))))
		PanelKit.line(_body, ", ".join(traits), PanelKit.Tone.DIM)

	# The live state, one line each: what the player's term has done to them.
	var grudge := float(ns.person_grudges.get(person.id, 0.0))
	var loyalty := float(ns.person_loyalty.get(person.id, 0.0))
	var standing := float(ns.person_standing.get(person.id, 0.0))
	# Rapport too (QA's pre-gate B RECORD 5): the register a decline, a lapse and
	# a call write, priced on the request card and shown nowhere after it.
	var rapport := President.rapport(ns, String(person.id))
	if grudge >= 0.05 or loyalty != 0.0 or standing >= 0.05 or rapport != 0.0:
		PanelKit.row(_body, tr("Standing"), Num.f(standing, 2))
		PanelKit.row(_body, tr("Loyalty"), Num.fs(loyalty, 2))
		PanelKit.row(_body, tr("Grudge"), Num.f(grudge, 2))
		PanelKit.row(_body, tr("Rapport with you"), Num.fs(rapport, 2))

	if not person.wants.is_empty():
		PanelKit.line(_body, tr("Wants"), PanelKit.Tone.DIM)
		for want in person.wants:
			PanelKit.line(_body, "  %s %s" % [
				stance_label(String(want["stance"])),
				object_text(loader, ns, String(want["object"]), want)])

	visible = true
	# In the frame of the show the rows are measured before their width is known, so
	# the minimum (and the panel, which grows to it and never shrinks) comes out ~1.7x
	# the content. A frame later the minimum is right; reset_size takes the panel to it.
	_shows += 1
	if is_inside_tree():
		_settle(_shows)


## Two frames, not one: the first still reads the inflated minimum.
func _settle(show_no: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if visible and show_no == _shows:
		reset_size()


func hide_card() -> void:
	visible = false
