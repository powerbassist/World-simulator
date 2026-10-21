extends SceneTree

## Headless test: godot --headless --script res://tests/test_strings.gd
## Non-zero exit on any failure.
##
## V5.1b. The localisation plumbing (src/ui/strings.gd): English is the msgid, the
## French table is data/i18n/fr/ui.json, a language is chosen by code, and a row of
## data/ is translated by the key `<id>.<field>` in data/i18n/<lang>/<kind>.json
## with the English in the row itself as the fallback. What this pins is the
## contract the content child translates against: a miss is the English, a
## placeholder survives translation, and the switch is reversible.

const Strings = preload("res://src/ui/strings.gd")
const Law = preload("res://src/core/law.gd")
const GameEvent = preload("res://src/core/event.gd")
const CampaignAction = preload("res://src/core/campaign_action.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_languages()
	_check_switch()
	_check_rows()
	_check_tables()
	_check_placeholder_parse()
	_check_plurals()
	_check_row_accessors()
	Strings.set_language("en")
	_finish()
	quit(1 if not _failures.is_empty() else 0)


func _check_languages() -> void:
	var codes: Array[String] = []
	for entry in Strings.languages():
		codes.append(String(entry["code"]))
		if String(entry.get("name", "")) == "":
			_fail("language %s has no name" % entry["code"])
	if codes.size() < 2 or codes[0] != "en" or not codes.has("fr"):
		_fail("languages() should list en first and fr, got %s" % [codes])
	if Strings.language() != "en":
		_fail("the default language should be en, got %s" % Strings.language())


func _check_switch() -> void:
	if tr("SETTINGS") != "SETTINGS":
		_fail("tr() in English should return the msgid, got %s" % tr("SETTINGS"))
	if not Strings.set_language("fr"):
		_fail("set_language('fr') was refused")
	if Strings.language() != "fr":
		_fail("language() should be fr after the switch")
	if tr("SETTINGS") != "PARAMÈTRES":
		_fail("tr('SETTINGS') in French should be PARAMÈTRES, got %s" % tr("SETTINGS"))
	if Strings.t("SETTINGS") != "PARAMÈTRES":
		_fail("Strings.t() should translate like tr(), got %s" % Strings.t("SETTINGS"))
	if tr("A line no table has ever seen") != "A line no table has ever seen":
		_fail("a msgid with no translation should come back unchanged")
	# A language that is not offered is refused and nothing moves.
	if Strings.set_language("xx"):
		_fail("an unknown language should be refused")
	if Strings.language() != "fr" or tr("SETTINGS") != "PARAMÈTRES":
		_fail("a refused switch should leave the language as it was")
	# And the switch is reversible: the French table is removed, not shadowed.
	Strings.set_language("en")
	if tr("SETTINGS") != "SETTINGS":
		_fail("switching back to English should return the msgid, got %s" % tr("SETTINGS"))


func _check_rows() -> void:
	var english := "Single-Term Presidency Act"
	if Strings.row("laws", "single_term_reform", "name", english) != english:
		_fail("in English a row is its own text")
	# The law accessor the display sites use: the row's own English in English, the
	# override in French, the English again for a law the table has never heard of.
	var law := Law.new()
	law.id = "single_term_reform"
	law.law_name = english
	law.summary = "A summary"
	if Strings.law_name(law) != english:
		_fail("in English a law's name is its own")
	Strings.set_language("fr")
	if Strings.law_name(law) == english:
		_fail("the French table should override the law's name through law_name()")
	if Strings.law_name(null, "the_id") != "the_id":
		_fail("a missing law should show the fallback the caller gives")
	law.id = "no_such_law"
	if Strings.law_name(law) != english or Strings.law_summary(law) != "A summary":
		_fail("a law with no French entry should show its English name and summary")
	var fr := Strings.row("laws", "single_term_reform", "name", english)
	if fr == english or fr == "":
		_fail("the French table should override the single-term law's name, got '%s'" % fr)
	if Strings.row("laws", "no_such_law", "name", "Fallback") != "Fallback":
		_fail("a row with no French entry should return the English it was given")
	if Strings.row("no_such_kind", "x", "name", "Fallback") != "Fallback":
		_fail("a kind with no table should return the English it was given")
	Strings.set_language("en")


## Every translation keeps its source's placeholders, in the same order: `%` cannot
## reorder them, so a French string that swaps two is a wrong number under a right
## label. The same check runs on the row tables, which may carry placeholders too.
func _check_tables() -> void:
	for lang in ["fr"]:
		var table := Strings.ui_table(lang)
		if table.is_empty():
			_fail("the %s UI table is empty or missing" % lang)
		for msgid in table:
			# A plural entry is a list of forms (the loader hands back a PackedStringArray); every form keeps the singular's
			# placeholders, because the caller formats whichever form is picked.
			var forms: Array = Array(table[msgid]) if table[msgid] is PackedStringArray else [table[msgid]]
			for form in forms:
				var text := String(form)
				if text.strip_edges() == "":
					_fail("%s: '%s' is translated to nothing" % [lang, msgid])
				if Strings.placeholders(String(msgid)) != Strings.placeholders(text):
					_fail("%s: '%s' and its translation do not share placeholders in order" % [lang, msgid])
	if Strings.placeholders("%d of %s, %.1f%% (%%)") != ["%d", "%s", "%.1f", "%%", "%%"]:
		_fail("placeholders() read %s" % [Strings.placeholders("%d of %s, %.1f%% (%%)")])


## A placeholder is `%` immediately followed by its conversion. A French "50 % du PIB"
## (a space, even a non-breaking one, before the percent sign) holds none.
func _check_placeholder_parse() -> void:
	for text in ["50 % du PIB", "50 % du PIB", "100 % of total", "rate: 5 % d'intérêt"]:
		if not Strings.placeholders(text).is_empty():
			_fail("'%s' holds no placeholder, read %s" % [text, Strings.placeholders(text)])
	if Strings.placeholders("%d %% of %s, 50 % du total") != ["%d", "%%", "%s"]:
		_fail("a real placeholder next to a spaced percent was misread: %s" % [Strings.placeholders("%d %% of %s, 50 % du total")])


## tr_n / Strings.tn through a table: a msgid's value is a list of forms, picked by the
## language's plural rule (French: 0 and 1 are the first form). The fixture table is
## the test's own, so this does not borrow the real French.
func _check_plurals() -> void:
	var real_dir := Strings.dir
	Strings.dir = "res://tests/fixtures/i18n"
	if not Strings.set_language("fr"):
		_fail("the fixture table was refused")
	for n in [0, 1, 2, 5]:
		var want := "%d pomme" % n if n < 2 else "%d pommes" % n
		if tr_n("%d apple", "%d apples", n) % n != want:
			_fail("tr_n(%d) gave '%s', wanted '%s'" % [n, tr_n("%d apple", "%d apples", n) % n, want])
		if Strings.tn("%d apple", "%d apples", n) % n != want:
			_fail("Strings.tn(%d) differs from tr_n" % n)
	if tr("Hello %s") % "x" != "Bonjour x":
		_fail("a plain entry beside the plural ones should still translate")
	if Strings.plural_forms("fr") != 2:
		_fail("plural_forms('fr') should read 2 from the language entry")
	Strings.set_language("en")
	if tr_n("%d apple", "%d apples", 1) % 1 != "1 apple" or tr_n("%d apple", "%d apples", 3) % 3 != "3 apples":
		_fail("in English tr_n should pick the source singular or plural")
	Strings.dir = real_dir


## V5.1b3. The row accessors every display of a data row goes through, against the
## fixture tables: a loaded object and a plain row Dictionary, an event's choice, a
## record's copied English (an old save's event the data has since dropped keeps its
## own words), and an action's authored noun found through its effect id, which is not
## the action's id (`start_x` holds the effort `x`).
func _check_row_accessors() -> void:
	var event := GameEvent.new()
	event.id = "fixture_event"
	event.event_name = "English event"
	event.summary = "English summary"
	var choice := {"id": "yield", "label": "English choice", "summary": "English choice summary"}
	var programme := {"id": "fixture_entry", "name": "English entry", "summary": "English entry summary"}
	var action := CampaignAction.new()
	action.id = "start_fixture_effort"
	action.action_name = "Start the English effort"
	action.effects = {"campaign": {"op": "start", "effort_id": "fixture_effort", "effort_name": "The English effort"}}
	var decoy := CampaignAction.new()
	decoy.id = "stop_fixture_effort"
	decoy.effects = {"campaign": {"op": "stop", "effort_id": "fixture_effort"}}
	var actions := [decoy, action]
	var record := {"event_id": "fixture_event", "event_name": "English event", "choice_id": "yield", "choice_label": "English choice"}
	var gone := {"event_id": "dropped_since", "event_name": "An old event", "choice_id": "x", "choice_label": "An old choice"}
	var expect := {
		"English event": Strings.row_name("events", event),
		"English summary": Strings.row_summary("events", event),
		"English choice": Strings.choice_label(event.id, choice),
		"English choice summary": Strings.choice_summary(event.id, choice),
		"English entry": Strings.row_name("programme", programme),
		"English entry summary": Strings.row_summary("programme", programme),
		"Start the English effort": Strings.row_name("campaign-actions", action),
		"The English effort": Strings.noun("campaign-actions", actions, "campaign", "effort_id", "fixture_effort", "effort_name", "The English effort"),
	}
	for english in expect:
		if expect[english] != english:
			_fail("in English a row accessor returns the row's own text: %s gave %s" % [english, expect[english]])
	var real_dir := Strings.dir
	Strings.dir = "res://tests/fixtures/i18n"
	Strings.set_language("fr")
	# [wanted, got]: a "50 %" in a translation is text, never a placeholder to format.
	var french := [
		["FR événement", Strings.row_name("events", event)],
		["FR résumé d'événement", Strings.row_summary("events", event)],
		["Céder 50 % du PIB", Strings.choice_label(event.id, choice)],
		["FR résumé du choix", Strings.choice_summary(event.id, choice)],
		["FR événement", Strings.record_event_name(record)],
		["Céder 50 % du PIB", Strings.record_choice_label(record)],
		["FR programme", Strings.row_name("programme", programme)],
		["FR résumé du programme", Strings.row_summary("programme", programme)],
		["FR lancer l'effort", Strings.row_name("campaign-actions", action)],
		["FR l'effort", Strings.noun("campaign-actions", actions, "campaign", "effort_id", "fixture_effort", "effort_name", "The English effort")],
		["An old event", Strings.record_event_name(gone)],
		["An old choice", Strings.record_choice_label(gone)],
		["The English fallback", Strings.noun("campaign-actions", actions, "campaign", "effort_id", "no_such_effort", "effort_name", "The English fallback")],
	]
	for pair in french:
		if pair[1] != pair[0]:
			_fail("a row accessor under the fixture French: wanted '%s', got '%s'" % pair)
	Strings.set_language("en")
	Strings.dir = real_dir


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_strings: all checks passed")
	else:
		for f in _failures:
			printerr(f)
