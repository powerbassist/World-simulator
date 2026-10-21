extends RefCounted

## Which city in the register is a nation's capital -- ONE rule, read by the map's
## glyphs, the diary's travel pricing and the campaign's tour (V5.1-0d, G1).
##
## It used to be two rules. The map folded names (case and diacritics) and fell
## back to the largest city; src/sim matched the name EXACTLY and priced a miss at
## TRAVEL_DAYS_MAX. The two files a capital is matched across were imported from
## different sources -- MDA's "Chișinău" is the register's "Chisinau", and MLT's
## Valletta (~6k people) is below the register's cut -- so the map drew both
## capitals while a Warsaw-Chisinau state visit cost 8 days where 3 is right. A
## fold lives in src/core because src/sim may not preload src/ui; the map now reads
## it from here, so the diary cannot disagree with the map about where a capital is.
##
## The largest-city fallback is a BOUND, recorded in docs/map-platform-model.md
## §10: for MLT it puts the capital a few kilometres from Valletta, which no
## whole-day travel price can see.

const _FOLD := {
	"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a", "ă": "a", "ą": "a",
	"ç": "c", "ć": "c", "č": "c", "ĉ": "c", "ď": "d", "đ": "d", "ð": "d",
	"è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ė": "e", "ę": "e", "ě": "e",
	"ğ": "g", "ģ": "g", "ì": "i", "í": "i", "î": "i", "ï": "i", "ī": "i", "į": "i", "ı": "i",
	"ķ": "k", "ł": "l", "ļ": "l", "ľ": "l", "ñ": "n", "ń": "n", "ň": "n", "ņ": "n",
	"ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o", "ő": "o", "ō": "o",
	"ř": "r", "ŕ": "r", "ś": "s", "š": "s", "ş": "s", "ș": "s", "ť": "t", "ţ": "t", "ț": "t",
	"ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u", "ű": "u", "ų": "u",
	"ý": "y", "ÿ": "y", "ź": "z", "ż": "z", "ž": "z",
	"ß": "ss", "æ": "ae", "œ": "oe", "þ": "th",
}


static func fold(text: String) -> String:
	var low := text.to_lower()
	var out := ""
	for i in low.length():
		var ch := low[i]
		out += String(_FOLD.get(ch, ch))
	return out


## The capital's city record, or null when the nation has no city at all: the
## first city whose folded name is the capital's, else the nation's largest city
## by population share.
static func city(loader, nation_id: String) -> Variant:
	var nation = loader.nations.get(nation_id)
	if nation == null:
		return null
	var want := fold(String(nation.capital))
	var largest = null
	var largest_share := -1.0
	for region in loader.regions.get(nation_id, []):
		for c in region.cities:
			if want != "" and fold(c.city_name) == want:
				return c
			var s := float(region.share) * float(c.share)
			if s > largest_share:
				largest_share = s
				largest = c
	return largest


## The capital as a lon/lat, or null (Variant, because null is the not-found
## answer).
static func lonlat(loader, nation_id: String) -> Variant:
	var c = city(loader, nation_id)
	return c.lonlat if c != null else null
