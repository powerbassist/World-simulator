extends RefCounted

## How a tax's rate is written on the Books, in its own unit: a symbol or a word after the number, and an index before
## it ("index 100", the parent's rule on the author's Books comment). A move says the unit once.

const Strings = preload("res://src/ui/strings.gd")


## What follows a number: nothing for an index, which reads before its number, and for no unit at all.
static func suffix(code: String) -> String:
	match code:
		"", "index":
			return ""
		"%":
			return " %"
		"pt":
			return Strings.t(" pt")
		"EUR/l":
			return " €/l"
		"EUR/kg":
			return " €/kg"
		"EUR/t":
			return " €/t"
		"EUR/passenger":
			return Strings.t(" € a passenger")
	return " " + code


static func rate(number: String, code: String) -> String:
	return Strings.t("index %s") % number if code == "index" else number + suffix(code)


## "from 20 to 22 %", "from index 100 to 105".
static func moving(was: String, to: String, code: String) -> String:
	if code == "index":
		return Strings.t("from index %s to %s") % [was, to]
	return Strings.t("from %s to %s") % [was, to + suffix(code)]


## "20 → 22 %", "index 100 → 105".
static func arrow(was: String, to: String, code: String) -> String:
	var before := rate(was, code) if code == "index" else was
	return "%s → %s%s" % [before, to, suffix(code)]
