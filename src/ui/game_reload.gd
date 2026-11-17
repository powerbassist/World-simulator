extends RefCounted

## A load rebuilds the game (the author's call, 2026-11-16: "la solution 2, on s'en fiche d'un
## temps de chargement plus long"). Until then a load kept main and every panel and pointed them
## at the loaded state through setup(), and each panel's per-game memory had to be forgotten by
## hand: the stale-state-after-load class was fixed one panel at a time, six times, and the
## guard of #396 kept finding more (a picked line, a refusal, a confirm card, a helper's state).
## Now the main that asked is taken out of the tree and a new one is built from main.tscn with
## the save handed in, the way a new game starts, so nothing of the old scene survives: panels,
## helpers, overlays, confirm cards, verb plates, the voice queue, the map's view.
##
## The swap mirrors SceneTree.change_scene_to_node() (class_scenetree.md: "The current scene node
## is immediately removed from the tree ... the formerly current scene ... will be deleted ...
## This ensures that both scenes aren't running at the same time"), done through the node's own
## parent rather than the tree's current scene, because tests parent main under the root without
## making it current and run two mains at once; and synchronously, so the caller gets the new
## main back.

const Strings = preload("res://src/ui/strings.gd")
const GAME_SCENE := "res://src/ui/main.tscn"


## `result` is SaveManager.load_game()'s successful result. Returns the new main.
static func swap(main: Node, result: Dictionary, slot: String) -> Node:
	var fresh: Node = load(GAME_SCENE).instantiate()
	fresh.pending_loader = main._loader
	fresh.pending_save = handoff(result, slot, int(main._clock.speed))
	var parent := main.get_parent()
	var index := main.get_index()
	var tree := main.get_tree()
	var was_current: bool = tree != null and tree.current_scene == main
	preload("res://src/ui/voice.gd").stop(main)  # the old game's line ends with it
	parent.remove_child(main)
	parent.add_child(fresh)
	parent.move_child(fresh, index)
	if was_current:
		tree.current_scene = fresh
	main.queue_free()
	return fresh


## Statics keyed by a main's instance id (one entry per main): the old main's entry would outlive
## it (its lane, its session, callables bound to it), one game's worth per load. [file stem in
## src/ui, static var]. tests/test_game_reload_records.gd walks src/ui for every `static var` and
## fails one that is in neither this table, CLEARED_STATICS nor its cache allow-list.
const MAIN_KEYED_STATICS := [
	["audience_driver", "_games"], ["briefing_driver", "_games"], ["phone_driver", "_games"],
	["poll_card", "_games"], ["files_driver", "_views"], ["council_cards", "_told"],
	["proposal_note", "_tabled"], ["proposal_note", "_told"], ["region_arrival", "_told"],
]


static func _static_dict(stem: String, var_name: String) -> Dictionary:
	return load("res://src/ui/%s.gd" % stem).get(var_name)


## Called from main's _exit_tree, the one place every way out of a game passes through: a load's
## swap, the pause menu's and a lost election's trip to the menu, a test freeing it.
static func forget_main(main: Node) -> void:
	var id := main.get_instance_id()
	for entry in MAIN_KEYED_STATICS:
		_static_dict(entry[0], entry[1]).erase(id)


## A save read for a main to boot from: {state, day, slot}, or {} when it does not read (the
## caller then keeps the slot, and main's load path reports the error on the save screen).
static func read(slot: String, loader) -> Dictionary:
	var result: Dictionary = preload("res://src/core/save_manager.gd").load_game(slot, loader)
	if not bool(result.get("ok", false)):
		return {}
	return handoff(result, slot)


## The ONE handoff a main boots from a save with, built here for every load (menu, test, in game)
## so the paths cannot diverge (#396 pass 2, T2): the state, the saved day, the slot, and the speed
## the player was running at (0 for a boot, which keeps the clock's own).
static func handoff(result: Dictionary, slot: String, speed := 0) -> Dictionary:
	return {"state": result["state"], "day": int(result["day"]), "slot": slot, "speed": speed}


## A main built from a save takes its date from it, opens paused at the speed it was handed, and
## mirrors today into the state for the diary (a booking for today reads as past otherwise).
static func set_clock(main) -> void:
	var clock = main._clock
	clock.year = main._state.year
	clock.month = main._state.month
	clock.day = int(main.pending_save["day"])
	clock.paused = true
	if int(main.pending_save.get("speed", 0)) > 0:
		clock.set_speed(int(main.pending_save["speed"]))
	main._state.day = clock.day


## Per-game state some UI files keep in a static rather than on a node (QA's RECORD on #396), NOT
## keyed by a main: a new main is a new game, so main._ready() clears them, for a load and for a
## new game alike. [file stem in src/ui, static var].
const CLEARED_STATICS := [["counter_chips", "_picked"], ["law_sheet", "_open"], ["poll_strip", "_picked"]]


## Files whose per-game statics are reset by their own `forget()`: file stem -> the statics it
## covers (the guard test reads the names).
const RESET_BY_CALL := {"glossary_hint": ["_shown_in", "_card", "term_read"]}


static func reset_statics() -> void:
	for entry in CLEARED_STATICS:
		_static_dict(entry[0], entry[1]).clear()
	for stem in RESET_BY_CALL:
		load("res://src/ui/%s.gd" % stem).forget()


## What a main built from a save does once every panel is up: the steps that establish the loaded
## game (its date, its desk, its pauses), not the ones that used to forget the discarded one.
static func after_load(main) -> void:
	var save: Dictionary = main.pending_save
	# The assembly's announce stamps from the loaded register: a quiet month must not re-announce
	# a division the save already carries (assembly_news.gd's forget, the ultra pass-7 finding).
	main._assembly_news.forget(main._state.player().last_law_result)
	# The desk's rows back in the inbox and the latest consequence card (C6).
	preload("res://src/ui/desk_cards.gd").restore_after_load(main)
	# The month's music from the loaded game's own situation, as its month ends would set it: the old
	# main's Music node went with it, and nothing else plays a band before the first month end
	# (#396 pass 2, T1).
	var ns = main._state.player()
	if ns != null and bool(ns.in_government):
		var ranked: Dictionary = preload("res://src/ui/chief_mark_view.gd").rank(main, {})
		preload("res://src/ui/music.gd").follow(main, preload("res://src/ui/priorities.gd").situation(ranked["lines"]),
			preload("res://src/ui/trends.gd").months_to_vote(main._state, ns), main._state.get_instance_id())
	# V2.4b: an interrupt crisis pending in the save stops the clock again.
	main._enforce_interrupt()
	main._note_holds_for_pause_menu()
	main._save_load_panel.report(Strings.t("Loaded '%s'.") % String(save["slot"]))
	main._save_load_panel.mark_dirty()
