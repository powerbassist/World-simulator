extends PanelContainer

## The player, bottom-left, for the whole game -- U5a.
##
## This is the piece that makes the difference the session was asked for: the
## game was a dashboard over a country, and a dashboard has no one sitting at
## it. A face in the corner of every screen is what turns "France's approval is
## 50%" into "they are at 50% with me".
##
## Reads state, never writes it. The approval shown is the *polled* figure, the
## same one top_bar.gd and polling_panel.gd show -- a president reads the polls,
## not the model, and three surfaces disagreeing about the number would be worse
## than any of them being wrong.
##
## The bust is drawn, not an image. docs/tiers/v1.md schedules no portrait art
## and the roster is fictional, so a placeholder silhouette is the honest thing
## to ship: it says "your character goes here" without pretending to be a face.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Flag = preload("res://src/ui/flag.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")

const CARD_SIZE := Vector2(268, 96)
const FLAG_SIZE := Vector2(30, 20)

var _state
var _loader

var _bust: Control
var _mood: Control
var _approval_label: Label
var _leader_label: Label
var _nation_label: Label
var _flag: Control


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size = CARD_SIZE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_bust = Bust.new()
	_bust.custom_minimum_size = Vector2(54, 74)
	row.add_child(_bust)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)

	var approval_row := HBoxContainer.new()
	approval_row.add_theme_constant_override("separation", 8)
	column.add_child(approval_row)

	_approval_label = Label.new()
	_approval_label.theme_type_variation = UiTheme.HERO
	approval_row.add_child(_approval_label)

	_mood = Mood.new()
	_mood.custom_minimum_size = Vector2(26, 26)
	_mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	approval_row.add_child(_mood)

	var approval_caption := Label.new()
	approval_caption.text = "APPROVAL"
	approval_caption.theme_type_variation = UiTheme.MICRO
	column.add_child(approval_caption)

	_leader_label = Label.new()
	_leader_label.theme_type_variation = UiTheme.CAPTION
	column.add_child(_leader_label)

	var nation_row := HBoxContainer.new()
	nation_row.add_theme_constant_override("separation", 7)
	column.add_child(nation_row)

	_flag = Flag.new()
	_flag.custom_minimum_size = FLAG_SIZE
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nation_row.add_child(_flag)

	_nation_label = Label.new()
	_nation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nation_row.add_child(_nation_label)


## Called once at startup. The name, title and flag are static content -- they
## are read here rather than in refresh() so the per-day path stays three label
## writes.
func setup(state, loader) -> void:
	_state = state
	_loader = loader

	var nation = loader.nations.get(state.player_nation_id, null)
	if nation == null:
		return
	_nation_label.text = nation.nation_name
	_leader_label.text = "%s, %s" % [loader.person_name(nation.leader_person_id), nation.leader_title]
	_flag.setup(nation.flag_bands, nation.flag_layout)
	refresh()


func refresh() -> void:
	if _state == null:
		return
	var ns = _state.player()
	var shown := PollNoise.displayed(
		PollNoise.poll_id(_state.year, _state.month), PollingPanel.HEADLINE_KEY, ns.overall_approval_pct
	)
	_approval_label.text = "%.0f%%" % shown
	_mood.set_approval(shown)


## The placeholder the session shipped instead of portrait art. Shoulders, neck,
## head, and the suggestion of a collar -- enough to read as a person at 54x74
## and obviously not a likeness, which is the point until there is a real
## character to draw.
class Bust extends Control:
	const UiTheme = preload("res://src/ui/ui_theme.gd")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := UiTheme.SLATE.lightened(0.06)
		var skin := UiTheme.TEXT_DIM.darkened(0.10)

		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.INK)

		# Shoulders: a wide, shallow ellipse cropped by the bottom edge. Wider
		# than the head by a good margin -- at this size a narrow body reads as
		# a lightbulb rather than as a person.
		_draw_ellipse(Vector2(w * 0.5, h * 1.30), Vector2(w * 0.62, h * 0.52), body)

		# Neck, then head. Drawn after the shoulders so the neck disappears
		# behind them instead of ending in a visible stump.
		draw_rect(Rect2(Vector2(w * 0.43, h * 0.44), Vector2(w * 0.14, h * 0.24)), skin)
		_draw_ellipse(Vector2(w * 0.5, h * 0.34), Vector2(w * 0.17, h * 0.20), skin)

		# Collar, as two strokes rather than a shape -- it is what makes the
		# silhouette read as a suit instead of a bust in a museum.
		draw_line(Vector2(w * 0.34, h * 0.72), Vector2(w * 0.50, h * 0.98), UiTheme.INK, 2.0)
		draw_line(Vector2(w * 0.66, h * 0.72), Vector2(w * 0.50, h * 0.98), UiTheme.INK, 2.0)

		# The brass hairline the plate carries on its top edge, repeated along
		# the bottom of the frame so the bust reads as inset rather than as a
		# hole punched in the card.
		draw_line(Vector2(0, h - 1), Vector2(w, h - 1), UiTheme.ACCENT, 1.0)

	func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for i in range(24):
			var angle := TAU * i / 24.0
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_colored_polygon(points, color)


## A face, not a number. The approval figure is already right beside it, so what
## this adds is a reading the player takes at a glance without parsing digits --
## the same job the reference's smiley does.
class Mood extends Control:
	const UiTheme = preload("res://src/ui/ui_theme.gd")

	## Below the first the country is against you, above the second it is with
	## you. Both sit either side of 50 rather than on it, so a government
	## hovering at the neutral point does not flicker between two faces every
	## month on poll noise alone.
	const UNHAPPY_BELOW := 44.0
	const HAPPY_ABOVE := 56.0

	var _approval := 50.0

	func set_approval(value: float) -> void:
		_approval = value
		queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 1.0

		var tint := UiTheme.TEXT_DIM
		var curve := 0.0
		if _approval < UNHAPPY_BELOW:
			tint = UiTheme.BAD
			curve = -radius * 0.34
		elif _approval > HAPPY_ABOVE:
			tint = UiTheme.GOOD
			curve = radius * 0.34

		draw_arc(center, radius, 0.0, TAU, 28, tint, 1.5)
		draw_circle(center + Vector2(-radius * 0.34, -radius * 0.22), 1.6, tint)
		draw_circle(center + Vector2(radius * 0.34, -radius * 0.22), 1.6, tint)

		# The mouth is one quadratic through three points, so neutral is a flat
		# line rather than a special case.
		var left := center + Vector2(-radius * 0.42, radius * 0.28)
		var right := center + Vector2(radius * 0.42, radius * 0.28)
		var control := center + Vector2(0.0, radius * 0.28 + curve)
		var mouth := PackedVector2Array()
		for i in range(9):
			var t := i / 8.0
			mouth.append(left.lerp(control, t).lerp(control.lerp(right, t), t))
		draw_polyline(mouth, tint, 1.5)
