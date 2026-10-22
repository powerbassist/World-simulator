extends RefCounted

## The glossary table the tooltips read: data/glossary/terms.json, 48 entries,
## English first -- V5.1-c, docs/design/glossary-tooltips.md "The data model".
##
## Read here, in src/ui, and not by DataLoader: the glossary is UI content and no
## system reads it -- Strings reads data/i18n the same way (the parent's call Q1).
## Loaded once, on first use, and checked then: an unknown see_also id, an unknown
## live name or a missing model is a load error, loud, one push_error each ("the
## loader refuses ... at load and loudly"). problems() is the check without the
## noise, so a test can feed it a broken row and count.
##
## Shown text goes through Strings.row("glossary", ...): the English is the row's,
## and French joins under data/i18n/fr/glossary.json when Content un-parks it.

const Strings = preload("res://src/ui/strings.gd")
const GlossaryLive = preload("res://src/ui/glossary_live.gd")

const PATH := "res://data/glossary/terms.json"

static var _rows: Array = []
static var _by_id := {}
static var _loaded := false


static func rows() -> Array:
	_load()
	return _rows


static func ids() -> PackedStringArray:
	_load()
	return PackedStringArray(_by_id.keys())


static func has(id: String) -> bool:
	_load()
	return _by_id.has(id)


static func entry(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})


static func term(id: String) -> String:
	return Strings.row("glossary", id, "term", String(entry(id).get("term", id)))


static func definition(id: String) -> String:
	return Strings.row("glossary", id, "definition", String(entry(id).get("definition", "")))


static func body(id: String) -> String:
	return Strings.row("glossary", id, "body", String(entry(id).get("body", "")))


static func see_also(id: String) -> PackedStringArray:
	return PackedStringArray(entry(id).get("see_also", []))


static func live_name(id: String) -> String:
	return String(entry(id).get("live", ""))


## A model is one `<doc>#<heading>` anchor or a list of them (a definition that
## draws on several sections); anything else reads as none.
static func anchors(model) -> PackedStringArray:
	if model is String:
		return PackedStringArray([model])
	if model is Array:
		return PackedStringArray(model)
	return PackedStringArray()


static func problems(terms: Array, live_names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var known := {}
	for row in terms:
		known[String(row.get("id", ""))] = true
	for row in terms:
		var id := String(row.get("id", ""))
		for other in row.get("see_also", []):
			if not known.has(String(other)):
				out.append("%s: see_also names '%s', which is no entry" % [id, other])  # i18n: ok a load error for the developer
		var live := String(row.get("live", ""))
		if not live.is_empty() and not live_names.has(live):
			out.append("%s: live '%s' is not in the UI's closed table" % [id, live])  # i18n: ok a load error for the developer
		var cited := anchors(row.get("model"))
		if cited.is_empty():
			out.append("%s: no model section cited" % id)  # i18n: ok a load error for the developer
		for anchor in cited:
			var parts := anchor.split("#")
			if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
				out.append("%s: model anchor '%s' is not <doc>#<heading>" % [id, anchor])  # i18n: ok a load error for the developer
	return out


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not parsed is Dictionary:
		push_error("glossary: %s did not load" % PATH)
		return
	_rows = parsed.get("terms", [])
	for row in _rows:
		_by_id[String(row["id"])] = row
	for problem in problems(_rows, GlossaryLive.NAMES):
		push_error("glossary: %s" % problem)
