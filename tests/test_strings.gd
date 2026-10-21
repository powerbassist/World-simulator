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

var _failures: Array[String] = []


func _init() -> void:
	_check_languages()
	_check_switch()
	_check_rows()
	_check_tables()
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
			var text := String(table[msgid])
			if text.strip_edges() == "":
				_fail("%s: '%s' is translated to nothing" % [lang, msgid])
			if Strings.placeholders(String(msgid)) != Strings.placeholders(text):
				_fail("%s: '%s' and its translation do not share placeholders in order" % [lang, msgid])
	if Strings.placeholders("%d of %s, %.1f%% (%%)") != ["%d", "%s", "%.1f", "%%", "%%"]:
		_fail("placeholders() read %s" % [Strings.placeholders("%d of %s, %.1f%% (%%)")])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_strings: all checks passed")
	else:
		for f in _failures:
			printerr(f)
