extends RefCounted

## V5.3, the author's "je veux jouer en 2k": the interface size, the root window's
## content_scale_factor, a row of the Settings screen (settings_panel.gd).
##
## The project stretches its 1920x1080 canvas to the window (canvas_items, expand),
## so a 2560x1440 screen showed the 1080p layout x1.33 -- bigger, not more room.
## Below 1.0 the logical canvas grows instead (2560x1440 at 0.75 on a 1440p screen):
## the dock, the inbox and every type size stay what they are in logical px, so the
## extra room goes to the map. Never above 1.0: that is the retired interface scale
## (settings_panel.gd, TEXT_SCALES), which shrank the canvas until the dock ate the map.
## Text size still applies on top.
##
## Engine: "If Stretch Mode is set to canvas_items, 2D elements will be scaled
## relative to the base window size, then multiplied by the Scale setting"
## (tutorials/rendering/multiple_resolutions.md, Stretch Scale); the Scale setting
## at runtime is Window.content_scale_factor (classes/class_window.md).
##
## Its own file, not settings_panel.gd's: that one is at the size ratchet. It cannot
## preload settings_panel.gd (that one preloads this), so it names the file itself.

## settings_panel.gd's CONFIG_PATH; tests/test_interface_size.gd pins the two equal.
const CONFIG_PATH := "user://settings.cfg"
const KEY := "interface_size_index"

## Index 0 is Auto (0.0 here, resolved by factor()); the rest are the factor itself.
const SIZES: Array[float] = [0.0, 1.0, 0.9, 0.8, 0.75]
const AUTO_INDEX := 0
## Auto by default, and for a settings.cfg written before the row existed: it is
## exactly 1.0 on a 1080p screen and on any dense one (DENSE_DPI), so only a large,
## normal-density screen above 1080p (a desk monitor) sees a change.
const DEFAULT_INDEX := AUTO_INDEX
## Auto's floor: 4K would ask for 0.5, a canvas wider than anything the panels were
## laid out for. At 0.75 a 2160p screen shows the UI at 1.5x its 1080p size.
const AUTO_MIN_FACTOR := 0.75
## The author's call (2026-11-16, "Pixels + densité"): Auto shrinks only on a
## normal-density screen. A 27" 1440p desk monitor is about 109 dpi and a 24" 1080p one
## about 92: there 1080p pixels are a comfortable physical size. A 14" 2560x1600 laptop
## is about 215 dpi: 1080p pixels there are two thirds the size the OS's own scaling
## (150 %) intends, so Auto keeps 1.0 and the stretch makes the UI bigger instead. The cut
## sits between the two families, above the 32" 4K (about 140 dpi) desk monitors.
## Windows has no DisplayServer.screen_get_scale(), so density is the readable signal.
const DENSE_DPI := 150


## The factor for a row index and a window size in physical px. Auto undoes the
## stretch -- min(w/1920, h/1080) under canvas_items + expand, so 1080/height on a
## 16:9 or wider screen, but the width's ratio on a taller one (a 1920x1200 or a
## drag-resized 1600x1200 window must not shrink below its 1080p size) -- clamped to
## [AUTO_MIN_FACTOR, 1.0] -- and 1.0 on a screen of DENSE_DPI or more. An index the row
## does not offer reads as Auto. `dpi` is the window's screen's, passed in so a test
## can give either kind of screen (headless reports 72).
static func factor(index: int, window_size: Vector2i, dpi := 96) -> float:
	if index > AUTO_INDEX and index < SIZES.size():
		return SIZES[index]
	if window_size.x <= 0 or window_size.y <= 0 or dpi >= DENSE_DPI:
		return 1.0
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	var stretch := minf(float(window_size.x) / base.x, float(window_size.y) / base.y)
	return clampf(1.0 / stretch, AUTO_MIN_FACTOR, 1.0)


## The row as the file holds it; Auto when the file has no key.
static func index() -> int:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return index_in(cfg)


static func index_in(cfg: ConfigFile) -> int:
	var i := int(cfg.get_value("display", KEY, DEFAULT_INDEX))
	return i if i >= 0 and i < SIZES.size() else DEFAULT_INDEX


## Sets the window's factor from the file, and makes Auto follow the window: F11, a
## maximize and a drag all change its size. The connection is made once, on the root
## Window, which outlives change_scene_to_file() (window_mode.gd's reason). Public so
## a tool that boots main.tscn without the menu (tools/screenshot.gd) gets the canvas
## a player does.
static func apply(window: Window) -> void:
	if window == null:
		return
	_index = index()
	if not window.size_changed.is_connected(refit.bind(window)):
		window.size_changed.connect(refit.bind(window))
	refit(window)


## The density refit() reads: the main window's screen, or `dpi_override` when a test
## sets it (headless reports 72, so the dense branch is otherwise unreachable there).
static var dpi_override := -1


static func screen_dpi() -> int:
	if dpi_override >= 0:
		return dpi_override
	return DisplayServer.screen_get_dpi(DisplayServer.SCREEN_OF_MAIN_WINDOW)


## The row as apply() last read it: refit() runs on every size_changed, a drag emits
## many, and the file only changes through the Settings screen, which calls apply().
static var _index := DEFAULT_INDEX


## Guarded: assigning the factor resizes the viewport, which can emit size_changed
## again; the second call finds the factor already right and stops. The density is read
## here, every time, rather than cached: a move to another screen (F11 on it, a resize
## there, a Settings save) refits with that screen's dpi.
static func refit(window: Window) -> void:
	var f := factor(_index, window.size, screen_dpi())
	if not is_equal_approx(window.content_scale_factor, f):
		window.content_scale_factor = f
