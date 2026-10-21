extends Node

## V5.1-0c. The game's own OS window: what "windowed" means, and the key that
## gets a player out of fullscreen.
##
## Why this exists (the author's "window size change dont work"): the game boots
## FULLSCREEN (SettingsPanel.DEFAULT_FULLSCREEN), where the OS window has no frame
## to drag, the resolution list is disabled, and no key left it -- the only way out
## was a Settings row nobody knew to look for. And once windowed, every return to
## the main menu re-applied the preset size, so a drag-resize snapped back.
##
## Two rules fix both, with no project.godot change (repo-guards refuses staging
## it): windowed is always resizable with a floor, and the preset size is applied
## only when the window is NOT already windowed -- a drag survives the trip
## through the menu. F11 flips fullscreen and persists the choice, so the Settings
## row agrees with the screen.
##
## Installed once on the root Window by SettingsPanel.apply_saved(), which the menu
## runs first; a Window's children outlive change_scene_to_file(), so the key works
## in the menu and in the game with no wiring in either scene.

const TOGGLE_KEY := KEY_F11
const NODE_NAME := "WindowMode"

## The smallest window the 1920x1080 layout stays legible in: the settings list's
## own smallest preset, 1280x720, is above it.
const MIN_SIZE := Vector2i(960, 540)

## True once the first apply has run in this process; from then on a windowed
## window is the player's to size.
static var _applied_once := false


## What _apply should do, as data so it can be tested without a display.
## `was_fullscreen` is the window's mode NOW: a window that is already windowed
## keeps the size the player dragged it to; one coming out of fullscreen (or the
## first apply of the process) takes the preset, and so does a size picked on
## the Settings screen (`force_size`).
static func plan(fullscreen: bool, was_fullscreen: bool, force_size := false) -> Dictionary:
	return {
		"fullscreen": fullscreen,
		"resizable": true,
		"min_size": MIN_SIZE,
		"set_size": (not fullscreen) and (force_size or was_fullscreen or not _applied_once),
	}


## Called by SettingsPanel._apply once the plan has been carried out.
static func note_applied() -> void:
	_applied_once = true


## What the key does is handed in rather than preloaded: settings_panel.gd owns
## the config file and preloads this file, and two preloads of each other do not
## parse.
var _on_toggle: Callable


## Adds the key node to `window` unless it is already there.
static func install(window: Window, on_toggle: Callable) -> void:
	if window == null or window.get_node_or_null(NODE_NAME) != null:
		return
	var node := new()
	node.name = NODE_NAME
	node._on_toggle = on_toggle
	window.add_child(node)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != TOGGLE_KEY:
		return
	get_viewport().set_input_as_handled()
	_on_toggle.call(get_window())
