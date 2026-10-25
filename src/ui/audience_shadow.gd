extends VBoxContainer

## The audience's shadows -- V5.2c c1 (Systems' src/sim/shadows.gd): the money a
## request can come with, and the affair. Its own control beside the levers
## (audience_verbs.gd), because neither is a lever: an offer is the person's, put
## on the table as the request arrives, and an affair is between two people, not
## an attempt on a want.
##
## It writes nothing: a click emits, and the wiring (audience_talks.gd) calls
## Shadows.accept_offer / refuse_offer / begin_affair / end_affair and hands the
## result back. What it shows is the view's `shadow` block, read off the sim.

signal offer_answered(accepted: bool)
signal affair(action: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Words = preload("res://src/ui/lever_words.gd")

## The reasons a proposal is not even put: no standing, or lovers already. Every
## other reason is the person's to give, in their own words, once it is asked.
const UNASKED := ["not_covered", "already"]

var _offer: VBoxContainer
var _line: Label
var _terms: Label
var _affair: HFlowContainer
var _propose: Button
var _stop: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_offer = VBoxContainer.new()
	_offer.add_theme_constant_override("separation", 4)
	add_child(_offer)
	_line = Label.new()
	_line.name = "OfferLine"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_offer.add_child(_line)
	_terms = Label.new()
	_terms.theme_type_variation = UiTheme.CAPTION
	_offer.add_child(_terms)
	var answers := PanelKit.buttons(_offer)
	var accept := PanelKit.sized(Button.new())
	accept.name = "OfferAccept"
	accept.text = tr("Accept")
	accept.tooltip_text = tr("Take it: the request is settled and an attempt spent, and it leaves evidence that can be found.")
	accept.pressed.connect(func() -> void: offer_answered.emit(true))
	answers.add_child(accept)
	var refuse := PanelKit.sized(Button.new())
	refuse.name = "OfferRefuse"
	refuse.text = tr("Refuse")
	refuse.tooltip_text = tr("Turn it down: they think a little less of you, and nothing else.")
	refuse.pressed.connect(func() -> void: offer_answered.emit(false))
	answers.add_child(refuse)
	_affair = PanelKit.buttons(self)
	_propose = Button.new()
	_propose.name = "ProposeAffair"
	_propose.text = tr("Propose an affair")
	_propose.pressed.connect(func() -> void: affair.emit("propose"))
	_affair.add_child(_propose)
	_stop = Button.new()
	_stop.name = "EndAffair"
	_stop.text = tr("End the affair")
	_stop.tooltip_text = tr("It ends here: they take it badly, and what it left behind stays.")
	_stop.pressed.connect(func() -> void: affair.emit("end"))
	_affair.add_child(_stop)
	show_for({})


## `view`: the scene's view; its `shadow` block is {offer: {currency,
## amount_eur_m} or {}, affair_why: Shadows.may_begin_affair()'s key, flirted:
## a flirt spoken this audience, lovers: an affair under way}.
func show_for(view: Dictionary) -> void:
	var shadow: Dictionary = view.get("shadow", {})
	var offer: Dictionary = shadow.get("offer", {})
	_offer.visible = not offer.is_empty()
	if not offer.is_empty():
		_terms.text = tr("On the table: %s.") % Words.offer_terms(offer)
	var lovers := bool(shadow.get("lovers", false))
	var why := String(shadow.get("affair_why", ""))
	# Proposed only once there has been a flirt: the scene's own order, flirt first.
	_propose.visible = bool(shadow.get("flirted", false)) and not lovers
	_propose.disabled = UNASKED.has(why)
	_propose.tooltip_text = Words.reason(why) if UNASKED.has(why) else tr("Ask them: they may say yes, or tell you why not.")
	_stop.visible = lovers
	_affair.visible = _propose.visible or _stop.visible


## The person's offer in their own words (the wiring awaits DialogueManager); ""
## leaves the terms alone to say it.
func set_offer_line(text: String) -> void:
	_line.text = text
	_line.visible = text != ""
