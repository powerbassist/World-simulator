extends RefCounted

## What the audience's three cards and its bands say -- V5.3 (C4 and C4-refused). Words only:
## every figure is a read the sim already makes (Deal.answers, Deal.refusal_risk and
## silence_worth, the card of deal_words.gd) and nothing is computed or guessed here. A line
## is {glyph, tone, text}: a glyph that carries the sign (never colour alone), the status
## tone, a sentence. Nothing here explains the interface (the author's first ruling).

const DealK = preload("res://src/sim/deal_constants.gd")
const DateText = preload("res://src/ui/date_text.gd")
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
	# Only a SILENCE spares a brief: a vote's pledge writes no silence (Deal._strike), so the line
	# would promise what the sim does not deliver (QA #324 TAKE 2).
	var spared := risk_text(reads.get("silence", {}), true) if String(answers.get("offer", {}).get("kind", "")) == DealK.OFFER_SILENCE else ""
	if spared != "":
		grant_lines.append(line(UP, GOOD, spared))
	if ask.has("due_month"):
		grant_lines.append(line(CALENDAR, DIM, judged_on(int(ask["due_month"]))))
	if not bool(card["grant_ok"]):
		grant_lines.append(line("!", WARN, String(card["grant_why"])))
	var refuse_lines: Array = [line(DOWN, BAD, String(card["refuse"]))]
	var risk := risk_text(reads.get("refusal", {}), false)
	if risk != "":
		refuse_lines.append(line(DOWN, BAD, risk))
	return {
		"lead": "%s %s" % [String(card["want"]), String(card["give_stake"])],
		"grant": {"micro": Strings.t("Grant"), "title": _grant_title(String(ask.get("kind", ""))), "lines": grant_lines, "ok": bool(card["grant_ok"]), "why": String(card["grant_why"])},
		"counter": _counter(answers, session),
		"refuse": {"micro": Strings.t("Refuse"), "title": Strings.t("Say no"), "lines": refuse_lines, "ok": true, "why": ""},
	}


## The Counter is Deal.bargain's promise_date row: its odds shown once, its window of months.
## ONE per audience (the parent's ruling, QA #324 TAKE 1): the sim keeps the row offered while
## attempts remain, so the same counter could be rolled again at a rising chance; the session's own
## attempt list says it was made, and the cards close it. Grant and Refuse stay open.
static func _counter(answers: Dictionary, session: Dictionary) -> Dictionary:
	for row in answers.get("bargain", {}).get("approaches", []):
		if String(row["lever"]) != "promise_date":
			continue
		var lines: Array = [line(PERCENT, DIM, Strings.t("%s they agree") % Words.odds_text(float(row.get("odds_lo", 0.0)), float(row.get("odds_hi", 0.0)))),
			line(NEUTRAL, DIM, Strings.t("The same terms, judged on %s") % _first_day(int(answers.get("bargain", {}).get("due_month", 0))))]
		(lines[1] as Dictionary)["live"] = true
		var ok := bool(row.get("offered", false))
		var why := Words.reason(String(row.get("why_not", "")))
		if ok and _countered(session):
			ok = false
			why = Strings.t("You have already made your counter.")
		if not ok:
			lines.append(line("!", WARN, why))
		var dates: Dictionary = row.get("dates", {})
		return {"micro": Strings.t("Counter"), "title": Strings.t("The same word, later"), "lines": lines, "ok": ok,
			"why": why, "earliest": int(dates.get("earliest", 0)), "latest": int(dates.get("latest", 0))}
	return {}


## "Judged on 01 OCT 2026": a word is judged when its due month BEGINS -- the clock emits
## month_elapsed with the new month and Levers.tick_month takes every row with due_month <= now --
## so the card says that day, never "the end of" the month (QA #324, the real-window play).
static func judged_on(due_month: int) -> String:
	return Strings.t("Judged on %s") % _first_day(due_month)


## The Counter's own line for the date the field shows: the picked MONTH decides, the day is the
## diary's only (due_day changes nothing in the judgement).
static func counter_judged(date: Dictionary) -> String:
	return Strings.t("The same terms, judged on %s") % _first_day(int(date["year"]) * 12 + int(date["month"]))


## An absolute month (year x 12 + month) as the first day of it, in the house date.
static func _first_day(due_month: int) -> String:
	var year := floori((due_month - 1) / 12.0)
	return DateText.day_month_year(1, due_month - year * 12, year)


static func _countered(session: Dictionary) -> bool:
	for attempt in session.get("attempts", []):
		if String(attempt.get("lever", "")) == "promise_date":
			return true
	return false


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
## `spared` words what a silence keeps off you instead of what a refusal brings. One line whatever
## the count: only whether a brief comes and the first month are validated against a real run
## (test_refusal_risk's band); a count past the first is twelve frozen-clock ticks (QA #324 TAKE 3).
static func risk_text(read: Dictionary, spared: bool) -> String:
	var briefs := int(read.get("briefs", 0))
	if briefs <= 0:
		return ""
	var when_text := Strings.t("next month") if int(read.get("first_month", -1)) == 1 else Strings.t("within a year")
	var points := Num.fs(float(read.get("approval_pt", 0.0)) * (-1.0 if spared else 1.0), 1)
	if spared:
		return Strings.t("Spares you a brief %s: about %s approval") % [when_text, points]
	return Strings.t("A brief likely %s: about %s approval") % [when_text, points]


## The band under her line once the deal is struck (the sim's `struck` row on the session): what it
## gave and what it put in the Diary.
static func struck_lines(answers: Dictionary, card: Dictionary) -> Array:
	var out: Array = [line(UP, GOOD, String(card["give_stake"]))]
	var ask: Dictionary = answers.get("ask", {})
	if ask.has("due_month"):
		out.append(line(CALENDAR, DIM, Strings.t("Your word is in the Diary, judged on %s.") % _first_day(int(ask["due_month"]))))
	return out


## The money on the table: where it lands (the band's head) and its two lines, the risk and what
## taking it gives. Take is Grant plus the money (the author, 2026-11-13: "Prendre = promettre +
## argent"), so the word is stated here, not left to be found out after the click.
static func money_terms(money: Dictionary) -> String:
	return Words.offer_terms(money)


static func money_lines(money: Dictionary) -> Array:
	return [line(DOWN, BAD, money_risk(money)), line(NEUTRAL, DIM, Strings.t("Taken, they have your word, and the money"))]


## What taking it risks over the TERM (the author's ruling: not one year): the chance of being found
## before the vote that decides the office, with it taken and with it left. Without a vote on the
## clock the sim gives only the year, and that is what is said.
static func money_risk(money: Dictionary) -> String:
	var months := int(money.get("months_to_vote", -1))
	if months < 0:
		return DealWords.risk(money)
	if months == 0:
		return Strings.t("The vote is this month: nothing is found before it.")
	var taken := Num.f(float(money.get("found_by_the_vote", 0.0)) * 100.0, 0)
	var left := Num.f(float(money.get("found_by_the_vote_without", 0.0)) * 100.0, 0)
	return Strings.tn("Found before the vote, in %d month: %s %% if you take it, %s %% if you do not.", "Found before the vote, in %d months: %s %% if you take it, %s %% if you do not.", months) % [months, taken, left]


## The band after Leave: what turning the money down cost (the render's line), one fixed sentence,
## since the sim prices it in regard alone (Shadows.refuse_offer).
static func left_lines() -> Array:
	return [line(DOWN, BAD, Strings.t("They think a little less of you"))]


## The band after an affair begins: what it will cost, in the sim's two terms (evidence each month it
## lasts, Shadows.AFFAIR_EVIDENCE_PER_MONTH, and the regard lost when it ends, AFFAIR_END_RAPPORT).
static func affair_lines() -> Array:
	return [line(DOWN, BAD, Strings.t("Each month it lasts leaves a trace the press can find")), line(DOWN, BAD, Strings.t("Ending it will cost you most of their regard"))]


## The two lines the struck band adds once the money is taken: the gain and the risk it left.
static func taken_lines(money: Dictionary) -> Array:
	var months := int(money.get("months_to_vote", -1))
	var risk := Strings.t("The vote is this month: nothing is found before it.")
	if months < 0:
		risk = Strings.t("Found within a year: %s %%") % Num.f(float(money.get("found_in_a_year", 0.0)) * 100.0, 0)
	elif months > 0:
		risk = Strings.tn("Found before the vote, in %d month: %s %%", "Found before the vote, in %d months: %s %%", months) % [months, Num.f(float(money.get("found_by_the_vote", 0.0)) * 100.0, 0)]
	return [line(UP, GOOD, money_terms(money)), line(DOWN, BAD, risk)]


## The band after a refusal: what it cost, then the risk, read before the refusal.
static func refused_lines(card: Dictionary, reads: Dictionary) -> Array:
	var out: Array = [line(DOWN, BAD, String(card["refuse"]))]
	var risk := risk_text(reads.get("refusal", {}), false)
	if risk != "":
		out.append(line(DOWN, BAD, risk))
	return out
