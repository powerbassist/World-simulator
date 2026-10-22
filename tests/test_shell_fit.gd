extends SceneTree

## Headless test: godot --headless --script res://tests/test_shell_fit.gd
## Non-zero exit on any failure.
##
## V5.1-c2.3, the figure strip under a width it cannot fill. The strip sits beside
## the sidebar, so its slot is the screen less 232 px; a longer language, a larger
## text size (c2.4) or a game whose readings all speak at once can ask for more.
## The strip then folds its LOWEST-PRIORITY figures into a "+N" whose tip names
## them -- the gaps give way first, then the tail of StripReadings.ORDER -- and it
## re-folds when the window changes shape, not only on the next day's refresh
## (Review focus 5: a window gone 21:9 mid-game).
##
## And at the largest text size (V5.1-c2.4, Review focus 4): at 130 % on the 1920
## reference the title bar, the strip and the sidebar keep their slots -- the
## strip folds rather than grows, nothing pushes the workspace's top down.
##
## Driven a frame at a time: a size change reaches the strip through the
## viewport's size_changed and a layout pass, and a check that called the fit
## itself would assert only that the test can call it.

const StripReadings = preload("res://src/ui/strip_readings.gd")
const Sidebar = preload("res://src/ui/sidebar.gd")
const TitleBar = preload("res://src/ui/title_bar.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := "start"
var _wait := 0
var _folded_at_narrow: Array = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		"start":
			if _main.get("_top_bar") == null:
				_fail("main scene built no figure strip")
				_finish()
				return false
			_stage_every_reading_at_its_widest()
			# The strip's own slot, by a window as narrow as the stretch allows:
			# 4:3 keeps the 1920 reference width, so the slot is narrowed by text
			# instead -- every value at its widest plus a long programme caption.
			_phase = "narrow"
			_wait = 3
		"narrow":
			_wait -= 1
			if _wait > 0:
				return false
			_check_strip_folds_by_priority()
			# A wider window: 21:9 at the 1080 reference height.
			root.size = Vector2i(2520, 1080)
			_phase = "wide"
			_wait = 4
		"wide":
			_wait -= 1
			if _wait > 0:
				return false
			_check_refit_on_resize()
			# Back to the reference, at the largest text size, through the same
			# path the settings row takes.
			root.size = Vector2i(1920, 1080)
			UiTheme.set_text_scale(1.3)
			UiTheme.rebuild(_main)
			_phase = "text"
			_wait = 4
		"text":
			_wait -= 1
			if _wait > 0:
				return false
			_check_chrome_at_130()
			UiTheme.set_text_scale(1.0)
			_finish()
	return false


func _stage_every_reading_at_its_widest() -> void:
	var bar = _main._top_bar
	var widest := {
		"approval": "100% ▼ 100% ▼", "deficit": "-10.50% -10.50%", "gdp": "12345 Bn ▲ 12345 Bn ▲",
		"unemployment": "12.34% 12.34%", "inflation": "10.5% 10.5%", "unrest": "100 100",
		"assembly": "+123 +123", "election": "60 mo 60 mo", "programme": "100% 100%",
		"desk": "12 pending 12 pending", "europe": "Treaty: 12m Treaty: 12m", "commodities": "Rare earths 18% Rare earths 18%",
	}
	for id in StripReadings.ORDER:
		var value: Label = bar._figure_values[id]
		value.get_parent().visible = true
		value.text = widest[id]
	# Staging, not the check: the values were set behind the strip's back.
	bar.refit()


## Doubled values ask for far more than the 1688 px slot. The strip must fit it,
## and what it hides must be the tail of the priority order, behind a "+N".
func _check_strip_folds_by_priority() -> void:
	var bar = _main._top_bar
	var slot: float = _main.get_viewport().get_visible_rect().size.x - Sidebar.WIDTH
	var need: float = bar.get_combined_minimum_size().x
	if need > slot + 0.5:
		_fail("the strip asks for %.0f px of a %.0f px slot -- it did not fold" % [need, slot])
	var folded: Array = bar.folded_ids()
	if folded.is_empty():
		_fail("doubled readings fit a %.0f px slot without folding -- the premise is wrong" % slot)
		return
	# The folded ones are exactly the last of ORDER, in order.
	var tail: Array = StripReadings.ORDER.slice(StripReadings.ORDER.size() - folded.size())
	if folded != tail:
		_fail("the strip folded %s, not the lowest-priority tail %s" % [str(folded), str(tail)])
	if not bar._more.visible or bar._more.text != "+%d" % folded.size():
		_fail("%d folded figures show '%s', not '+%d'" % [folded.size(), bar._more.text, folded.size()])
	for id in folded:
		if not bar._more.tooltip_text.contains(String(bar._figure_captions[id].text)):
			_fail("the '+N' tip does not name the folded '%s'" % id)
	_folded_at_narrow = folded


## The window went 21:9: the slot grew by 600 px and the strip unfolds what now
## fits -- through size_changed, with no refresh between.
func _check_refit_on_resize() -> void:
	var bar = _main._top_bar
	var folded: Array = bar.folded_ids()
	if folded.size() >= _folded_at_narrow.size():
		_fail("a window 600 px wider still folds %d figures (it folded %d) -- the strip did not refit on resize"
			% [folded.size(), _folded_at_narrow.size()])


func _check_chrome_at_130() -> void:
	var hud = _main._hud
	var view: Vector2 = _main.get_viewport().get_visible_rect().size
	var title: Vector2 = hud.title_bar.get_combined_minimum_size()
	if title.y > TitleBar.HEIGHT + 0.5:
		_fail("at 130 %% the title bar is %.0f px tall; its slot is %d" % [title.y, TitleBar.HEIGHT])
	if title.x > view.x + 0.5:
		_fail("at 130 %% the title bar needs %.0f px of a %.0f px screen" % [title.x, view.x])
	var strip: Vector2 = hud.top_bar.get_combined_minimum_size()
	if strip.y > TopBar.BAR_HEIGHT + 0.5:
		_fail("at 130 %% the strip is %.0f px tall; its slot is %d" % [strip.y, TopBar.BAR_HEIGHT])
	if strip.x > view.x - Sidebar.WIDTH + 0.5:
		_fail("at 130 %% the strip needs %.0f px of its %.0f px slot -- it did not fold" % [strip.x, view.x - Sidebar.WIDTH])
	var side: Vector2 = hud.sidebar.get_combined_minimum_size()
	if side.x > Sidebar.WIDTH + 0.5:
		_fail("at 130 %% the sidebar needs %.0f px; it is %d wide" % [side.x, Sidebar.WIDTH])
	if side.y > view.y - TitleBar.HEIGHT + 0.5:
		_fail("at 130 %% the sidebar needs %.0f px of %.0f under the title bar" % [side.y, view.y - TitleBar.HEIGHT])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_shell_fit: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
