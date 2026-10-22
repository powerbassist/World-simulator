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

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Strings = preload("res://src/ui/strings.gd")

const SECTION := "glossary"  # i18n: ok a config section
const KEY := "hint_shown"  # i18n: ok a config key


## Push the note into `inbox` unless this profile has had it; then remember it has.
## `path` is the settings file; a test passes its own, since tests sharing a user
## dir would otherwise race on the flag.
static func offer(inbox, path := SettingsPanel.CONFIG_PATH) -> void:
	if inbox == null:
		return
	var cfg := ConfigFile.new()
	cfg.load(path)  # an absent file is a profile that has seen nothing
	if bool(cfg.get_value(SECTION, KEY, false)):
		return
	inbox.push(Strings.t("Dotted words explain themselves"),
		Strings.t("A word underlined in dots has a note behind it: point at one, as here -- [g=approval]approval[/g]. Click it to keep the note open, and its own dotted words open the next."))
	cfg.set_value(SECTION, KEY, true)
	cfg.save(path)
