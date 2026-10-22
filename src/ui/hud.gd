extends Control

## The chrome around the map -- V5.1-c2.3's BUREAU shell: the title bar across
## the top, the sidebar down the left, the figure strip under the title bar, and
## over the map area the legend and the message column, with the day ribbon at
## the bottom. The workspace (window_manager.gd) docks beside the sidebar,
## under the strip and above the ribbon; this file only arranges the chrome.
##
## It owns no game state and no behaviour: every signal these pieces emit is
## connected by main.gd, which is the node holding the Clock and the GameState.
## That keeps this file readable as what it is -- a layout.
##
## **Everything structural is MOUSE_FILTER_IGNORE.** The map is underneath, and
## the boxes that arrange this furniture cover the whole screen; left at the
## Control default they would swallow every pan and every click on a nation.
## Only the plates themselves -- which are PanelContainers, and stop input by
## default -- are meant to be solid.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const TitleBar = preload("res://src/ui/title_bar.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const Sidebar = preload("res://src/ui/sidebar.gd")
const PortraitCard = preload("res://src/ui/portrait_card.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const MessageStack = preload("res://src/ui/message_stack.gd")
const MapLegend = preload("res://src/ui/map_legend.gd")
const Ribbon = preload("res://src/ui/ribbon.gd")

const EDGE_MARGIN := 14

var title_bar
var top_bar
var sidebar
var portrait_card
var clock_cluster
var message_stack
var map_legend
var ribbon


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := _ignore(VBoxContainer.new())
	column.add_theme_constant_override("separation", 0)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	# The title bar across the top: history, where you are, the clock, save and
	# the menu.
	title_bar = TitleBar.new()
	column.add_child(title_bar)
	clock_cluster = ClockCluster.new()
	title_bar.add_clock(clock_cluster)

	var row := _ignore(HBoxContainer.new())
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	# The sidebar down the left, the portrait card at its head.
	sidebar = Sidebar.new()
	row.add_child(sidebar)
	portrait_card = PortraitCard.new()
	sidebar.add_portrait(portrait_card)

	var right := _ignore(VBoxContainer.new())
	right.add_theme_constant_override("separation", 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	# The figure strip, under the title bar and beside the sidebar.
	top_bar = TopBar.new()
	right.add_child(top_bar)

	# The map area: a plain Control, so nothing drawn over it -- the legend, a
	# column of tall cards -- can change its size and push the ribbon off the
	# bottom (V5.1-0c's "notifications push the UI down").
	var map_area := _ignore(Control.new())
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(map_area)

	# The legend, bottom-left of the map. Hidden by main.gd while a tab covers it.
	var legend_box := _ignore(MarginContainer.new())
	legend_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margins(legend_box)
	map_area.add_child(legend_box)
	var legend_column := _ignore(VBoxContainer.new())
	legend_column.alignment = BoxContainer.ALIGNMENT_END
	legend_box.add_child(legend_column)
	map_legend = MapLegend.new()
	map_legend.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	legend_column.add_child(map_legend)

	# The message column, top-right of the map: the strip of map beside the
	# workspace, where V5.1-c3's inbox docks. It sat hard left until the sidebar
	# took that edge.
	var cards_box := _ignore(MarginContainer.new())
	cards_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margins(cards_box)
	map_area.add_child(cards_box)
	message_stack = MessageStack.new()
	message_stack.size_flags_horizontal = Control.SIZE_SHRINK_END
	message_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cards_box.add_child(message_stack)

	# V2.4a: the day ribbon, the bottom-most plate, the line the month sits on.
	ribbon = Ribbon.new()
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(ribbon)


## True when the point is over a solid piece of furniture. main.gd asks before
## treating a click as a click on the map -- the map view sits behind the whole
## HUD rect, so without this a drag started on the portrait card would pan
## Europe.
func is_over_furniture(point: Vector2) -> bool:
	for plate in [title_bar, top_bar, sidebar, message_stack, map_legend, ribbon]:
		if plate == null or not plate.visible:
			continue
		if Rect2(plate.global_position, plate.size).has_point(point):
			return true
	return false


func _margins(box: MarginContainer) -> void:
	for side in ["left", "right", "top", "bottom"]:
		box.add_theme_constant_override("margin_%s" % side, EDGE_MARGIN)


static func _ignore(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
