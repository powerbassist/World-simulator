extends RefCounted

## Relations shown as feelings -- V5.2 b+ R11 + Q2 (docs/design/v5.2-bplus-spec.md).
## The author: relations are feelings, not "grudge +0.17". Each word is a band over
## one register, and each cut is where the person's behaviour changes (0.45 the
## brief, 0.60 the defection, -0.40 the resignation), so a word names what the
## person may now do. A figure stays only in a tooltip (tests/test_feelings.gd
## lints src/ui for one anywhere else), but for the person card's rapport and loyalty,
## which carry figure() beside the word (the author, 2026-11-08).
##
## The words are the spec's, as English msgids in this one table (the parent's
## call, 2026-10-24: no Content file); the cut points are the spec's own.

const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const President = preload("res://src/sim/president.gd")
## The cuts are the sim's (V5.3 B7, the author's ruling of 2026-11-10): the quiet-month
## call judges whether a request's answers land in different words with the same
## cuts this file draws them with (src/sim/feeling_constants.gd).
const FK = preload("res://src/sim/feeling_constants.gd")

## Each register's words, lowest band first, one per FK.CUTS band (the same index).
## "" shows no word: no grudge, an unmoved loyalty.
const WORDS := {
	"grudge": [
		"",
		"annoyed",  # i18n: msgid
		"resentful",  # i18n: msgid
		"hostile, may leak",  # i18n: msgid
		"bitter, may defect",  # i18n: msgid
	],
	"rapport": [
		"cold",  # i18n: msgid
		"wary",  # i18n: msgid
		"neutral",  # i18n: msgid
		"warm",  # i18n: msgid
		"close",  # i18n: msgid
	],
	"loyalty": [
		"disloyal",  # i18n: msgid
		"uncertain",  # i18n: msgid
		"",
		"loyal",  # i18n: msgid
		"devoted",  # i18n: msgid
	],
}
## The resign act covers only an office holder (characters.gd, _office_held), so
## only there does the lowest loyalty promise it.
const OFFICE_DISLOYAL := "ready to resign"  # i18n: msgid
## V5.2c: the bond the sim writes (President's BONDS), as the person card names it.
const BOND := {
	"friend": "a friend", "close": "close to you", "rival": "a rival, may talk",  # i18n: msgid
	"enemy": "an enemy, may talk", "affair": "your lover, in secret",  # i18n: msgid
}
const RANGE: Dictionary = FK.RANGE
## A delta under this moved nothing a player should read (QA on #105: "loyalty
## +0.00" was noise on a card).
const MOVED := 0.005


## The three registers of one person, as the president's term has left them, and
## whether they hold the office the resign act reads (the premiership, as
## characters.gd's _office_held has it).
static func of(ns, pid: String) -> Dictionary:
	return {
		"grudge": float(ns.person_grudges.get(pid, 0.0)),
		"rapport": President.rapport(ns, pid),
		"loyalty": float(ns.person_loyalty.get(pid, 0.0)),
		"office": String(ns.pm_person_id) == pid,
	}


## The bond's word, translated; "" for none (a stranger or an acquaintance, which
## the card's fog already says).
static func bond_word(bond: String) -> String:
	return Strings.t(String(BOND[bond])) if BOND.has(bond) else ""  # i18n: row-ok a bond id, its word the msgid


## The word a register's value reads as, translated; "" for a band with none.
static func word(register: String, value: float, office := false) -> String:
	var i := band(register, value)
	if i < 0:
		return ""
	if register == "loyalty" and office and i == 0:
		return Strings.t(OFFICE_DISLOYAL)
	var said := String(WORDS[register][i])
	return Strings.t(said) if said != "" else ""  # i18n: row-ok a band's word, the msgid in WORDS


## The index of the band `value` falls in, lowest first -- the one cut the word
## and the mood badge (mood_badge.gd) both read, so the two cannot disagree.
## Above every cut (NaN) it is -1: no word, as word() always had it.
static func band(register: String, value: float) -> int:
	return FK.band(register, value)


## Register -> word for `feel` (of() above), the bands that show none included. A
## register `feel` lacks reads 0.0, the value the sim's own reads default to.
static func words(feel: Dictionary) -> Dictionary:
	var out := {}
	for register in WORDS:
		out[register] = word(register, float(feel.get(register, 0.0)), bool(feel.get("office", false)))
	return out


## The words each register MOVED by `delta` lands in, BEFORE the act: the value
## now plus the delta, clamped as the sim clamps it.
static func landing(feel: Dictionary, delta: Dictionary) -> Dictionary:
	var out := {}
	for register in WORDS:
		if absf(float(delta.get(register, 0.0))) < MOVED:
			continue
		var r: Vector2 = RANGE[register]
		out[register] = word(register, clampf(float(feel.get(register, 0.0)) + float(delta[register]), r.x, r.y), bool(feel.get("office", false)))
	return out


## Before the act, a clause a moved register: "they will be annoyed", "rapport
## turns wary" -- what the card promises.
static func promised(feel: Dictionary, delta: Dictionary) -> PackedStringArray:
	var now := words(feel)
	var to := landing(feel, delta)
	var out := PackedStringArray()
	if to.has("grudge"):
		out.append(Strings.t("they will be %s") % to["grudge"] if to["grudge"] != "" else Strings.t("a grudge too slight to show"))
	if to.has("rapport"):
		out.append(Strings.t("rapport turns %s") % to["rapport"] if to["rapport"] != now["rapport"] else Strings.t("rapport stays %s") % to["rapport"])
	if to.has("loyalty"):
		out.append(Strings.t("their loyalty turns %s") % to["loyalty"] if to["loyalty"] != "" else Strings.t("a shift in loyalty too slight to show"))
	return out


## After the act, a clause a register `delta` moved, read off `feel` as it now
## stands -- the same words promised() named, where the sim paid what it priced.
static func stands(feel: Dictionary, delta: Dictionary) -> PackedStringArray:
	var now := words(feel)
	var out := PackedStringArray()
	for register in WORDS:
		if absf(float(delta.get(register, 0.0))) < MOVED:
			continue
		match register:
			"grudge":
				out.append(Strings.t("they are %s") % now["grudge"] if now["grudge"] != "" else Strings.t("a grudge too slight to show"))
			"rapport":
				out.append(Strings.t("rapport is now %s") % now["rapport"])
			"loyalty":
				out.append(Strings.t("their loyalty is now %s") % now["loyalty"] if now["loyalty"] != "" else Strings.t("a shift in loyalty too slight to show"))
	return out


## A person's relation to the president as the player reads it: a whole number from -100 to
## +100 (the author, 2026-11-08). The one place the register's -1 to +1 is turned into one.
static func figure(value: float) -> String:
	var whole := roundi(100.0 * value)
	return Num.f(0.0, 0) if whole == 0 else Num.fs(float(whole), 0)


## The figure behind a word, for its tooltip only: a grudge, which runs 0 to 1 and is no relation.
static func tip(value: float) -> String:
	return Num.fs(value, 2)
