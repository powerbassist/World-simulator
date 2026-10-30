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

const GOOD := "good"  # i18n: ok a tone key
const BAD := "bad"  # i18n: ok a tone key
const BLOCKED := "blocked"  # i18n: ok a tone key
const RISKY := "risky"  # i18n: ok a tone key

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


## A result that moved the person's regard reads by its sign: up is in your
## favour, down against you, none neutral.
static func of_rapport(delta: float) -> String:
	return GOOD if delta > 1e-6 else (BAD if delta < -1e-6 else "")
