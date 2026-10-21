extends RefCounted

## The ONE place an id becomes the word a player reads -- V5.1b3. The sim keys blocs,
## sectors, portfolios, votes, event categories and the rest on bare ids and carries no
## display name, so a panel that printed `id.capitalize()` showed English in every
## language; tests/test_i18n_rows_lint.gd now fails that. The English stays in the
## tables below, marked for the extractor, and is translated here -- DateText's pattern.
## An id no table knows is shown as itself, capitalised, rather than as nothing.

const Strings = preload("res://src/ui/strings.gd")

const BLOC := {
	"workers": "Workers", "pensioners": "Pensioners", "urban": "Urban",  # i18n: msgid
	"rural": "Rural", "business": "Business", "students": "Students",  # i18n: msgid
}
const SECTOR := {
	"agriculture": "Agriculture", "industry": "Industry", "services": "Services",  # i18n: msgid
}
const PORTFOLIO := {
	"health": "Health", "education": "Education", "defence": "Defence",  # i18n: msgid
	"pensions": "Pensions", "infrastructure": "Infrastructure",  # i18n: msgid
}
const VOTE := {"for": "For", "against": "Against", "abstain": "Abstain"}  # i18n: msgid
const EVENT_CATEGORY := {
	"scandal": "Scandal", "fiscal": "Fiscal", "unrest": "Unrest", "personal": "Personal",  # i18n: msgid
	"european": "European", "foreign": "Foreign", "industrial": "Industrial",  # i18n: msgid
	"commodity": "Commodity", "disaster": "Disaster",  # i18n: msgid
}
const SEVERITY := {"minor": "Minor", "major": "Major", "critical": "Critical"}  # i18n: msgid
const ENERGY_BRANCH := {"fossil": "Fossil", "nuclear": "Nuclear", "renewable": "Renewable"}  # i18n: msgid
const PROGRAMME_GROUP := {
	"economy": "Economy", "institutions": "Institutions", "europe": "Europe",  # i18n: msgid
	"society": "Society", "office": "Office",  # i18n: msgid
}
const TAX := {
	"income": "Income tax", "corporate": "Corporate tax", "vat": "VAT",  # i18n: msgid
	"capital_gains": "Capital gains tax", "wealth": "Wealth tax",  # i18n: msgid
}


static func of(table: Dictionary, id: String) -> String:
	if table.has(id):
		return Strings.t(String(table[id]))
	return id.capitalize()  # i18n: row-ok an id no table knows, shown as itself


static func bloc(id: String) -> String:
	return of(BLOC, id)


static func sector(id: String) -> String:
	return of(SECTOR, id)


static func portfolio(id: String) -> String:
	return of(PORTFOLIO, id)


static func vote(id: String) -> String:
	return of(VOTE, id)


static func event_category(id: String) -> String:
	return of(EVENT_CATEGORY, id)


static func severity(id: String) -> String:
	return of(SEVERITY, id)


static func energy_branch(id: String) -> String:
	return of(ENERGY_BRANCH, id)


static func programme_group(id: String) -> String:
	return of(PROGRAMME_GROUP, id)


static func tax(id: String) -> String:
	return of(TAX, id)
