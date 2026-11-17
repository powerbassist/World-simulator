extends RefCounted

## Why the Assembly cannot take a law now, in the player's words -- the Bills second pass. The
## gate's flag (src/sim/law_gate.gd) made a sentence, read by the row, the sheet and the verb
## table (bill_verbs.gd), so a shut law says the same thing wherever it is pressed. A law whose
## preconditions are unmet names the first one and where the figure stands now.

const LawGate = preload("res://src/sim/law_gate.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## The precondition fields a law names, as a word (legislature_constants' PRECONDITION_FIELDS
## that the book uses; a field not here reads as the plain sentence).
const FIELD_WORDS := {
	"unrest_pct": "unrest",  # i18n: msgid
	"unemployment_pct": "unemployment",  # i18n: msgid
	"debt_to_gdp_pct": "the debt",  # i18n: msgid
	"growth_annual_pct": "growth",  # i18n: msgid
	"deficit_pct_gdp": "the deficit",  # i18n: msgid
	"overall_approval_pct": "your approval",  # i18n: msgid
}


static func text(ns, law, flag: String) -> String:
	match flag:
		LawGate.PASSED:
			return Strings.t("Passed, and it can pass only once.")
		LawGate.COOLDOWN:
			var months := int(ns.law_cooldown_months.get(law.id, 0))
			return Strings.tn("Voted on recently: it can come back in %d month.", "Voted on recently: it can come back in %d months.", months) % months
		LawGate.NOTHING_TO_REPEAL:
			return Strings.t("Nothing to repeal: the law it undoes is not in force.")
		LawGate.CONSTITUTION:
			return Strings.t("This constitution does not allow it.")
		LawGate.IN_FORCE:
			return Strings.t("Already the rule: the electoral method it sets is in force.")
		LawGate.REFERENDUM:
			return Strings.t("Put to the country: the referendum is under way.")
		LawGate.HELD:
			return Strings.t("Carried, and held by the second chamber.")
		LawGate.ASSEMBLY:
			return Strings.t("The Assembly's own bill: it is already before the Assembly.")
		LawGate.CONDITIONS:
			return _condition(ns, law)
	return Strings.t("The Assembly cannot take it now.")


## "Needs unemployment at 9.0% or more; it is 7.7% now.": the first unmet precondition.
static func _condition(ns, law) -> String:
	for c in law.preconditions:
		if Legislature.preconditions_met(ns, [c]) or not FIELD_WORDS.has(String(c["field"])):
			continue
		var what := Strings.t(String(FIELD_WORDS[String(c["field"])]))
		var want := "%s%%" % Num.f(float(c["value"]), 1)
		var now := "%s%%" % Num.f(Legislature.read_field(ns, String(c["field"])), 1)
		match String(c["op"]):
			">=", ">":
				return Strings.t("Needs %s at %s or more; it is %s now.") % [what, want, now]
			"<=", "<":
				return Strings.t("Needs %s at %s or less; it is %s now.") % [what, want, now]
	return Strings.t("Its conditions are not met yet.")
