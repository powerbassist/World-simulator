extends SceneTree

## Saves a PNG of the running game. Dev-only, never shipped.
##
##   godot --path "<repo>" --script res://tools/screenshot.gd
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --frames 40
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer relations
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer trade --hover DEU
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer coercion --coerce
##
## Exists because --headless draws nothing and the whole test suite is headless.
## Two U5a bugs -- the map's opening zoom and a window's maximum height -- were
## wrong on a 1080p screen and invisible to a green suite; both would have been
## obvious in one frame. A UI session that never looks at a frame is a UI session
## that ships whatever the layout engine happened to do.
##
## Runs windowed, not headless, on purpose: root.get_texture() is the window's own
## framebuffer, and with no rendering device there is nothing in it.

const Relations = preload("res://src/core/relations.gd")

const OUT_DEFAULT := "user://screenshot.png"

## Enough frames for the theme to build, the raster to decode, and the first
## resize -- which is what triggers _fit_zoom() -- to have happened and been
## drawn. Below about ten the map is caught at zoom 1.0 mid-fit.
const FRAMES_DEFAULT := 30

var _frames_wanted := FRAMES_DEFAULT
var _out_path := OUT_DEFAULT
var _frame := 0

## U5c. Which map layer to capture, and which nation to hold the cursor over.
## Both exist because the layer system's one falsifiable claim -- that a
## saturated ramp survives being drawn over a satellite photograph -- can only be
## checked by looking, and there are four frames to look at rather than one.
var _layer := ""
var _hover := ""

## V1.3c. Impose a spread of measures before capturing, because a new game has
## none and a frame of an all-zero layer proves nothing about its ramp -- which is
## the one claim a screenshot exists to check. U5c's own falsifier was whether a
## saturated ramp survives being drawn over a satellite photograph; that question
## cannot be asked of a layer where every nation sits at the same end.
var _coerce := false
var _main


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			_frames_wanted = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]
		elif args[i] == "--layer" and i + 1 < args.size():
			_layer = args[i + 1]
		elif args[i] == "--hover" and i + 1 < args.size():
			_hover = args[i + 1].to_upper()
		elif args[i] == "--coerce":
			_coerce = true

	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	# One frame before the capture, not at _init(): the map has to have been laid
	# out and fitted before a lon/lat can be turned into the screen point the
	# hover needs, and the legend has to have run _ready() to be told anything.
	if _frame == _frames_wanted - 1:
		_apply_view()
	if _frame < _frames_wanted:
		return false

	var image := root.get_texture().get_image()
	if image == null:
		printerr("no framebuffer -- run windowed, not --headless")
		quit(1)
		return true

	var error := image.save_png(_out_path)
	if error != OK:
		printerr("could not write %s: %d" % [_out_path, error])
		quit(1)
		return true

	print("wrote %s (%dx%d)" % [ProjectSettings.globalize_path(_out_path), image.get_width(), image.get_height()])
	quit(0)
	return true


## Drives the map through its public surface rather than synthesising input:
## set_layer() and the hover fields are the same methods the legend and a
## headless test use, so this tool captures the real code path.
func _apply_view() -> void:
	if _main == null or _main._map_view == null:
		return
	if _coerce:
		_impose_a_spread()
	if _layer != "":
		_main._map_view.set_layer(_layer)
		_main._hud.map_legend.show_layer(_main._map_view.layer())
	if _hover != "":
		_main._map_view._hovered_id = _hover
		_main._map_view.queue_redraw()
		_main._hud.map_legend.show_hover(
			_hover, _main._state, _main._map_view.viewer_id()
		)


## One measure at each legend stop, so the captured frame shows the whole ramp
## rather than one point on it. Written straight into the register, the way
## tools/coercion_probe.gd does -- this is a dev tool looking at pixels, not a
## test of the command path, and going through Diplomacy.execute() would tie the
## severities to whatever the shipped verbs happen to use.
func _impose_a_spread() -> void:
	var state = _main._state
	if state == null:
		return
	var viewer: String = _main._map_view.viewer_id()

	# Deliberately spread across the domain AND across the two directions, so the
	# frame answers both questions at once: does the ramp separate, and does a
	# measure aimed AT the player read the same as one the player aimed.
	var spread := {"DEU": 0.625, "ITA": 1.0, "ESP": 0.3}
	for target in spread.keys():
		if not state.nations.has(target):
			continue
		state.measures[Relations.directed_key(viewer, target)] = _terms(
			state, "tariff", float(spread[target])
		)
	# Mutual: the pair that must read at the top of the ramp rather than as clean,
	# which is the netting bug this layer's design note warns a later session about.
	if state.nations.has("ITA"):
		state.measures[Relations.directed_key("ITA", viewer)] = _terms(state, "tariff", 1.0)

	_main._map_view.queue_redraw()


func _terms(state, kind: String, severity: float) -> Dictionary:
	return {
		"action_id": "screenshot", "action_name": "Screenshot",
		"kind": kind, "severity": severity,
		"since_year": state.year, "since_month": state.month, "retaliated": true,
	}
