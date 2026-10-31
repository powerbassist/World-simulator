extends RefCounted

## How a result landed -- V5.2 close R5 (the author at the gate: "all reactions is
## sentences, it lacks colors to show positive, neutral or negative outcome"). A
## result keeps its sentence; a short WORD in a STATUS tone goes before it, so the
## news is read at a glance and never by colour alone (the word says it too).
##
## Tones are the fixed status ones (UiTheme GOOD / BAD / WARN), never the accent:
## the accent says "you are here", not "this went well". Two words share WARN on
## purpose: a verb the sim would not take ("not possible") and one it took that
## leaves something behind ("risky") -- attention, not failure.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Motion = preload("res://src/ui/motion.gd")

const GOOD := "good"  # i18n: ok a tone key
const BAD := "bad"  # i18n: ok a tone key
const BLOCKED := "blocked"  # i18n: ok a tone key
const RISKY := "risky"  # i18n: ok a tone key
const BASE_META := "result_tone_base"  # i18n: ok a meta key
const POP_META := "result_tone_pop"  # i18n: ok a meta key

## key -> [variation, word]. The words are tags, short and upper-cased on screen.
const TAG := {
	GOOD: [UiTheme.GOOD_SMALL, "In your favour"],  # i18n: msgid
	BAD: [UiTheme.BAD_SMALL, "Against you"],  # i18n: msgid
	BLOCKED: [UiTheme.WARN_TEXT, "Not possible"],  # i18n: msgid
	RISKY: [UiTheme.WARN_TEXT, "Risky"],  # i18n: msgid
}


## The tag `label` shows for `tone`; "" (a neutral result) hides it.
static func apply(label: Label, tone: String) -> void:
	label.visible = TAG.has(tone)
	if not TAG.has(tone):
		label.text = ""
		return
	label.theme_type_variation = String(TAG[tone][0])
	label.text = Strings.t(String(TAG[tone][1]))  # i18n: row-ok a tone key, its word the msgid
	# V5.3-0 4.5: the tag pops in (Motion.OPEN_SCALE to full), once it is on screen.
	if label.is_inside_tree():
		Motion.open(label)
	elif not label.has_meta(POP_META):
		label.set_meta(POP_META, true)
		label.tree_entered.connect(func() -> void:
			label.remove_meta(POP_META)
			Motion.open(label), CONNECT_ONE_SHOT)


## A result that moved the person's regard reads by its sign: up is in your
## favour, down against you, none neutral.
static func of_rapport(delta: float) -> String:
	return GOOD if delta > 1e-6 else (BAD if delta < -1e-6 else "")


## A new tag for `tone`, hidden when the result is neutral (V5.3-0 RF7): what a
## surface puts beside its result sentence.
static func tag(tone: String) -> Label:
	var label := Label.new()
	label.name = "ResultTone"  # i18n: ok a node name, found by tests
	apply(label, tone)
	return label


## An inbox card's tag, under its title, as the party chip sits; nothing for a
## neutral result or a card the inbox no longer has.
static func mark(inbox, card_id: String, tone: String) -> void:
	if inbox != null and card_id != "" and TAG.has(tone) and not inbox.has_tag(card_id):
		inbox.add_under_title(card_id, tag(tone))


## An inbox card pushed with its tag: the card id, as inbox.push() returns it.
static func push(inbox, title: String, body: String, tone: String) -> String:
	var card_id: String = inbox.push(title, body)
	mark(inbox, card_id, tone)
	return card_id


## A result whose own sentence already holds the verdict word (PASSED, DEFEATED,
## Refused, Delivered) takes the tone on that sentence instead of a second word:
## the word says it, the tone colours it, and the text diet (RF6) pays nothing.
## A neutral result goes back to the variation the control had before its first
## tint, so a label reused for the next result (a status line) is never left red.
static func tint(control: Control, tone: String) -> void:
	if not control.has_meta(BASE_META):
		control.set_meta(BASE_META, control.theme_type_variation)
	control.theme_type_variation = String(TAG[tone][0]) if TAG.has(tone) else String(control.get_meta(BASE_META))


## A status line's text and its tone in one call.
static func say(label: Label, text: String, tone := "") -> void:
	label.text = text
	tint(label, tone)
