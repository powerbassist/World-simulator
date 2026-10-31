extends RefCounted

## "What your choices did" -- V5.3-0, docs/design/v5.3-0-readability.md 2.5, band RF5.
##
## The honest rule: a line says what a choice did only when a register BOOKED that
## number as that choice's own effect -- a law's channels for the passage stamped
## this month (law_ledger), a commitment judged this month, a request lapsed this
## month. Everything else is a national figure's movement since the month's
## decisions, and is UNCERTAIN: shown in grey with the word, never in GOOD or BAD,
## because effects_ledger.gd's own rule holds (QA on #69: a month's decisions cannot
## be told apart in a month's numbers). The author's call 7: "Montrer l'incertain en
## gris".
##
## A booked line speaks the register's own terms: a bloc's offset as a direction
## and a size word (gate b R11: "human relations are feelings, not grudge plus or
## minus 0.17"), the figure in its tooltip; a tax or spending channel as its points.

const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const Trends = preload("res://src/ui/trends.gd")
const EffectsLedger = preload("res://src/ui/effects_ledger.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const AudienceK = preload("res://src/sim/audience_constants.gd")

const MAX_LINES := 3
## Decisions named on the "Decided last month" line before "and N more".
const DECIDED_NAMED := 2
## A bloc offset's size word: under the first cut "slightly", under the second
## nothing, beyond it "clearly". Offsets live in [-1, 1].
const OFFSET_SLIGHT := 0.05
const OFFSET_CLEAR := 0.15
## The sparkline's reach back into history.
const SPARK_MONTHS := 12


## Up to three lines {text, tone, uncertain, spark, tooltip}: booked first, then
## uncertain; with none booked, what was decided (or "Nothing you decided") and
## the month's biggest movement. `report` is the month's report (its lapsed requests), {} when absent.
static func lines(state, loader, report: Dictionary) -> Array:
	var ns = state.player()
	var now := int(state.year) * 12 + int(state.month)
	var out: Array = []
	_laws(ns, loader, now, out)
	for row in ns.commitments_judged:
		if int(row.get("judged_month", -1)) == now and String(row.get("verdict", "")) != "void":
			var kept := String(row["verdict"]) == "kept"
			var who: String = loader.person_name(String(row.get("person_id", "")))
			out.append(_booked(Strings.t("Your word to %s: kept") % who if kept else Strings.t("Your word to %s: broken") % who,
				ResultTone.GOOD if kept else ResultTone.BAD))
	var lapsed: Array = (report.get("audience_requests", {}) as Dictionary).get("lapsed", [])
	if not lapsed.is_empty():
		out.append(_booked(Strings.tn("%d request lapsed: taken as a refusal", "%d requests lapsed: taken as a refusal",
			lapsed.size()) % lapsed.size(), ResultTone.BAD))
	var lost := _defeat(ns, loader, report.get("division", {}))
	if not lost.is_empty():
		out.append(lost)
	var booked := not out.is_empty()
	if not booked:
		out.append(_decided(state, now))
	for m in _movements(state, now):
		if out.size() >= MAX_LINES or (not booked and out.size() >= 2):
			break
		out.append(_uncertain(state, m))
	return out.slice(0, MAX_LINES)


static func _laws(ns, loader, now: int, out: Array) -> void:
	for law_id in ns.law_ledger:
		var entry: Dictionary = ns.law_ledger[law_id]
		if not (entry.get("months", []) as Array).has(now):
			continue
		var name := PriorityWords._law(ns, loader, String(law_id))
		var channels: Dictionary = entry.get("channels", {})
		var parts: PackedStringArray = []
		var tips: PackedStringArray = []
		var offsets: Dictionary = channels.get("bloc_offset", {})
		var blocs := offsets.keys()
		blocs.sort_custom(func(a, b): return absf(float(offsets[a])) > absf(float(offsets[b])))
		for bloc in blocs.slice(0, 2):
			var d := float(offsets[bloc])
			parts.append(_offset_words(String(bloc), d))
			tips.append("%s %s" % [Labels.bloc(String(bloc)), Num.fs(d, 2)])
		for tax in (channels.get("tax_rates_pct", {}) as Dictionary):
			parts.append(Strings.t("%s tax %s pt") % [Labels.tax(String(tax)), Num.fs(float(channels["tax_rates_pct"][tax]), 1)])
		var text := Strings.t("%s passed") % name if parts.is_empty() else Strings.t("%s passed: %s") % [name, ", ".join(parts.slice(0, 2))]
		# No tone: a passage is booked, but whether it was in the player's favour is
		# the bill's own question (an assembly's bill passes too).
		var line := _booked(text, "")
		line["tooltip"] = ", ".join(tips)
		out.append(line)


## Pre-gate B4: the tabled bill divides at the boundary the card opens on, so its
## result is known: a defeat is booked with its count. A division that settled
## nothing yet (refused, held by the second chamber, sent to the country) or ended
## past the Assembly (blocked above it, struck down) books no defeat here; a
## carried one is its law_ledger passage, above.
static func _defeat(ns, loader, result: Dictionary) -> Dictionary:
	if result.is_empty() or bool(result.get("passed", false)):
		return {}
	for unsettled in ["refused", "held_by_upper", "referendum_called", "blocked_by_upper", "struck_down"]:
		if bool(result.get(unsettled, false)):
			return {}
	var name := PriorityWords._law(ns, loader, String(result.get("law_id", "")))
	return _booked(Strings.t("%s defeated, %d to %d") % [name, int(result.get("yes_seats", 0)), int(result.get("no_seats", 0))],
		ResultTone.BAD)


## Requests the player answered last month by a command of their own: delegated,
## declined, or booked (acted_month) -- each a decision with no number of its own.
## Never an outcome: an audience held last month was the booking's, made months
## before, and a lapse or an agreement closed at the tick is the sim's (the
## parent's TAKE 1 on #230). Last month, since the card opens on the month after:
## the sim stamps a request with the month its command ran.
static func _answered(ns, now: int) -> int:
	var n := 0
	for row in ns.audience_requests:
		var resolved := int(row.get("resolved_month", -1)) == now - 1 \
			and [AudienceK.STATUS_DELEGATED, AudienceK.STATUS_DECLINED].has(String(row.get("status", "")))
		if resolved or int(row.get("acted_month", -1)) == now - 1:
			n += 1
	return n


## "workers clearly for", "business slightly against".
## With nothing booked, what was decided: the month's recent_effects entry names it
## (main._queue_effect queues every command), and its effect is UNCERTAIN -- QA's
## RF5 TAKE on #218: "Nothing you decided" printed after real decisions. Only a
## month with no entry is a month the player decided nothing.
static func _decided(state, now: int) -> Dictionary:
	var effect: Dictionary = {} if state.recent_effects.is_empty() else state.recent_effects[0]
	if not effect.is_empty() and int(effect.get("year", 0)) * 12 + int(effect.get("month", 0)) != now:
		effect = {}
	var answered := _answered(state.player(), now)
	if effect.is_empty() and answered == 0:
		return {"text": Strings.t("Nothing you decided last month"), "tone": "", "uncertain": false,
			"spark": PackedFloat64Array(), "tooltip": ""}
	var names: PackedStringArray = String(effect.get("label", "")).split("; ", false)  # i18n: row-ok effects' labels, routed when queued
	if answered > 0:
		names.append(Strings.tn("%d request answered", "%d requests answered", answered) % answered)
	var text := Strings.t("Decided last month: %s") % ", ".join(names.slice(0, DECIDED_NAMED))
	if names.size() > DECIDED_NAMED:
		var more := names.size() - DECIDED_NAMED
		text = Strings.tn("Decided last month: %s and %d more", "Decided last month: %s and %d more", more) % [", ".join(names.slice(0, DECIDED_NAMED)), more]
	return {"text": text, "tone": "", "uncertain": true, "spark": PackedFloat64Array(),
		"tooltip": Strings.t("A month's decisions cannot be told apart in its numbers.")}


static func _offset_words(bloc: String, d: float) -> String:
	var who := Labels.bloc(bloc)
	if absf(d) < OFFSET_SLIGHT:
		return Strings.t("%s slightly for") % who if d > 0.0 else Strings.t("%s slightly against") % who
	if absf(d) < OFFSET_CLEAR:
		return Strings.t("%s for") % who if d > 0.0 else Strings.t("%s against") % who
	return Strings.t("%s clearly for") % who if d > 0.0 else Strings.t("%s clearly against") % who


static func _booked(text: String, tone: String) -> Dictionary:
	return {"text": text, "tone": tone, "uncertain": false, "spark": PackedFloat64Array(), "tooltip": ""}


## The pooled measurement effects_ledger.gd booked this month, biggest first; with
## nothing decided, the history's own six-month movements.
static func _movements(state, now: int) -> Array:
	if not state.recent_effects.is_empty():
		var effect: Dictionary = state.recent_effects[0]
		if int(effect.get("year", 0)) * 12 + int(effect.get("month", 0)) == now:
			return EffectsLedger.moved(effect)
	var rows: Array = Trends.movements(state)
	return EffectsLedger.moved({"movements": rows})


static func _uncertain(state, m: Dictionary) -> Dictionary:
	var spark := PackedFloat64Array()
	var history: Array = state.history
	for i in range(maxi(0, history.size() - SPARK_MONTHS), history.size()):
		var e: Dictionary = history[i]
		# Approval as the polls showed it, never the true figure (the fog).
		spark.append(Trends._polled(e) if String(m["key"]) == Trends.APPROVAL_KEY else float(e.get(String(m["key"]), 0.0)))
	return {"text": "%s %s" % [String(m["label"]), Trends.change_text(float(m["change"]), String(m["unit"]))],  # i18n: row-ok Trends translates its labels
		"tone": "", "uncertain": true, "spark": spark, "tooltip": Strings.t("Many causes move this figure.")}
