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

const CharacterK = preload("res://src/sim/character_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

const KIND_LABEL := {
	"politician": "Politician", "regional_figure": "Regional figure",
	"union_leader": "Union leader", "press_owner": "Press owner",
	"judge": "Judge", "activist": "Activist",
}

const TRAIT_LABEL := {
	"ambitious": "Ambitious", "loyal": "Loyal", "principled": "Principled",
	"pragmatic": "Pragmatic", "vain": "Vain", "stubborn": "Stubborn",
	"networked": "Networked", "fervent": "Fervent",
}

var _body: VBoxContainer


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

	for child in _body.get_children():
		child.queue_free()

	var title := Label.new()
	title.theme_type_variation = UiTheme.LEAD
	title.text = person.person_name
	_body.add_child(title)

	PanelKit.line(_body, KIND_LABEL.get(person.kind, person.kind), PanelKit.Tone.DIM)

	var party_id: String = String(ns.person_party_override.get(person.id, person.party_id))
	if party_id != "":
		for p in loader.parties.get(ns.id, []):
			if p.id == party_id:
				PanelKit.line(_body, String(p.party_name), PanelKit.Tone.DIM)
				break

	if not person.traits.is_empty():
		var traits: Array[String] = []
		for t in person.traits:
			traits.append(String(TRAIT_LABEL.get(t, t)))
		PanelKit.line(_body, ", ".join(traits), PanelKit.Tone.DIM)

	# The live state, one line each: what the player's term has done to them.
	var grudge := float(ns.person_grudges.get(person.id, 0.0))
	var loyalty := float(ns.person_loyalty.get(person.id, 0.0))
	var standing := float(ns.person_standing.get(person.id, 0.0))
	if grudge >= 0.05 or loyalty != 0.0 or standing >= 0.05:
		PanelKit.row(_body, "Standing", "%.2f" % standing)
		PanelKit.row(_body, "Loyalty", "%+.2f" % loyalty)
		PanelKit.row(_body, "Grudge", "%.2f" % grudge)

	if not person.wants.is_empty():
		PanelKit.line(_body, "Wants", PanelKit.Tone.DIM)
		for want in person.wants:
			PanelKit.line(_body, "  %s %s" % [
				String(want["stance"]), String(want["object"])])

	visible = true


func hide_card() -> void:
	visible = false
