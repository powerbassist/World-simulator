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
	fresh.pending_save = {"state": result["state"], "day": int(result["day"]), "slot": slot}
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


## A save read for a main to boot from: {state, day, slot}, or {} when it does not read (the
## caller then keeps the slot, and main's load path reports the error on the save screen).
static func read(slot: String, loader) -> Dictionary:
	var result: Dictionary = preload("res://src/core/save_manager.gd").load_game(slot, loader)
	if not bool(result.get("ok", false)):
		return {}
	return {"state": result["state"], "day": int(result["day"]), "slot": slot}


## Per-game state some UI files keep in a static rather than on a node (QA's RECORD on #396). A
## new main is a new game, so main._ready() clears them, for a load and for a new game alike.
## The statics keyed by a main's instance id (the drivers' `_games`) need nothing: a new main has
## a new id.
static func reset_statics() -> void:
	preload("res://src/ui/counter_chips.gd")._picked.clear()
	preload("res://src/ui/law_sheet.gd")._open.clear()
	preload("res://src/ui/poll_strip.gd")._picked.clear()


## What a main built from a save does once every panel is up: the steps that establish the loaded
## game (its date, its desk, its pauses), not the ones that used to forget the discarded one.
static func after_load(main) -> void:
	var save: Dictionary = main.pending_save
	# The assembly's announce stamps from the loaded register: a quiet month must not re-announce
	# a division the save already carries (assembly_news.gd's forget, the ultra pass-7 finding).
	main._assembly_news.forget(main._state.player().last_law_result)
	# The desk's rows back in the inbox and the latest consequence card (C6).
	preload("res://src/ui/desk_cards.gd").restore_after_load(main)
	# V2.4b: an interrupt crisis pending in the save stops the clock again.
	main._enforce_interrupt()
	main._note_holds_for_pause_menu()
	main._save_load_panel.report(Strings.t("Loaded '%s'.") % String(save["slot"]))
	main._save_load_panel.mark_dirty()
