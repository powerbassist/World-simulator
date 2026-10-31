extends RefCounted

## V4.8c. Message settings -- Victoria 3's shape, wired to severity.
##
## Per event category, four switches: NOTIFY (the action-bar mark, pending.gd),
## FEED (the Dispatches ledger's record), POPUP (the inbox decision card)
## and PAUSE (the arrival pause). Each switch holds a SEVERITY THRESHOLD, not a
## boolean: it fires for an event at or above it. A category carries no severity of
## its own -- its events do (`ev.severity`, 1..3) -- so a per-category on/off could
## not give "defaults banded by severity" any meaning; a threshold per category is
## the one shape where it does. OFF is one past the worst severity.
##
## Static, like pending.gd, and read-only over nothing: the register is a plain
## Dictionary {category: {switch: threshold}} that main.gd holds and hands to the
## readers. An EMPTY dictionary reads as the defaults everywhere, so a reader
## constructed before main.gd loads the file draws exactly what a first launch does.
##
## Persisted in the settings screen's own file under `[messages]`, absent key ->
## default (settings_panel.gd's `[audio]`/`[display]` precedent). It is not a save
## field: these are the player's preferences, not the game's state, so a loaded game
## keeps whatever this machine says and SAVE_VERSION does not move.
##
## WHAT PAUSE OFF DOES NOT BUY. The arrival pause exists because a decision that
## expired unseen was "Decided for you" in both playtests (2026-09-05). PAUSE OFF
## defers the pause, it does not remove it: main.gd's lapse guard holds the clock
## for an unanswered quiet decision in its LAST month. And an interrupt-flagged
## event ignores this register entirely -- the flag is the content saying "until
## answered", and a preference does not overrule content.

const EventsK = preload("res://src/sim/events_constants.gd")

const SECTION := "messages"
const SWITCHES := ["notify", "feed", "popup", "pause"]

## The player-facing column names, in SWITCHES order.
const SWITCH_LABELS := ["Notify", "Feed", "Popup", "Pause"]  # i18n: msgid

## One past critical: no severity reaches it.
const OFF := EventsK.SEVERITY_MAX + 1

## The bands a switch can sit at, index = threshold - 1, so the settings screen's
## OptionButton index and the stored value are one subtraction apart.
const BAND_LABELS := ["All", "Major+", "Critical", "Off"]  # i18n: msgid

## The defaults, one band per switch and the same for every category -- banded by
## severity, not by taste: nothing here says scandals matter less than disasters.
## Notify, feed and popup show everything, which is what the game did before this
## register existed. PAUSE is Major+ (author's call, 2026-10-17): a minor arrival
## keeps the clock running and is caught by the lapse guard in its last month; a
## major or critical one still stops the world on arrival as it always has.
const DEFAULTS := {"notify": 1, "feed": 1, "popup": 1, "pause": 2}


## V5.1-0c. Whether acts between two OTHER nations get a card at all. A separate
## scalar rather than a category: it is about WHO the news concerns, not how severe
## it is, and the author did not want to be told what other countries do to each
## other. Off by default; an act aimed at the player cards regardless. Stored in
## the same section, so save_to() (which edits keys in place) keeps it.
const FOREIGN_NEWS_KEY := "foreign_news"
const DEFAULT_FOREIGN_NEWS := false


static func foreign_news(path: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return bool(cfg.get_value(SECTION, FOREIGN_NEWS_KEY, DEFAULT_FOREIGN_NEWS))


## V5.3-0, the author's call 2 ("Réglage « si nouveau »"): the monthly briefing holds
## every month by default; this setting skips a month whose three priorities are
## all ones last month's briefing already named.
const BRIEFING_NEW_ONLY_KEY := "briefing_new_only"
const DEFAULT_BRIEFING_NEW_ONLY := false
## A test seam: a bool pins the setting in this process, null reads the file. A
## parallel pool's tests share one settings file, so a test that needs the
## briefing to open every month cannot rely on the file while another writes it
## (QA's TAKE on #230: test_briefing_clock's writes failed test_briefing_go).
static var forced_new_only = null


static func briefing_new_only(path: String) -> bool:
	if forced_new_only != null:
		return bool(forced_new_only)
	var cfg := ConfigFile.new()
	cfg.load(path)
	return bool(cfg.get_value(SECTION, BRIEFING_NEW_ONLY_KEY, DEFAULT_BRIEFING_NEW_ONLY))


static func set_foreign_news(on: bool, path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(SECTION, FOREIGN_NEWS_KEY, on)
	cfg.save(path)


## Every category, every switch, at its default.
static func defaults() -> Dictionary:
	var out := {}
	for category in EventsK.CATEGORIES:
		var row := {}
		for switch in SWITCHES:
			row[switch] = int(DEFAULTS[switch])
		out[category] = row
	return out


## The whole register as the file holds it; an absent key, an absent file or an
## out-of-band value reads as the default.
static func load_from(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(path)  # an absent file leaves it empty, which is the default set
	var out := defaults()
	for category in EventsK.CATEGORIES:
		for switch in SWITCHES:
			var stored := int(cfg.get_value(SECTION, _key(category, switch), int(DEFAULTS[switch])))
			out[category][switch] = clampi(stored, EventsK.SEVERITY_MIN, OFF)
	return out


## Writes the register into `path`, keeping every other section the file holds.
static func save_to(settings: Dictionary, path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for category in EventsK.CATEGORIES:
		for switch in SWITCHES:
			cfg.set_value(SECTION, _key(category, switch), threshold(settings, category, switch))
	cfg.save(path)


## The band one switch sits at for one category; the default when the register
## does not say.
static func threshold(settings: Dictionary, category: String, switch: String) -> int:
	var row: Dictionary = settings.get(category, {})
	return int(row.get(switch, DEFAULTS.get(switch, 1)))


## Whether `switch` fires for an event of `category` at `severity`.
static func allows(settings: Dictionary, category: String, severity: int, switch: String) -> bool:
	return severity >= threshold(settings, category, switch)


static func _key(category: String, switch: String) -> String:
	return "%s.%s" % [category, switch]
