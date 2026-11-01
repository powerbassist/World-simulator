extends RefCounted

## V5.3 a + b, band B7 (docs/design/v5.3-ab.md section 7): what counts as a
## MEANINGFUL DECISION ARRIVAL, and the band over a run. The rule only: the probe
## (`decision_surfaces_probe.gd --density`) builds each decision's answers as
## effects strips from the sim's own numbers and hands them here; this file never
## reads a game state, so tests/test_density_count.gd pins it on fixtures.
##
## A STRIP is one answer's effects, as the spec's strip (2.1) would print them:
##   money_bn   the public balance, EUR bn a year, signed;
##   debt_bn    a one-off price on the debt (a capital transaction), signed;
##   approval   the estimated move in overall approval, points;
##   arrows     bloc -> arrow grade (arrow() below; 0 is no arrow);
##   feel       "person|register" -> the feeling band index the answer lands in;
##   division   a division's outcome, stage a process stage (none exist on main);
##   other      channel -> value for what the strip does not print (a society
##              term, a sector's regulation burden): never counted, reported.
## A key that is absent reads as unmoved.

const BriefingEffects = preload("res://src/ui/briefing_effects.gd")

## Section 7 item 2's thresholds.
const MONEY_BN := 0.5
const APPROVAL_PT := 0.5
## Section 7 item 3: a subject counted is not counted again for this many months
## unless its state changed. "Within 3 months" reads inclusive: counted at t, the
## same subject in the same state is a repeat at t+1, t+2 and t+3, and counts at t+4.
const REPEAT_MONTHS := 3
## The band (section 7, the author's "Une par mois"): every month at least one,
## a mean of at least 2, at most 6 a month, at least 3 domains a quarter.
const BAND_SHARE := 1.0
const BAND_MEAN := 2.0
const BAND_MAX := 6
const BAND_DOMAINS := 3
const QUARTER := 3

const AXES := ["money", "approval", "arrow", "feeling", "division", "stage"]


## A bloc offset's arrow, on the briefing's own word bands (briefing_effects.gd):
## under OFFSET_SLIGHT no arrow, then one, from OFFSET_CLEAR two ("business ↓↓").
static func arrow(offset: float) -> int:
	var size := absf(offset)
	if size < float(BriefingEffects.OFFSET_SLIGHT):
		return 0
	var grade := 1 if size < float(BriefingEffects.OFFSET_CLEAR) else 2
	return grade if offset > 0.0 else -grade


## The spec axes on which two strips differ, in AXES order.
static func differs(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	if absf(float(a.get("money_bn", 0.0)) - float(b.get("money_bn", 0.0))) >= MONEY_BN \
			or absf(float(a.get("debt_bn", 0.0)) - float(b.get("debt_bn", 0.0))) >= MONEY_BN:
		out.append("money")
	if absf(float(a.get("approval", 0.0)) - float(b.get("approval", 0.0))) >= APPROVAL_PT:
		out.append("approval")
	if _keyed_differ(a.get("arrows", {}), b.get("arrows", {}), 0):
		out.append("arrow")
	if _feel_differ(a.get("feel", {}), b.get("feel", {})):
		out.append("feeling")
	if String(a.get("division", "")) != String(b.get("division", "")):
		out.append("division")
	if String(a.get("stage", "")) != String(b.get("stage", "")):
		out.append("stage")
	return out


## The channels outside the strip on which two strips differ, sorted.
static func other_differs(a: Dictionary, b: Dictionary) -> Array:
	var oa: Dictionary = a.get("other", {})
	var ob: Dictionary = b.get("other", {})
	var out: Array = []
	for key in oa.keys() + ob.keys():
		if out.has(key):
			continue
		if absf(float(oa.get(key, 0.0)) - float(ob.get(key, 0.0))) > 1e-9:
			out.append(key)
	out.sort()
	return out


## Section 7 items 1 and 2: at least two answers, and two of them differ on an axis.
static func meaningful(answers: Array) -> bool:
	for i in answers.size():
		for j in range(i + 1, answers.size()):
			if not differs(answers[i], answers[j]).is_empty():
				return true
	return false


## For a decision that is NOT meaningful: the outside channels on which its
## answers differ -- the axis that would have counted it. Empty when it counts.
static func saved_by(answers: Array) -> Array:
	if meaningful(answers):
		return []
	var out: Array = []
	for i in answers.size():
		for j in range(i + 1, answers.size()):
			for key in other_differs(answers[i], answers[j]):
				if not out.has(key):
					out.append(key)
	out.sort()
	return out


## One month: each candidate is {source, subject, state, domain, due ("arrival" or
## "deadline"), answers: [strip]}. Returns the candidates sorted three ways --
## `counted`, `dull` (not meaningful) and `repeat` (section 7 item 3) -- and
## records every counted one in `memory` (subject -> {now, state}). A dull offer is
## not remembered: it never blocks a later, meaningful one.
static func month(candidates: Array, memory: Dictionary, now: int) -> Dictionary:
	var out := {"counted": [], "dull": [], "repeat": []}
	for c in candidates:
		if not meaningful(c["answers"]):
			out["dull"].append(c)
			continue
		var subject := String(c["subject"])
		var seen: Dictionary = memory.get(subject, {})
		if not seen.is_empty() and now - int(seen["now"]) <= REPEAT_MONTHS \
				and String(seen["state"]) == String(c.get("state", "")):
			out["repeat"].append(c)
			continue
		memory[subject] = {"now": now, "state": String(c.get("state", ""))}
		out["counted"].append(c)
	return out


## The band over a run. `months` is one entry per month run, in order:
## {now, count, domains}. Quarters are blocks of three months from the run's
## start; a partial last quarter (a defeat ends a run) is judged on what it has.
static func summary(months: Array) -> Dictionary:
	var n := months.size()
	var total := 0
	var with_one := 0
	var most := 0
	var run := 0
	var longest := 0
	var over := 0
	var quarters := 0
	var quarters_ok := 0
	var domains := {}
	for i in n:
		var count := int(months[i]["count"])
		total += count
		most = maxi(most, count)
		if count > BAND_MAX:
			over += 1
		if count > 0:
			with_one += 1
			run = 0
		else:
			run += 1
			longest = maxi(longest, run)
		for d in months[i]["domains"]:
			domains[String(d)] = true
		if i % QUARTER == QUARTER - 1 or i == n - 1:
			quarters += 1
			if domains.size() >= BAND_DOMAINS:
				quarters_ok += 1
			domains = {}
	var share := float(with_one) / maxf(float(n), 1.0)
	var mean := float(total) / maxf(float(n), 1.0)
	return {
		"months": n, "with_one": with_one, "share": share, "mean": mean, "max": most,
		"longest_none": longest, "over_max": over, "quarters": quarters, "quarters_ok": quarters_ok,
		"pass": n > 0 and share >= BAND_SHARE and mean >= BAND_MEAN and over == 0 and quarters_ok == quarters,
	}


static func _keyed_differ(a: Dictionary, b: Dictionary, absent: int) -> bool:
	for key in a.keys() + b.keys():
		if int(a.get(key, absent)) != int(b.get(key, absent)):
			return true
	return false


## A register present on one side only is unmoved on the other, so it is compared
## only where both sides carry it: a band index has no "absent" value of its own.
static func _feel_differ(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if b.has(key) and int(a[key]) != int(b[key]):
			return true
	return false
