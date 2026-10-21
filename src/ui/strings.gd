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
## The property a loaded row object keeps its English name in, by kind; every action
## kind uses `action_name`.
const _NAME_PROPERTY := {"laws": "law_name", "events": "event_name", "bloc-proposals": "proposal_name", "orgs": "name"}


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
	return row_name("laws", law)


static func law_summary(law) -> String:
	return row_summary("laws", law)


## The name and summary of a data row as the player reads them (V5.1b3) -- every
## display of a row's text goes through these, and tests/test_i18n_rows_lint.gd fails
## a panel that reads the English field itself. `row_data` is the loaded object or a plain
## row Dictionary ({"id", "name", "summary"} -- the programme's entries). A loaded
## object keeps its English name under a property that differs by kind.
static func row_name(kind: String, row_data) -> String:
	if row_data is Dictionary:
		return row(kind, String(row_data.get("id", "")), "name", String(row_data.get("name", "")))
	return row(kind, String(row_data.id), "name", String(row_data.get(_NAME_PROPERTY.get(kind, "action_name"))))


static func row_summary(kind: String, row_data) -> String:
	if row_data is Dictionary:
		return row(kind, String(row_data.get("id", "")), "summary", String(row_data.get("summary", "")))
	return row(kind, String(row_data.id), "summary", String(row_data.summary))


## An event's choice: `<event id>.choices.<choice id>.label|summary`.
static func choice_label(event_id: String, choice: Dictionary) -> String:
	return row("events", event_id, "choices.%s.label" % String(choice.get("id", "")), String(choice.get("label", "")))


static func choice_summary(event_id: String, choice: Dictionary) -> String:
	return row("events", event_id, "choices.%s.summary" % String(choice.get("id", "")), String(choice.get("summary", "")))


## A record the sim kept of an event (the desk's entries, the ledger's answers) copies
## the English it was made with, beside the ids; the ids find the translation and the
## copy is the fallback, so a save whose event the data has since dropped still reads.
static func record_event_name(record: Dictionary) -> String:
	return row("events", String(record.get("event_id", "")), "name", String(record.get("event_name", "")))


static func record_choice_label(record: Dictionary) -> String:
	return row("events", String(record.get("event_id", "")),
		"choices.%s.label" % String(record.get("choice_id", "")), String(record.get("choice_label", "")))


## A sim record's copy of an ACTION's name beside its `action_id` -- an agreement, a
## pact, a measure, a foreign act. Most are diplomatic actions; an org's common external
## measure is keyed by the bloc PROPOSAL's id. The two kinds' ids never collide, so the
## record's kind is whichever table knows the id.
static func record_action_name(record: Dictionary) -> String:
	var id := String(record.get("action_id", ""))
	var english := String(record.get("action_name", id))
	return row("bloc-proposals", id, "name", row("diplomatic-actions", id, "name", english))


## An action's authored NOUN -- an effort's, a pledge's, a project's name, which sits
## in `effects.<effect>.<noun_field>` of the action that makes it. The sim names the
## thing by its effect id (`ground_game`), the table keys it by the action's id
## (`start_ground_game`), so the action is found by its effect id; `english` is what the
## sim's name_of() says, the fallback.
static func noun(kind: String, actions: Array, effect: String, id_key: String, id: String,
		noun_field: String, english: String) -> String:
	for action in actions:
		var terms: Dictionary = action.effects.get(effect, {})
		if String(terms.get(id_key, "")) == id and terms.has(noun_field):
			return row(kind, String(action.id), "effects.%s.%s" % [effect, noun_field], english)
	return english


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
