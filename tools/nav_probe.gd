extends SceneTree

## V2.1c step 0. Run: godot --headless --script res://tools/nav_probe.gd
##
## THREE QUESTIONS, and the third is the one the ROADMAP row calls this session's
## real one.
##
## **(a) How many entries does a cluster hold?** The bottom bar's drawer is centred
## between the left stack and the clock, so the width it may use is not the
## viewport -- it is whatever those two leave. Measured rather than guessed,
## because "does V2 need a fifth cluster" is otherwise a matter of taste, and this
## project's record says a range chosen by taste chooses the answer.
##
## **(b) How is a window actually reached?** Four routes exist -- the bar, the
## keyboard, a map marker (U6c) and a message card (V1.8) -- and only the first is
## complete. The keyboard half is measured by PRESSING EVERY LETTER rather than by
## reading main.gd's match block, because reading a list to check a list is how
## `tests/test_shell.gd::EXPECTED_PANELS` stayed at seven of fourteen since U5a.
##
## **(c) What is unanswered while nothing is open?** The resting screen is the map
## plus the furniture. A pending decision reaches it through exactly one thing --
## `message_stack.gd` -- which holds `MAX_CARDS = 6`, drops the OLDEST when a
## seventh arrives, lets the player dismiss any of them, and is never re-pushed.
## So a crisis with a deadline can go quiet while its deadline runs. This counts
## the months in which that is true.
##
## Measures and prints. Nothing here decides anything on its own: the plan's
## pre-committed responses are what read these numbers.

const Events = preload("res://src/sim/events.gd")
const Campaign = preload("res://src/sim/campaign.gd")

## Fourteen years, the horizon every probe on this project uses.
const MONTHS := 168

## What a V2 surface would be called in a drawer. Real labels rather than "XXXX",
## because a subrow's width is the sum of its buttons' text widths.
const SYNTHETIC_LABELS: Array[String] = ["City", "Region", "Energy", "Climate", "Agenda"]

## The two routes that are neither the bar nor the keyboard. A pair, not a list.
const OTHER_ROUTES := {
	"projects": "map marker",
	"events": "message card",
}

var _main
var _frame := 0
var _jobs: Array = []
var _job_rows: Array = []
var _pending_job: Dictionary = {}
var _shipped_entries := {}
var _available_width: float = 0.0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false

	if _frame == 3:
		_prepare_capacity_jobs()

	# One job per frame: a subrow rebuilt in this call reports the width it had
	# before the rebuild -- docs/panel-system.md section 5, one level up again.
	if not _pending_job.is_empty():
		_measure_capacity_job()
	if not _jobs.is_empty():
		_apply_capacity_job()
		return false

	_print_capacity()
	_restore_entries()
	_print_routes()
	# Two passes over the same fourteen years, differing only in whether the
	# player ever clicks the X on a card they have read. The second is a fresh
	# game because the first spends its own history.
	_print_resting(_main, false)
	var second = load("res://src/ui/main.tscn").instantiate()
	root.add_child(second)
	_print_resting(second, true)
	quit(0)
	return true


# --- (a) cluster capacity -----------------------------------------------------

func _prepare_capacity_jobs() -> void:
	var bar = _main._hud.action_bar
	for cluster_id in bar._entries.keys():
		_shipped_entries[cluster_id] = bar._entries[cluster_id].duplicate(true)

	# What the bar may use: the whole HUD row less the two corners it sits
	# between, and less the margins that corner them.
	var hud = _main._hud
	var left: float = maxf(hud.map_legend.size.x, hud.portrait_card.size.x)
	var right: float = hud.clock_cluster.size.x
	_available_width = hud.size.x - hud.EDGE_MARGIN * 2.0 - left - right

	for cluster_id in bar._entries.keys():
		for extra in range(0, 4):
			_jobs.append({"cluster": cluster_id, "extra": extra})


func _apply_capacity_job() -> void:
	var job: Dictionary = _jobs.pop_front()
	var bar = _main._hud.action_bar
	var cluster_id := String(job["cluster"])

	var entries: Array = _shipped_entries[cluster_id].duplicate(true)
	for i in range(int(job["extra"])):
		entries.append({"id": "synthetic_%d" % i, "label": SYNTHETIC_LABELS[i]})
	bar._entries[cluster_id] = entries

	bar.close_subrow()
	bar._toggle_cluster(cluster_id)
	_pending_job = job


func _measure_capacity_job() -> void:
	var bar = _main._hud.action_bar
	var width: float = bar._subrow.get_parent().size.x
	_job_rows.append({
		"cluster": String(_pending_job["cluster"]),
		"entries": _shipped_entries[String(_pending_job["cluster"])].size() + int(_pending_job["extra"]),
		"extra": int(_pending_job["extra"]),
		"width": width,
	})
	_pending_job = {}


func _restore_entries() -> void:
	var bar = _main._hud.action_bar
	for cluster_id in _shipped_entries.keys():
		bar._entries[cluster_id] = _shipped_entries[cluster_id]
	bar.close_subrow()


func _print_capacity() -> void:
	print("")
	print("=== (a) how wide is a drawer, and how wide may it be ===")
	print("viewport %.0f, bar may use %.0f (the rest is the left stack and the clock)"
		% [_main._hud.size.x, _available_width])
	print("%-10s %8s %8s %8s %8s" % ["cluster", "entries", "extra", "width", "headroom"])
	var over := 0
	for row in _job_rows:
		var headroom: float = _available_width - float(row["width"])
		if headroom < 0.0:
			over += 1
		print("%-10s %8d %8d %8.0f %8.0f%s" % [
			row["cluster"], row["entries"], row["extra"], row["width"], headroom,
			"   OVER" if headroom < 0.0 else "",
		])
	print("rows over the available width: %d of %d" % [over, _job_rows.size()])


# --- (b) route coverage -------------------------------------------------------

func _print_routes() -> void:
	var windows = _main._windows
	var bar = _main._hud.action_bar

	var cluster_of := {}
	for cluster_id in bar._entries.keys():
		for entry in bar._entries[cluster_id]:
			cluster_of[String(entry["id"])] = cluster_id

	# Press every letter and see what opens. No list is read: whatever main.gd
	# binds today answers for itself.
	var key_of := {}
	for offset in range(26):
		var keycode: int = KEY_A + offset
		windows.close_all()
		_press(keycode)
		for id in windows.open_ids():
			key_of[id] = OS.get_keycode_string(keycode)
		if _main._save_load_panel != null:
			_main._save_load_panel.hide()
	windows.close_all()

	print("")
	print("=== (b) how each window is reached ===")
	print("%-12s %-10s %-8s %-14s" % ["window", "cluster", "key", "other"])
	var keyed := 0
	for id in windows.panel_ids():
		var key := String(key_of.get(id, "--"))
		if key != "--":
			keyed += 1
		print("%-12s %-10s %-8s %-14s" % [
			id, String(cluster_of.get(id, "NONE")), key, String(OTHER_ROUTES.get(id, "")),
		])
	print("bar %d of %d, keyboard %d of %d, other routes %d" % [
		cluster_of.size(), windows.panel_ids().size(),
		keyed, windows.panel_ids().size(), OTHER_ROUTES.size(),
	])


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_main._unhandled_input(event)


# --- (c) what is unanswered at rest -------------------------------------------

func _print_resting(game, tidy: bool) -> void:
	var windows = game._windows
	windows.close_all()
	var clock: Node = game.get_node("Clock")
	var state = game._state

	var months := 0
	var elections := 0
	var live := {}      # kind -> months in which a decision of that kind was pending
	var unseen := {}    # kind -> months in which it was pending and nothing on screen said so
	for kind in ["event", "referendum", "bloc vote", "dissolution", "campaign"]:
		live[kind] = 0
		unseen[kind] = 0

	var last_month: int = state.month
	while months < MONTHS:
		clock.advance_one_day()
		if game._election_panel != null and game._election_panel.visible:
			game._election_panel.hide()
			elections += 1
		if state.month == last_month:
			continue
		last_month = state.month
		months += 1

		var ns = state.player()
		if ns == null or not ns.in_government:
			break

		var titles := _card_titles(game)
		for kind in _pending_kinds(state, ns):
			live[kind] += 1
			if not _spoken_for(kind, ns, titles):
				unseen[kind] += 1
		# A player who reads a card and closes it. Nothing re-pushes, so what the
		# X takes away is gone for the rest of the deadline.
		if tidy:
			game._hud.message_stack.clear()

	print("")
	print("=== (c) pending decisions against what the resting screen says%s ===" % (
		", player dismisses each card once read" if tidy else ", player never touches a card"))
	print("%d months run, %d election screens dismissed, nothing ever opened" % [months, elections])
	print("%-12s %8s %8s %8s" % ["pending", "months", "unseen", "share"])
	var total_live := 0
	var total_unseen := 0
	for kind in live.keys():
		var l: int = live[kind]
		var u: int = unseen[kind]
		total_live += l
		total_unseen += u
		print("%-12s %8d %8d %8s" % [
			kind, l, u, "--" if l == 0 else "%.0f%%" % (100.0 * float(u) / float(l)),
		])
	print("pending-months %d, of which nothing on screen says so %d (%s)" % [
		total_live, total_unseen,
		"--" if total_live == 0 else "%.0f%%" % (100.0 * float(total_unseen) / float(total_live)),
	])


func _pending_kinds(state, ns) -> Array[String]:
	var out: Array[String] = []
	if Events.is_pending(ns):
		out.append("event")
	if not ns.referendum_pending.is_empty():
		out.append("referendum")
	if not Dictionary(state.bloc.get("pending", {})).is_empty():
		out.append("bloc vote")
	if ns.dissolution_pending:
		out.append("dissolution")
	if Campaign.is_open(state, ns):
		out.append("campaign")
	return out


## Does anything on the resting screen name this decision? The message column is
## the only route, so this is a search of the cards on screen right now -- an
## event's card is pushed once, on arrival, and nothing re-pushes it.
func _spoken_for(kind: String, ns, titles: Array) -> bool:
	if kind != "event":
		# Nothing in main.gd ever pushes a card for a referendum, a council vote,
		# a pending dissolution or an open campaign window. Measured by counting
		# the callers of message_stack.push(), and asserted here by construction.
		return false
	# The column upper-cases every title it is given, so the comparison is too.
	# The first version of this check was case-sensitive and reported an event
	# unseen in 32 months of 32 -- a probe wrong about its own headline.
	var name := Events.pending_event_name(ns).to_upper()
	for title in titles:
		if String(title).to_upper() == name:
			return true
	return false


func _card_titles(game) -> Array:
	var out: Array = []
	var stack = game._hud.message_stack
	for id in stack._cards.keys():
		var card: Control = stack._cards[id]
		out.append(_first_label(card))
	return out


func _first_label(node) -> String:
	if node is Label:
		return node.text
	for child in node.get_children():
		var found := _first_label(child)
		if not found.is_empty():
			return found
	return ""
