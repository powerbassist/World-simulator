extends RefCounted

## What the audience's three cards and its bands say -- V5.3 (C4 and C4-refused). Words only:
## every figure is a read the sim already makes (Deal.answers, Deal.refusal_risk and
## silence_worth, the card of deal_words.gd) and nothing is computed or guessed here. A line
## is {glyph, tone, text}: a glyph that carries the sign (never colour alone), the status
## tone, a sentence. Nothing here explains the interface (the author's first ruling).

const DealWords = preload("res://src/ui/deal_words.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")
const Words = preload("res://src/ui/lever_words.gd")

const UP := "▲"  # i18n: ok a glyph
const DOWN := "▼"  # i18n: ok a glyph
const NEUTRAL := "="  # i18n: ok a glyph
const PERCENT := "%"  # i18n: ok a glyph
const CALENDAR := "event"  # i18n: ok an icon file stem
const GOOD := "good"  # i18n: ok a tone key
const BAD := "bad"  # i18n: ok a tone key
const WARN := "warn"  # i18n: ok a tone key
const DIM := ""  # i18n: ok a tone key


static func line(glyph: String, tone: String, text: String) -> Dictionary:
	return {"glyph": glyph, "tone": tone, "text": text}


## The question: {lead, grant, counter, refuse}, each card {micro, title, lines, ok, why}, and
## the counter's {earliest, latest} months and its one row. `counter` is {} for an ask that has
## no date to move (a post, a plant): two cards, the same rule.
static func question(loader, ns, session: Dictionary, answers: Dictionary, feel: Dictionary, wants: String, kind: String, reads: Dictionary) -> Dictionary:
	var card := DealWords.card(loader, ns, answers, feel, wants, kind)
	var ask: Dictionary = answers.get("ask", {})
	var grant_lines: Array = [line(DOWN, BAD, String(card["grant_cost"]))] if String(card["grant_cost"]) != "" else []
	grant_lines.append(line(UP, GOOD, String(card["give_stake"])))
	var spared := risk_text(reads.get("silence", {}), true)
	if spared != "":
		grant_lines.append(line(UP, GOOD, spared))
	if ask.has("due_month"):
		grant_lines.append(line(CALENDAR, DIM, Strings.t("Judged at the end of %s") % Words.when(int(ask["due_month"]))))
	if not bool(card["grant_ok"]):
		grant_lines.append(line("!", WARN, String(card["grant_why"])))
	var refuse_lines: Array = [line(DOWN, BAD, String(card["refuse"]))]
	var risk := risk_text(reads.get("refusal", {}), false)
	if risk != "":
		refuse_lines.append(line(DOWN, BAD, risk))
	return {
		"lead": "%s %s" % [String(card["want"]), String(card["give_stake"])],
		"grant": {"micro": Strings.t("Grant"), "title": _grant_title(String(ask.get("kind", ""))), "lines": grant_lines, "ok": bool(card["grant_ok"]), "why": String(card["grant_why"])},
		"counter": _counter(answers),
		"refuse": {"micro": Strings.t("Refuse"), "title": Strings.t("Say no"), "lines": refuse_lines, "ok": true, "why": ""},
	}


## The Counter is Deal.bargain's promise_date row: its odds shown once, its window of months.
static func _counter(answers: Dictionary) -> Dictionary:
	for row in answers.get("bargain", {}).get("approaches", []):
		if String(row["lever"]) != "promise_date":
			continue
		var lines: Array = [line(PERCENT, DIM, Strings.t("%s they agree") % Words.odds_text(float(row.get("odds_lo", 0.0)), float(row.get("odds_hi", 0.0)))),
			line(NEUTRAL, DIM, Strings.t("The same terms, judged at the end of the month you pick"))]
		var ok := bool(row.get("offered", false))
		if not ok:
			lines.append(line("!", WARN, Words.reason(String(row.get("why_not", "")))))
		var dates: Dictionary = row.get("dates", {})
		return {"micro": Strings.t("Counter"), "title": Strings.t("The same word, later"), "lines": lines, "ok": ok,
			"why": Words.reason(String(row.get("why_not", ""))), "earliest": int(dates.get("earliest", 0)), "latest": int(dates.get("latest", 0))}
	return {}


static func _grant_title(kind: String) -> String:
	match kind:
		"post":
			return Strings.t("Give them the post")
		"firm":
			return Strings.t("Rescue the plant")
		"law":
			return Strings.t("Bring it forward")
	return Strings.t("Give your word")


## "A brief likely within a year: about -0.6 approval", or "" when the read expects none.
## `spared` words what a silence keeps off you instead of what a refusal brings.
static func risk_text(read: Dictionary, spared: bool) -> String:
	var briefs := int(read.get("briefs", 0))
	if briefs <= 0:
		return ""
	var when_text := Strings.t("next month") if int(read.get("first_month", -1)) == 1 else Strings.t("within a year")
	var points := Num.fs(float(read.get("approval_pt", 0.0)) * (-1.0 if spared else 1.0), 1)
	if spared:
		return Strings.t("Spares you a brief %s: about %s approval") % [when_text, points] if briefs == 1 \
			else Strings.t("Spares you %d briefs %s: about %s approval each") % [briefs, when_text, points]
	return Strings.t("A brief likely %s: about %s approval") % [when_text, points] if briefs == 1 \
		else Strings.t("%d briefs likely %s: about %s approval each") % [briefs, when_text, points]


## The band under her line once the deal is struck (the sim's `struck` row on the session): what it
## gave and what it put in the Diary.
static func struck_lines(answers: Dictionary, card: Dictionary) -> Array:
	var out: Array = [line(UP, GOOD, String(card["give_stake"]))]
	var ask: Dictionary = answers.get("ask", {})
	if ask.has("due_month"):
		out.append(line(CALENDAR, DIM, Strings.t("Your word is in the Diary, judged at the end of %s.") % Words.when(int(ask["due_month"]))))
	return out


## The band after a refusal: what it cost, then the risk, read before the refusal.
static func refused_lines(card: Dictionary, reads: Dictionary) -> Array:
	var out: Array = [line(DOWN, BAD, String(card["refuse"]))]
	var risk := risk_text(reads.get("refusal", {}), false)
	if risk != "":
		out.append(line(DOWN, BAD, risk))
	return out
