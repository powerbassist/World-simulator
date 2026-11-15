extends PanelContainer

## The bill briefing -- V4.2 T5. One popup over a bill the player is about to put to the
## assembly or has just drafted (opened by the tax panel's compose flow, where it carries the
## drafting months). Since V5.3 screen 4 the law sheet holds the same sections inline and
## divides on its own Propose; this popup remains for the bills the sheet does not carry: a
## draft, and an ownership bill (bill_button.gd).
##
## What it says is briefing_sections.gd's -- the channels, the landed price, the two polls --
## so the popup and the sheet cannot disagree. Its one verb of its own: Propose routes through
## main.gd into law_panel.run_proposal(), so one propose path and one card path survive
## however the bill was asked for.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const LawGrade = preload("res://src/ui/law_grade.gd")
const Sections = preload("res://src/ui/briefing_sections.gd")

## Emitted for the division, and ONLY for the division: main.gd hides the
## briefing and calls law_panel.run_proposal(law), whose `proposed` signal
## carries the card and the U4 baseline. A draft has no division to ask for.
signal propose_requested(law)

## Emitted when a poll commission lands, carrying the pre-purchase baseline
## and the label -- finances_panel.gd's `committed` contract. The refusal path
## emits nothing; the briefing shows the refusal itself.
signal polled(before: Dictionary, label: String)

var _state = null
var _loader = null
## The bill's key in the purchase register: the law id, or the draft id while
## the bill is still drafting (which is the law id it will carry).
var _bill_key := ""
## Set for a law on the book (authored or composed); empty for a draft.
var _law = null
## The grade the player picked in the catalogue; 1 for a draft and for a bill with no size.
var _scale := 1.0
## The draft entry (ns.draft_bills shape) for a draft; {} for a law.
var _draft := {}
var _ns = null
var _party_list: Array = []

var _body: VBoxContainer
var _sections: Sections = null


func _ready() -> void:
	# Sized by content and placed by main.gd's CenterContainer -- the same
	# placement mechanism the four modal panels use, whose own comment records
	# why anchors cannot do this before the children exist. The height is the
	# content's honest minimum, measured on the captured frame: shorter and
	# the Propose/Close row scrolls below the fold of a popup that exists to
	# be answered -- the V2.1b finding (politics at 865 against an 826px
	# band) in a popup's shape.
	custom_minimum_size = Vector2(680, 600)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	hide()  # main.gd adds it to the screen stack and shows it on a bill's asking


## A bill on the book -- authored, or a composed law past its drafting.
func open_for_law(law, state, loader, scale := 1.0) -> void:
	_state = state
	_loader = loader
	_law = law
	_scale = scale
	_draft = {}
	_bill_key = String(law.id)
	_ns = _state.player()
	_party_list = _loader.parties.get(_ns.id, [])
	_rebuild()


## A parked draft -- the tax panel's compose flow opens this straight after
## Statute.draft() accepts the spec.
func open_for_draft(entry: Dictionary, draft_id: String, state, loader) -> void:
	_state = state
	_loader = loader
	_law = null
	_draft = entry
	_bill_key = String(draft_id)
	_ns = _state.player()
	_party_list = _loader.parties.get(_ns.id, [])
	_rebuild()


## A load invalidates everything this panel holds: the cached GameState is the
## discarded game, the purchase state on it is dead, and a stale poll press
## would write the dead run's books and push a dead-snapshot effects row into
## the live one. Called from main.gd's load path, beside the industry-map
## resets -- this panel is NOT in the window registry, so the setup() sweep
## that rebinds every registered surface never reaches it (the V2.8 drift
## class, one panel deeper).
func detach() -> void:
	hide()
	_state = null
	_ns = null
	_party_list = []
	_law = null
	_draft = {}
	_bill_key = ""
	if _sections != null:
		_sections.detach()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	_sections = Sections.new(_state, _loader, _law, _scale, _draft, _bill_key, _rebuild, polled.emit)

	PanelKit.line(_body, tr("BILL BRIEFING — %s") % _sections.bill_name(), PanelKit.Tone.PLAIN)
	if _law != null and _scale != 1.0:
		PanelKit.line(_body, tr("At %s.") % LawGrade.size_text(_law, _scale), PanelKit.Tone.PLAIN)
	_sections.channels(_body)
	_sections.price(_body)

	if not _draft.is_empty():
		var months := int(_draft.get("months_left", 0))
		PanelKit.line(_body, tr_n("In drafting: %d month before it reaches the order paper.", "In drafting: %d months before it reaches the order paper.", months) % months, PanelKit.Tone.PLAIN)

	# The Assembly's read: the same walk the legislature window prints, at the band this bill's purchases buy.
	var assembly := ""
	if _law != null:
		assembly = LawPanel.forecast_text(_ns, _party_list, LawGrade.read(_ns, _law, _scale), LawPanel.forecast_band(_ns, _bill_key))
	_sections.polls(_body, assembly)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	_body.add_child(buttons)

	# The division is a law's verb; a draft composes when its countdown ends.
	if _law != null:
		var propose_btn := Button.new()
		propose_btn.text = tr("Propose the bill")
		propose_btn.pressed.connect(func(): propose_requested.emit(_law))
		buttons.add_child(propose_btn)

	var close_btn := Button.new()
	close_btn.text = tr("Close")
	close_btn.pressed.connect(func(): hide())
	buttons.add_child(close_btn)
