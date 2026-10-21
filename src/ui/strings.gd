extends RefCounted

## Localisation plumbing -- V5.1b. Godot's own TranslationServer does the work; this
## file is how its tables get there, how the player's language reaches it, and the
## one accessor for text that lives in data/ rather than in a script.
##
## THE MSGID IS THE ENGLISH. `tr("Save the game")` in src/ui, and a data row's own
## `name`, are the source text; a language is a table from that text to its
## translation, data/i18n/<code>/ui.json for the UI and <kind>.json (keyed
## `<id>.<field>`) for rows. There is no English table: it would be an identity
## copy to keep in step with every edit, and the extractor (tools/i18n_extract.py)
## already reports a translation whose source went away. Every miss is the English.
##
## Tables are JSON read at runtime into a `Translation`, not `.translation` imports,
## for the reason fonts and icons are read as bytes: tools/run_tests.sh runs
## headless from a fresh clone and an unimported asset does not load.
##
## `tr()` returns a plain String, so a Control given `tr("Save")` keeps the text of
## the language it was built in -- a later switch does not re-translate it. The
## language is applied before a scene is built (SettingsPanel.apply_saved) and the
## Settings row says so; see docs/localisation.md.

const DIR := "res://data/i18n"
const DEFAULT := "en"
## A placeholder is `%` IMMEDIATELY followed by its conversion: a French "50 % du PIB"
## (a space before the percent sign) holds none.
const _PLACEHOLDER := r"%[-+#0]*\d*(?:\.\d+)?[sdfxXc%]"  # i18n: ok

## Where the tables are read from; a test points it at a fixture language.
static var dir := DIR
static var _language := DEFAULT
## The decimal separator of the current language (languages.json `decimal`); Num reads it.
static var _decimal := "."
static var _installed: Translation
## kind -> {"<id>.<field>": text} for the current language; cleared on a switch.
static var _rows := {}
static var _placeholder_regex: RegEx


## `tr()` for a static function, where the instance method does not exist. The same
## msgid rules; the lint and tools/i18n_extract.py read both spellings.
static func t(msgid: String) -> String:
	return TranslationServer.translate(msgid)


## `tr_n()` for a static function: the singular and plural English, and the count that
## picks the form. A table entry is a list of forms under the SINGULAR msgid; every
## form keeps the singular's placeholders (the caller formats whichever is picked).
static func tn(singular: String, plural: String, n: int) -> String:
	return TranslationServer.translate_plural(singular, plural, n)


## How many plural forms a language's table gives each plural msgid (its entry in
## languages.json); 2 for English and French (0 and 1 are the first form in French).
static func plural_forms(code: String) -> int:
	for entry in languages():
		if String(entry["code"]) == code:
			return int(entry.get("plural_forms", 2))
	return 2


## The offered languages, English first: [{code, name}].
static func languages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed = _read_json("%s/languages.json" % dir)
	if parsed is Dictionary:
		for entry in parsed.get("languages", []):
			if entry is Dictionary and entry.has("code") and entry.has("name"):
				out.append(entry)
	return out


static func language() -> String:
	return _language


## The decimal separator of the current language: "." in English, "," in French.
static func decimal() -> String:
	return _decimal


## Makes `code` the language of every tr() from here on. False, and nothing moves,
## for a code languages() does not list.
static func set_language(code: String) -> bool:
	var offered := false
	for entry in languages():
		if String(entry["code"]) == code:
			offered = true
	if not offered:
		return false
	if _installed != null:
		TranslationServer.remove_translation(_installed)
		_installed = null
	_rows.clear()
	_language = code
	_decimal = "."
	for entry in languages():
		if String(entry["code"]) == code:
			_decimal = String(entry.get("decimal", "."))
	if code != DEFAULT:
		var translation := Translation.new()
		translation.locale = code
		var table := ui_table(code)
		for msgid in table:
			if table[msgid] is PackedStringArray:
				translation.add_plural_message(StringName(msgid), table[msgid])
			else:
				translation.add_message(StringName(msgid), StringName(String(table[msgid])))
		TranslationServer.add_translation(translation)
		_installed = translation
	TranslationServer.set_locale(code)
	return true


## data/i18n/<code>/ui.json: {msgid: translation}. Empty for a missing file.
static func ui_table(code: String) -> Dictionary:
	return _table("%s/%s/ui.json" % [dir, code])


## A row's text in the current language: the table's entry for `<id>.<field>` in
## data/i18n/<lang>/<kind>.json, else `english` -- the text the row itself holds.
## Nested fields are dotted: an event choice's label is
## `<event id>.choices.<choice id>.label`.
static func row(kind: String, id: String, field: String, english: String) -> String:
	if _language == DEFAULT:
		return english
	if not _rows.has(kind):
		_rows[kind] = _table("%s/%s/%s.json" % [dir, _language, kind])
	var table: Dictionary = _rows[kind]
	var text := String(table.get("%s.%s" % [id, field], ""))
	return text if text != "" else english


## A law's name and summary as the player reads them: `row("laws", id, field, ...)`
## with the English the Law object holds. Every display site of a law's name goes
## through here, so a law the French table has not reached shows English.
static func law_name(law, fallback := "") -> String:
	if law == null:
		return fallback
	return row("laws", String(law.id), "name", String(law.law_name))


static func law_summary(law) -> String:
	return row("laws", String(law.id), "summary", String(law.summary))


## The printf placeholders of `text` in order, "%%" included: what `%` will consume,
## and what a translation must keep (it cannot reorder them).
static func placeholders(text: String) -> Array[String]:
	if _placeholder_regex == null:
		_placeholder_regex = RegEx.create_from_string(_PLACEHOLDER)
	var out: Array[String] = []
	for m in _placeholder_regex.search_all(text):
		out.append(m.get_string())
	return out


static func _table(path: String) -> Dictionary:
	var parsed = _read_json(path)
	var out := {}
	if parsed is Dictionary:
		for key in parsed:
			if String(key).begins_with("_"):
				continue
			# A list of plural forms stays a list; everything else is one string.
			if parsed[key] is Array:
				out[String(key)] = PackedStringArray(parsed[key])
			else:
				out[String(key)] = String(parsed[key])
	return out


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
