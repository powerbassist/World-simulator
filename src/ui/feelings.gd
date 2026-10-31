extends RefCounted

## Relations shown as feelings -- V5.2 b+ R11 + Q2 (docs/design/v5.2-bplus-spec.md).
## The author: relations are feelings, not "grudge +0.17". Each word is a band over
## one register, and each cut is where the person's behaviour changes (0.45 the
## brief, 0.60 the defection, -0.40 the resignation), so a word names what the
## person may now do. A figure stays only in a tooltip (tests/test_feelings.gd
## lints src/ui for one anywhere else).
##
## The words are the spec's, as English msgids in this one table (the parent's
## call, 2026-10-24: no Content file); the cut points are the spec's own.

const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const President = preload("res://src/sim/president.gd")
const ActK = preload("res://src/sim/character_act_constants.gd")

## bands-v5.2.md, the B6 amendment: ONE comparison for every cut, the one the
## sim's bonds call too (V5.2c moved it to src/core), so a card cannot say "cold"
## while the bond says nothing.
const Cut = preload("res://src/core/cut.gd")

## Each register's bands, lowest first: [the band's upper cut, whether the band
## includes that cut, its word]. "" shows no word: no grudge, an unmoved loyalty.
const BANDS := {
	"grudge": [
		[0.05, false, ""],
		[0.20, false, "annoyed"],  # i18n: msgid
		[0.45, false, "resentful"],  # i18n: msgid
		[0.60, false, "hostile, may leak"],  # i18n: msgid
		[INF, true, "bitter, may defect"],  # i18n: msgid
	],
	"rapport": [
		[-0.30, false, "cold"],  # i18n: msgid
		[-0.05, false, "wary"],  # i18n: msgid
		# Closed at both ends: a delegation's snub (-0.05) from 0 stays neutral, so
		# only a refusal (-0.10) moves this word.
		[0.05, true, "neutral"],  # i18n: msgid
		[0.30, true, "warm"],  # i18n: msgid
		[INF, true, "close"],  # i18n: msgid
	],
	"loyalty": [
		# Closed at the floor: the premier resigns AT it (characters.gd, loyalty <=
		# the floor), so the floor itself reads as the brink. The sim's constant,
		# never a copy (the parent's call on #151).
		[ActK.LOYALTY_RESIGN_FLOOR, true, "disloyal"],  # i18n: msgid
		[-0.10, false, "uncertain"],  # i18n: msgid
		[0.10, true, ""],
		[0.40, true, "loyal"],  # i18n: msgid
		[INF, true, "devoted"],  # i18n: msgid
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
const RANGE := {"grudge": Vector2(0.0, 1.0), "rapport": Vector2(-1.0, 1.0), "loyalty": Vector2(-1.0, 1.0)}
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
	if register == "loyalty" and office and i == 0:
		return Strings.t(OFFICE_DISLOYAL)
	var said := String(BANDS[register][i][2])
	return Strings.t(said) if said != "" else ""  # i18n: row-ok a band's word, the msgid in BANDS


## The index of the band `value` falls in, lowest first -- the one cut the word
## and the mood badge (mood_badge.gd) both read, so the two cannot disagree.
static func band(register: String, value: float) -> int:
	var bands: Array = BANDS[register]
	for i in bands.size():
		var cut := float(bands[i][0])
		if Cut.at_or_below(value, cut) if bool(bands[i][1]) else Cut.below(value, cut):
			return i
	return bands.size() - 1


## Register -> word for `feel` (of() above), the bands that show none included. A
## register `feel` lacks reads 0.0, the value the sim's own reads default to.
static func words(feel: Dictionary) -> Dictionary:
	var out := {}
	for register in BANDS:
		out[register] = word(register, float(feel.get(register, 0.0)), bool(feel.get("office", false)))
	return out


## The words each register MOVED by `delta` lands in, BEFORE the act: the value
## now plus the delta, clamped as the sim clamps it.
static func landing(feel: Dictionary, delta: Dictionary) -> Dictionary:
	var out := {}
	for register in BANDS:
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
	for register in BANDS:
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


## The figure behind a word, for its tooltip only.
static func tip(value: float) -> String:
	return Num.fs(value, 2)
