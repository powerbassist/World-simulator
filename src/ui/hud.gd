extends Control

## The instrument furniture laid over the map -- U5a's arrangement, and nothing
## else. Builds the six pieces, places them, and hands them to main.gd to wire.
##
## It owns no game state and no behaviour: every signal these pieces emit is
## connected by main.gd, which is the node holding the Clock and the GameState.
## That keeps this file readable as what it is -- a layout -- and means moving
## the clock cluster to the other corner is an edit here and nowhere else.
##
## **Everything structural is MOUSE_FILTER_IGNORE.** The map is underneath, and
## the boxes that arrange this furniture cover the whole screen; left at the
## Control default they would swallow every pan and every click on a nation.
## Only the plates themselves -- which are PanelContainers, and stop input by
## default -- are meant to be solid.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const PortraitCard = preload("res://src/ui/portrait_card.gd")
const ActionBar = preload("res://src/ui/action_bar.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const MessageStack = preload("res://src/ui/message_stack.gd")
const MapLegend = preload("res://src/ui/map_legend.gd")

const EDGE_MARGIN := 14

## Between the legend and the portrait card under it. Wider than a container
## separation so the two read as two plates stacked, not as one plate with a
## seam -- the same distinction the action bar's sub-row makes.
const LEFT_STACK_GAP := 8

var top_bar
var portrait_card
var action_bar
var clock_cluster
var message_stack
var map_legend


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := _ignore(VBoxContainer.new())
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	top_bar = TopBar.new()
	column.add_child(top_bar)

	var body := _ignore(MarginContainer.new())
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_%s" % side, EDGE_MARGIN)
	column.add_child(body)

	var rows := _ignore(VBoxContainer.new())
	body.add_child(rows)

	# Upper band: the message column, hard left, growing downward from under the
	# top strip. Everything to its right is deliberately empty -- that is the
	# map, and it is the thing the player is meant to be looking at.
	var upper := _ignore(HBoxContainer.new())
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(upper)

	message_stack = MessageStack.new()
	message_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	upper.add_child(message_stack)

	# Lower band: portrait left, commands centre, clock right. Each pinned to the
	# bottom of the band rather than stretched, so a taller cluster grows upward
	# into the map instead of dragging the others' baselines around.
	var lower := _ignore(HBoxContainer.new())
	lower.size_flags_vertical = Control.SIZE_SHRINK_END
	rows.add_child(lower)

	# The left stack: U5c's map legend above U5a's portrait card. Both are about
	# the map rather than about a panel -- who you are, and what the colours under
	# you mean -- so they share a corner. Shrink-end so the pair grows upward into
	# the map and the portrait's baseline never moves.
	var left := _ignore(VBoxContainer.new())
	left.size_flags_vertical = Control.SIZE_SHRINK_END
	left.alignment = BoxContainer.ALIGNMENT_END
	left.add_theme_constant_override("separation", LEFT_STACK_GAP)
	lower.add_child(left)

	map_legend = MapLegend.new()
	map_legend.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(map_legend)

	portrait_card = PortraitCard.new()
	left.add_child(portrait_card)

	lower.add_child(_spacer())

	action_bar = ActionBar.new()
	action_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	lower.add_child(action_bar)

	lower.add_child(_spacer())

	clock_cluster = ClockCluster.new()
	clock_cluster.size_flags_vertical = Control.SIZE_SHRINK_END
	lower.add_child(clock_cluster)


## True when the point is over a solid piece of furniture. main.gd asks before
## treating a click as a click on the map -- the map view sits behind the whole
## HUD rect, so without this a drag started on the portrait card would pan
## Europe.
func is_over_furniture(point: Vector2) -> bool:
	for plate in [top_bar, portrait_card, action_bar, clock_cluster, message_stack, map_legend]:
		if plate == null or not plate.visible:
			continue
		if Rect2(plate.global_position, plate.size).has_point(point):
			return true
	return false


func _spacer() -> Control:
	var spacer := _ignore(Control.new())
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


static func _ignore(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
