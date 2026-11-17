extends RefCounted

## The Bills second pass: the one word a law's row shows beside its name -- "raises",
## "grants", "requires" -- so the row says what the law changes before its summary does. An
## OPTIONAL authored field (`verb`); a law without one shows no word, never a word guessed from
## its summary. Kept off Law itself (law.gd is at the size ratchet's ceiling), the way
## law_category.gd keeps the shelf: the loader holds DataLoader.law_verb, keyed by law id.
## tools/law_lint.py checks the same shape.

## The longest verb a row has room for, in letters (law_lint.py's VERB_MAX).
const MAX := 14


## A row's verb, "" when it has none; "" and an error when it is not one lowercase English word
## (a to z only: the data is English, a translation goes through data/i18n).
static func parse(d: Dictionary, law_id: String, filename: String, errors: Array[String]) -> String:
	if not d.has("verb"):
		return ""
	var verb = d["verb"]
	if typeof(verb) != TYPE_STRING or String(verb).is_empty() or String(verb).length() > MAX \
			or String(verb).to_lower() != String(verb) or not _letters(String(verb)):
		errors.append("%s: %s verb must be one lowercase word, at most %d letters" % [filename, law_id, MAX])
		return ""
	return String(verb)


static func _letters(word: String) -> bool:
	for c in word:
		if not (c >= "a" and c <= "z"):
			return false
	return true
