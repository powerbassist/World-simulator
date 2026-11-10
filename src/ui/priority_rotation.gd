extends RefCounted

## V5.3 B7, band RF2 (Gameplay's rule, docs/design/v5.3-b7-density.md section 11): in a
## full month, a kind that qualifies can go unshown for good -- a hostile person (score
## 1.6) qualified for one month whose three lines were full, and RF2 failed 3 runs of 8.
## So after the three lines are chosen, a kind that qualifies and has had no line for
## UNSEEN_MONTHS takes the third line: the longest unseen first, then rank order. Never
## over a held line or one due this month, never a standing read; no fourth line, no
## score or footer moved. Measured: 10 third lines replaced over 685 briefings, RF2 8/8.
##
## The memory is `memory["shown"]`, {kind: the month it was last on a line}:
## presentation memory like the rest of the briefing's, so a load starts it over.

const K = preload("res://src/ui/priorities_constants.gd")


## `lines` as Priorities._pick chose them, `cands` in its rank order (it sorts them);
## rewrites the third line in place and stamps the month's kinds as shown.
static func rotate(lines: Array, cands: Array, memory: Dictionary, now: int) -> void:
	var shown: Dictionary = memory.get("shown", {})
	_third(lines, cands, now, shown)
	for l in lines:
		shown[String(l["kind"])] = now
	memory["shown"] = shown


static func _third(lines: Array, cands: Array, now: int, shown: Dictionary) -> void:
	if lines.size() < 3 or bool(lines[2]["held"]):
		return
	var due := int(lines[2]["deadline_month"])
	if due >= 0 and not bool(lines[2]["standing"]) and due - now <= 1:
		return
	var on_lines := {}
	for l in lines:
		on_lines[String(l["kind"])] = true
	var best = null
	var best_age := -1
	for c in cands:
		var age := now - int(shown.get(String(c["kind"]), -100000))
		if not on_lines.has(String(c["kind"])) and not bool(c["standing"]) and age >= K.UNSEEN_MONTHS and age > best_age:
			best = c
			best_age = age
	if best != null:
		lines[2] = best
