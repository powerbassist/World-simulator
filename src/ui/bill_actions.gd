extends RefCounted

## What a law's verbs do toward the slot and the queue -- V5.3 screen 4, PR 1. The sheet's verb row
## (verbs) and the row's right click, which lights that row, read ONE table (bill_verbs.gd), so a
## verb is down on both with the same reason, and neither offers a press the sim refuses.
## The commands are BillQueue's; the panel only redraws (mark_dirty).

const ActsOn = preload("res://src/ui/acts_on.gd")
const BillQueue = preload("res://src/sim/bill_queue.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const VerbBlock = preload("res://src/ui/verb_block.gd")

## The sheet buttons' node names, which the tests and the briefing's Go find them by.
const QUEUE := "Queue"  # i18n: ok a node name
const TAKE_OUT := "TakeOut"  # i18n: ok a node name


## The sheet's verbs after Propose, Force and Referendum are built into `row`: the table's reason
## goes on whichever of them is down, and the queue's verb is added. Article 49.3 adopts without
## a vote and takes no place, so a bill held in the slot does not hold it (the parent's call on
## #173); the tabled bill itself and a queued law refuse it.
static func verbs(list, row: Control, ns, law) -> void:
	var panel = list._panel
	var cells := BillVerbs.cells(panel._state, panel._loader, String(law.id), panel._find_law)
	var down: String = cells["propose"]
	if down != "":
		for verb in row.get_children():
			if verb.name == "Force" and cells["slot"] == "held" and int(cells["queued"]) < 0 and String(cells["shut"]) == "":
				continue
			(verb as Button).disabled = true
			(verb as Button).tooltip_text = down
			if panel._primary == verb:
				panel._primary = null
	var queue: Dictionary = cells["queue"]
	var out: Dictionary = cells["unqueue"]
	if bool(queue["shown"]):
		# The Bills second pass: one verb. While the slot is held, the queue's press IS the
		# proposal ("Propose for March"), so the down Propose beside it would say it twice.
		for verb in row.get_children():
			if verb.name == "Propose":
				verb.visible = false
		var press := _press(String(queue["text"]), not bool(queue["enabled"]), String(queue["reason"]), law, QUEUE)
		press.pressed.connect(func() -> void: add(list, law))
		panel._offer(press)
		row.add_child(press)
	if bool(out["shown"]):
		var press := _press(String(out["text"]), false, "", law, TAKE_OUT)
		press.pressed.connect(func() -> void: take_out(list, String(law.id)))
		row.add_child(press)


static func _press(text: String, down: bool, reason: String, law, node_name: String) -> Button:
	var press := PanelKit.sized(Button.new())
	press.name = node_name
	press.text = text  # i18n: row-ok BillVerbs hands a translated string
	press.disabled = down
	press.tooltip_text = reason
	# The briefing's Go lands on an enabled control tagged with the law: while the slot is held
	# the queue is the only verb that acts on it.
	ActsOn.tag(press, [law.id])
	return press


## Puts the law at the back of the queue, at the size grade the sheet has picked.
static func add(list, law) -> void:
	var panel = list._panel
	BillQueue.add(panel._state, {"law_id": String(law.id), "scale": list.grade(law), "referendum": false, "force": false})
	panel.mark_dirty()


static func take_out(list, law_id: String) -> void:
	var panel = list._panel
	var at := BillVerbs.queued_at(panel._state.player(), law_id)
	if at >= 0:
		BillQueue.remove(panel._state, at)
	panel.mark_dirty()


## A press on a law's row: the right button selects it and lights its sheet's verbs (the rework pass's C;
## the plate is gone). (A signal's argument comes first, the bound ones after.)
static func row_input(event: InputEvent, list, law) -> void:
	if VerbBlock.is_right_press(event):
		list.select(String(law.id))
		VerbBlock.light(list._detail)
