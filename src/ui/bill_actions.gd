extends RefCounted

## What a law's verbs do toward the slot and the queue -- V5.3 screen 4, PR 1. The sheet's verb row
## (verbs) and the row's right click (menu) are two doors onto ONE table (bill_verbs.gd), so a
## verb is down on both with the same reason, and neither offers a press the sim refuses.
## The commands are BillQueue's; the panel only redraws (mark_dirty).

const ActsOn = preload("res://src/ui/acts_on.gd")
const BillQueue = preload("res://src/sim/bill_queue.gd")
const BillVerbs = preload("res://src/ui/bill_verbs.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const VerbPlate = preload("res://src/ui/verb_plate.gd")

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
			if verb.name == "Force" and cells["slot"] == "held" and int(cells["queued"]) < 0:
				continue
			(verb as Button).disabled = true
			(verb as Button).tooltip_text = down
			if panel._primary == verb:
				panel._primary = null
	var queue: Dictionary = cells["queue"]
	var out: Dictionary = cells["unqueue"]
	if bool(queue["shown"]):
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


## A press on a law's row: the right button opens its verbs. (A signal's argument comes first,
## the bound ones after.)
static func row_input(event: InputEvent, list, law) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_RIGHT:
		menu(list, law)


## The right click on a law's row: the same verbs, each a press (or down, with its reason).
static func menu(list, law) -> void:
	var panel = list._panel
	var plate = VerbPlate.of(panel)
	if plate == null:
		return
	var cells := BillVerbs.cells(panel._state, panel._loader, String(law.id), panel._find_law)
	var items: Array = [
		{"text": Strings.t("Propose"), "enabled": cells["propose"] == "", "reason": cells["propose"], "call": panel._on_propose.bind(law)}]
	var queue: Dictionary = cells["queue"]
	if bool(queue["shown"]):
		items.append({"text": queue["text"], "enabled": queue["enabled"], "reason": queue["reason"], "call": add.bind(list, law)})
	if bool(cells["unqueue"]["shown"]):
		items.append({"text": cells["unqueue"]["text"], "enabled": true, "call": take_out.bind(list, String(law.id))})
	items.append({"text": Strings.t("Open the sheet"), "enabled": true, "call": list.select.bind(String(law.id))})
	plate.open(panel, items)
