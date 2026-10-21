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
const _PLACEHOLDER := r"%[-+ #0]*\d*(?:\.\d+)?[sdfxXc%]"

static var _language := DEFAULT
static var _installed: Translation
## kind -> {"<id>.<field>": text} for the current language; cleared on a switch.
static var _rows := {}
static var _placeholder_regex: RegEx


## `tr()` for a static function, where the instance method does not exist. The same
## msgid rules; the lint and tools/i18n_extract.py read both spellings.
static func t(msgid: String) -> String:
	return TranslationServer.translate(msgid)


## The offered languages, English first: [{code, name}].
static func languages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed = _read_json("%s/languages.json" % DIR)
	if parsed is Dictionary:
		for entry in parsed.get("languages", []):
			if entry is Dictionary and entry.has("code") and entry.has("name"):
				out.append(entry)
	return out


static func language() -> String:
	return _language


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
	if code != DEFAULT:
		var translation := Translation.new()
		translation.locale = code
		var table := ui_table(code)
		for msgid in table:
			translation.add_message(StringName(msgid), StringName(String(table[msgid])))
		TranslationServer.add_translation(translation)
		_installed = translation
	TranslationServer.set_locale(code)
	return true


## data/i18n/<code>/ui.json: {msgid: translation}. Empty for a missing file.
static func ui_table(code: String) -> Dictionary:
	return _table("%s/%s/ui.json" % [DIR, code])


## A row's text in the current language: the table's entry for `<id>.<field>` in
## data/i18n/<lang>/<kind>.json, else `english` -- the text the row itself holds.
## Nested fields are dotted: an event choice's label is
## `<event id>.choices.<choice id>.label`.
static func row(kind: String, id: String, field: String, english: String) -> String:
	if _language == DEFAULT:
		return english
	if not _rows.has(kind):
		_rows[kind] = _table("%s/%s/%s.json" % [DIR, _language, kind])
	var table: Dictionary = _rows[kind]
	var text := String(table.get("%s.%s" % [id, field], ""))
	return text if text != "" else english


## The printf placeholders of `text` in order, "%%" included: what `%` will consume,
## and what a translation must keep (it cannot reorder them).
static func placeholders(text: String) -> Array[String]:
	if _placeholder_regex == null:
		_placeholder_regex = RegEx.create_from_string(_PLACEHOLDER)
	var out: Array[String] = []
	for m in _placeholder_regex.search_all(text):
		out.append(m.get_string())
	return out


## A stand-in for a language that is longer than English, for the fit sweep that must
## run before any real French exists: accented vowels (wider glyphs, a font that
## lacks them shows), 35% more length in wide letters, placeholders untouched.
static func pseudo(text: String) -> String:
	var out := ""
	var i := 0
	var held := placeholders(text)
	while i < text.length():
		var matched := ""
		for p in held:
			if text.substr(i, p.length()) == p:
				matched = p
				break
		if matched != "":
			out += matched
			i += matched.length()
			continue
		var c := text[i]
		out += {"a": "à", "e": "é", "i": "î", "o": "ô", "u": "ü", "A": "Â", "E": "É", "O": "Ö"}.get(c, c)
		i += 1
	return out + "m".repeat(ceili(text.length() * 0.35))


static func _table(path: String) -> Dictionary:
	var parsed = _read_json(path)
	var out := {}
	if parsed is Dictionary:
		for key in parsed:
			if not String(key).begins_with("_"):
				out[String(key)] = String(parsed[key])
	return out


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
