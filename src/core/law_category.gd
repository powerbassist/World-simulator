extends RefCounted

## V5.3, screen 4 (H12): where a law sits in the statute book, for the player's
## browsing and search. Thirteen categories, each holding at least four of the authored
## laws. A browsing key only: no rule reads it, so no number moves with it.
##
## Kept off Law itself (law.gd is at the size ratchet's ceiling) and off the save: the
## category is a property of the authored row, so the loader keeps it in
## DataLoader.law_category, keyed by law id. A composed law has none, and reads "".
## `theme` stays: it groups the spread lints and the effect columns, which is a
## different job from the player's shelf.

const KEYS := ["taxes", "work", "welfare_health", "education_culture", "housing",
	"energy_environment", "business", "farming", "justice_transparency", "constitution",
	"elections", "media", "europe_migration"]


## A row's category; "" and an error when it is missing or not one of KEYS.
static func parse(d: Dictionary, law_id: String, filename: String, errors: Array[String]) -> String:
	var category = d.get("category", "")
	if typeof(category) != TYPE_STRING or not KEYS.has(category):
		errors.append("%s: %s category must be one of %s" % [filename, law_id, KEYS])
		return ""
	return category


## The category of `law_id` as the loader read it; "" for a law with none.
static func of(loader, law_id: String) -> String:
	return String(loader.law_category.get(law_id, ""))
