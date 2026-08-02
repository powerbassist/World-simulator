extends SceneTree

## Saves a PNG of the running game. Dev-only, never shipped.
##
##   godot --path "<repo>" --script res://tools/screenshot.gd
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --frames 40
##
## Exists because --headless draws nothing and the whole test suite is headless.
## Two U5a bugs -- the map's opening zoom and a window's maximum height -- were
## wrong on a 1080p screen and invisible to a green suite; both would have been
## obvious in one frame. A UI session that never looks at a frame is a UI session
## that ships whatever the layout engine happened to do.
##
## Runs windowed, not headless, on purpose: root.get_texture() is the window's own
## framebuffer, and with no rendering device there is nothing in it.

const OUT_DEFAULT := "user://screenshot.png"

## Enough frames for the theme to build, the raster to decode, and the first
## resize -- which is what triggers _fit_zoom() -- to have happened and been
## drawn. Below about ten the map is caught at zoom 1.0 mid-fit.
const FRAMES_DEFAULT := 30

var _frames_wanted := FRAMES_DEFAULT
var _out_path := OUT_DEFAULT
var _frame := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			_frames_wanted = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]

	root.add_child(load("res://src/ui/main.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frame += 1
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
