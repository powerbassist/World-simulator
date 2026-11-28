extends RefCounted

## The finance bill behind a held slot -- G2 of the blind play 2026-11-28 (docs/design/finance-bill.md section 10): the
## verb the bill's rail and sheet put in "Table the bill"'s place, its words, and the shell's card for whatever the
## footer's press did. The command is BillQueue's (finance_moves.gd calls it); the months are BillVerbs'.

const BillQueue = preload("res://src/sim/bill_queue.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const DateText = preload("res://src/ui/date_text.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRefusal = preload("res://src/ui/finance_refusal.gd")
const Strings = preload("res://src/ui/strings.gd")


## Where the queued finance bill stands in the queue, -1 when none is queued.
static func at(ns) -> int:
	for i in ns.bill_queue.size():
		if (ns.bill_queue[i] as Dictionary).has("finance"):
			return i
	return -1


## The verb when FinanceBill.refusal answers `flag`: {} unless another bill holds the slot, else {enabled, text (""
## keeps the host's own label), note (said after the refusal, before it when `cause`)} and, when it can be pressed,
## {month, day} it divides.
static func verb(state, loader, flag: String, bill: Dictionary, force := false) -> Dictionary:
	if flag != "already_tabled":
		return {}
	var ns = state.player()
	if at(ns) >= 0:
		return {"enabled": false, "text": "", "note": Strings.t("A budget text is already queued.")}
	# A queued bill is tabled in a later month, outside the autumn one: its creation or abolition would be dropped.
	if not (bill.get(FinanceBill.CREATE, {}) as Dictionary).is_empty() or not (bill.get(FinanceBill.ABOLISH, []) as Array).is_empty():
		return {"enabled": false, "text": "", "note": Strings.t("A new or abolished tax cannot wait in the queue.")}
	# The queue checks nothing and drops a bad bill months later, so tabling's other checks are asked here.
	var why := FinanceBill.refusal(state, loader, bill, force, true)
	if not why.is_empty():
		# The register's own reason when it gave one, as the register's sheet says it; else the flag's words.
		var own := String(why.get("reason", ""))
		var flags := why.keys().filter(func(key) -> bool: return not key in ["tabled", "refused", "reason"])
		return {"enabled": false, "text": "", "cause": true,
			"note": Strings.t(own) if own != "" else FinanceRefusal.reason(String(flags[0]))}  # i18n: row-ok the sim's reason, its English the msgid
	var i: int = ns.bill_queue.size()
	if i >= BillQueue.SIZE:
		return {"enabled": false, "text": Strings.t("The queue is full"), "note": Strings.t("The queue holds three bills. Take one out first.")}
	var lands := BillVerbs.division(state, i)
	return {"enabled": true, "text": Strings.t("Queue for %s") % BillVerbs.month_name(state, i),
		"note": Strings.t("If queued, it divides on %s.") % DateText.day_month(int(lands["day"]), int(lands["month"])),
		"month": int(lands["month"]), "day": int(lands["day"])}


## `reason` and the verb's note as one line, in the sheet's order. A `cause` is one of tabling's checks, which waiting
## a month does not lift: it is said first, and the folded bar shows only the first words.
static func said(queue: Dictionary, reason: String) -> String:
	var parts := [reason, String(queue.get("note", ""))]
	if queue.has("cause"):
		parts.reverse()
	return " ".join(parts).strip_edges()


## The finance bill waiting in the queue, said on the bar with no draft: {month, day, text}, {} when none is queued.
static func waiting(state) -> Dictionary:
	var i := at(state.player())
	if i < 0:
		return {}
	var lands := BillVerbs.division(state, i)
	return {"month": int(lands["month"]), "day": int(lands["day"]),
		"text": Strings.t("The finance bill is queued: it divides on %s.") % DateText.day_month(int(lands["day"]), int(lands["month"]))}


## What the bill's rail repaints on: the day, the slot, the queue and the draft.
static func stamp(state, ns, draft) -> String:
	return "%d|%d|%d|%s|%d|%d|%d|%d" % [state.year, state.month, state.day, str(ns.tabled_bill), ns.bill_queue.size(), at(ns), draft.count(), draft.moves().size()]


## The card for the footer's press: FinanceMoves.table's answer, or a withdrawal. [title, body]
static func card(tabling: Dictionary) -> Array:
	var moves := int(tabling.get("moves", 0))
	# Share moves alone (Finances slice 5): no bill was put; they took effect at once, with no vote.
	if not bool(tabling.get("rows", true)):
		return [Strings.tn("Share move applied", "Share moves applied", moves), Strings.t("The shares moved at once; no vote was needed.")]
	if bool(tabling.get("withdrawn", false)):
		return [Strings.t("Finance bill withdrawn"), Strings.t("Nothing is voted on it; the books stand as they were.")]
	if bool(tabling.get("tabled", false)):
		return [Strings.t("Finance bill tabled"), Strings.t("The Assembly votes on it at the month's end; it applies if carried.")]
	var applied := " " + Strings.tn("%d share move was applied all the same.", "%d share moves were applied all the same.", moves) % moves if moves > 0 else ""
	if bool(tabling.get("queued", false)):
		return [Strings.t("Finance bill queued"),
			Strings.t("Queued, it divides on %s.") % DateText.day_month(int(tabling["day"]), int(tabling["month"])) + applied]
	return [Strings.t("Finance bill not tabled"),
		Strings.t("No finance bill is tabled, another bill holds this month's slot, or no line moved.") + applied]
