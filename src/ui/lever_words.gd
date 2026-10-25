extends RefCounted

## The audience's words -- V5.2b b2. Every number the levers hand back (a range, a
## spend, what a try wrote, a promise's verdict) said as the player reads it, in
## one place: the scene, its wiring and the Diary call these, so a spend cannot
## read one way on the lever and another once paid.
##
## The numbers are the sim's (src/sim/levers.gd); this file only words them. A
## reason the sim gives (`why_not`, `error`) is already English and is shown
## through `Strings.t()`, its English the msgid.

const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Feelings = preload("res://src/ui/feelings.gd")

const LEVER_LABEL := {
	"argue": "Argue", "bargain": "Bargain", "promise_date": "Promise a date",  # i18n: msgid
	"pressure": "Pressure", "flatter": "Flatter", "friendship": "Appeal to friendship",  # i18n: msgid
}
const TOPIC_LABEL := {
	"family": "Family", "opinion": "Their opinion", "gossip": "Gossip",  # i18n: msgid
	"dinner": "Dinner", "flirt": "Flirt",  # i18n: msgid
}
const CURRENCY_LABEL := {
	"favour": "A favour", "vote_trade": "A vote trade",  # i18n: msgid
	"backroom": "A backroom favour", "aid": "Diverted aid",  # i18n: msgid
}
## V5.2c: the shadows answer with a reason KEY (src/sim/shadows.gd), every other
## lever with an English sentence; a key is said as its sentence here.
const SHADOW_REASON := {
	"not_covered": "You have no standing with them for that.",  # i18n: msgid
	"unmarried": "You have no spouse to deceive: an affair needs a marriage to hide from.",  # i18n: msgid
	"spouse": "This is your own spouse.",  # i18n: msgid
	"already": "You are already lovers.",  # i18n: msgid
	"too_cold": "They are not close enough to you for that.",  # i18n: msgid
	"no_spark": "There is no spark between you.",  # i18n: msgid
	"not_affair": "There is no affair to end.",  # i18n: msgid
}
## The fog the scene assumes when the sim names none: the widest.
const FOG_DEFAULT := "stranger"
const FOG_LABEL := {
	"stranger": "a stranger -- the odds are a wide guess",  # i18n: msgid
	"acquaintance": "an acquaintance -- the odds are a rough guess",  # i18n: msgid
	"known": "known to you -- the odds are close",  # i18n: msgid
}
const OUTCOME := {
	"settled": "They leave satisfied: the request is settled.",  # i18n: msgid
	"promised": "They leave with your word: the request rests on your promise.",  # i18n: msgid
	"declined": "They leave unmoved: it counts as a refusal.",  # i18n: msgid
}


static func lever(id: String) -> String:
	return Strings.t(String(LEVER_LABEL.get(id, id)))  # i18n: row-ok a lever id, its label the msgid


static func topic(id: String) -> String:
	return Strings.t(String(TOPIC_LABEL.get(id, id)))  # i18n: row-ok a topic id, its label the msgid


static func currency(id: String) -> String:
	return Strings.t(String(CURRENCY_LABEL.get(id, id)))  # i18n: row-ok a currency id, its label the msgid


static func fog(band: String) -> String:
	return Strings.t("They are %s.") % Strings.t(String(FOG_LABEL.get(band, FOG_LABEL[FOG_DEFAULT])))


## The sim's own reason, as shown.
static func reason(why: String) -> String:
	return Strings.t(String(SHADOW_REASON.get(why, why))) if why != "" else ""  # i18n: row-ok the sim's reason, its English the msgid


## A range, never a point: what the president cannot know about the person is the
## width (B4). Text tokens only -- odds are no good or bad news.
static func odds_text(lo: float, hi: float) -> String:
	return Strings.t("%s–%s %%") % [Num.f(lo * 100.0, 0), Num.f(hi * 100.0, 0)]


## An absolute month (year x 12 + month) as the Diary writes one.
static func when(absolute: int) -> String:
	var year := floori((absolute - 1) / 12.0)
	return DateText.month_year(absolute - year * 12, year)


## What a lever will cost, BEFORE the click: Levers' `spends` row (register ->
## amount; a commitment and a bond step are counts), a register's in the word it
## lands in (R11) from `feel`, Feelings.of() the person. `due` names the promise's
## date once one is picked.
static func spends_text(spends: Dictionary, feel: Dictionary, due := -1) -> String:
	var parts := Feelings.promised(feel, spends)
	if spends.has("iou"):
		parts.append(Strings.tn("an IOU: their vote, owed back in %d month", "an IOU: their vote, owed back in %d months", LK.IOU_MONTHS) % LK.IOU_MONTHS)
	if spends.has("promise"):
		parts.append(Strings.t("your word, due %s; it binds even if they doubt it") % when(due) if due > 0 else Strings.t("your word, at a date; it binds even if they doubt it"))
	if spends.has("bond"):
		parts.append(Strings.t("your bond, a step looser"))
	# V5.2c: a corrupt currency is paid in evidence -- nothing now, a scandal if found.
	if spends.has("evidence"):
		parts.append(Strings.t("nothing on the books, but it leaves evidence that can be found"))
	return "; ".join(parts) if not parts.is_empty() else Strings.t("costs nothing")


## What a try wrote, AFTER it: the attempt's `spent` (an IOU's and a promise's
## value is the month due) and `effects`, the deltas the registers took -- each
## register they moved in the word it now reads, off `feel` (Feelings.of() the
## person after the try).
static func paid_text(spent: Dictionary, effects: Dictionary, name_of: Callable, feel: Dictionary) -> String:
	# The larger write, never the sum: a spend and an effect of opposite signs both
	# happened, and the word after names where they left the person.
	var moved := {}
	for register in Feelings.BANDS:
		var a := float(spent.get(register, 0.0))
		var b := float(effects.get(register, 0.0))
		moved[register] = a if absf(a) >= absf(b) else b
	var parts := Feelings.stands(feel, moved)
	if spent.has("iou"):
		parts.append(Strings.t("you owe them a vote by %s") % when(int(spent["iou"])))
	if spent.has("promise"):
		parts.append(Strings.t("your word given, due %s") % when(int(spent["promise"])))
	if spent.has("bond"):
		parts.append(Strings.t("your bond is looser"))
	if spent.has("evidence"):
		parts.append(Strings.t("you left evidence behind"))
	# The offer's money (Shadows.accept_offer's `paid`): a figure, money being no feeling.
	if spent.has("wealth_eur_m"):
		parts.append(offer_terms({"currency": "personal_wealth", "amount_eur_m": spent["wealth_eur_m"]}))
	if spent.has("party_money_eur_m"):
		parts.append(offer_terms({"currency": "party_money", "amount_eur_m": spent["party_money_eur_m"]}))
	if absf(float(effects.get("knowledge", 0.0))) >= 0.005:
		parts.append(Strings.t("you know them better (%s)") % Num.fs(float(effects["knowledge"]), 2))
	var of: Dictionary = effects.get("knowledge_of", {})
	for id in of.keys():
		parts.append(Strings.t("you learn about %s (%s)") % [String(name_of.call(String(id))), Num.fs(float(of[id]), 2)])
	return "; ".join(parts)


## An offer's money and where it goes (Offers' {currency, amount_eur_m}), the same
## words on the table and once taken.
static func offer_terms(offer: Dictionary) -> String:
	var amount := Num.f(float(offer.get("amount_eur_m", 0.0)), 1)
	if String(offer.get("currency", "")) == "party_money":
		return Strings.t("€%s m to your party's accounts") % amount
	return Strings.t("€%s m to you, off the books") % amount


## What a lie costs if it is caught (Lies.reveal's price), in the words it would
## leave the person in: before the click, on the toggle. A promise told as a lie
## is found out at its date whatever happens (Levers._judge, B8), so its price is
## certain, not a risk.
static func lie_text(feel: Dictionary, lever := "argue") -> String:
	var parts := Feelings.promised(feel, {"rapport": -LK.LIE_RAPPORT, "grudge": LK.LIE_GRUDGE})
	parts.append(Strings.t("they trust what they know of you less"))
	if lever == "promise_date":
		return Strings.t("A lie: better odds. They find it out on the day, if not before: %s.") % ", ".join(parts)
	return Strings.t("A lie: better odds. If they catch it: %s.") % ", ".join(parts)


## What saying no writes on the person, the parts that move only, in the words
## they land in (R11): `feel` is Feelings.of() the person -- BEFORE the answer for
## the card's promise, AFTER it (`paid`) for what was told, the same words.
static func price_text(price: Dictionary, feel: Dictionary, paid := false) -> String:
	var parts := Feelings.stands(feel, price) if paid else Feelings.promised(feel, price)
	return ", ".join(parts) if not parts.is_empty() else Strings.t("nothing")


## What a try changed, as a sentence of its own.
static func changed(parts: String) -> String:
	return Strings.t("What changed: %s.") % parts if parts != "" else ""


static func outcome(id: String) -> String:
	return Strings.t(String(OUTCOME.get(id, OUTCOME["declined"])))  # i18n: row-ok an outcome id, its sentence the msgid


## A commitment in the Diary: to whom, by when, on which of their wants.
static func commitment_text(kind: String, person: String, want: String, due: int) -> String:
	if kind == "iou":
		return Strings.t("You owe %s a vote by %s (their want: %s).") % [person, when(due), want]
	# A delegated request is a minister's word, not the president's: broken, it is
	# a betrayal and never a lie (levers.gd _judge; bands-v5.2.md).
	if kind == "delegated":
		return Strings.t("Delegated to a minister for %s, due %s (their want: %s).") % [person, when(due), want]
	return Strings.t("Your word to %s, due %s (their want: %s).") % [person, when(due), want]


## A judged one: kept, or a lie revealed (a promise) / a betrayal (an IOU, or a
## delegation the minister did not deliver).
static func verdict_text(kind: String, kept: bool, person: String, want: String) -> String:
	if kind == "iou":
		return Strings.t("You paid %s the vote you owed.") % person if kept else Strings.t("You did not pay %s the vote you owed: a betrayal.") % person
	if kind == "delegated":
		return Strings.t("Your minister delivered for %s (their want: %s).") % [person, want] if kept else Strings.t("Your minister failed %s: a betrayal (their want: %s).") % [person, want]
	return Strings.t("You kept your word to %s (their want: %s).") % [person, want] if kept else Strings.t("Your word to %s is revealed a lie (their want: %s).") % [person, want]
