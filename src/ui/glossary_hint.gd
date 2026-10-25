extends RefCounted

## The one note that says the glossary exists -- V5.1-d1c, G12 of the play gate:
## the author played thirty minutes and never saw a tooltip ("j'ai pas vu les
## infobulles"), though the notes told them where. A term was findable only by
## luck: a pointer resting on a dotted word.
##
## Once per PROFILE, not per game (the parent's call): a settings flag beside the
## text size and the language, so a player who has read it is never told twice. Its
## own body marks a term, so the first thing it asks for can be done on the spot.
## The wording says what the player sees -- dotted words, the author's own
## "soulignés en pointillés".
##
## THE SESSION THAT SHOWED IT KEEPS IT (QA on #72): the game offers it at boot, and
## a load then clears the inbox -- with the flag already written, a profile whose
## first session began with a load never saw the note. So the flag stops the NEXT
## session; within the one that offered it, an offer onto an inbox that no longer
## shows the note shows it again.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Strings = preload("res://src/ui/strings.gd")

const SECTION := "glossary"  # i18n: ok a config section
const KEY := "hint_shown"  # i18n: ok a config key

## The settings file the flag lives in. A test points it at a private file: tests
## in one run share a user dir, and every game that boots offers the hint.
static var config_path := SettingsPanel.CONFIG_PATH
## This session's note: the inbox it went into and its card id, or nothing yet.
static var _shown_in = null
static var _card := ""


## Push the note into `inbox` unless this profile has had it in an earlier session,
## or `inbox` still shows it; then remember it has.
static func offer(inbox) -> void:
	if inbox == null:
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # an absent file is a profile that has seen nothing
	if _shown_in == null and bool(cfg.get_value(SECTION, KEY, false)):
		return
	if _shown_in == inbox and inbox.lane_of(_card) != "":
		return
	_card = inbox.push(Strings.t("Dotted words explain themselves"),
		Strings.t("A word underlined in dots has a note behind it: point at one, as here -- [g=approval]approval[/g]. Click it to keep the note open, and its own dotted words open the next."))
	# Its second sentence is the instruction: never folded behind More.
	inbox.keep_whole(_card)
	_shown_in = inbox
	cfg.set_value(SECTION, KEY, true)
	cfg.save(config_path)


## Re-arm the note: the next game shows it, as on a profile that never saw it. The
## dev console's `hint reset` -- any run of the game on a real profile (a smoke, a
## windowed frame) spends the one showing.
static func reset() -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	if cfg.has_section_key(SECTION, KEY):
		cfg.erase_section_key(SECTION, KEY)
	cfg.save(config_path)
	_shown_in = null
	_card = ""
