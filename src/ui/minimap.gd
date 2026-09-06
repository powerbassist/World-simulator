extends Control

## The world thumbnail in the clock cluster's reserved slot -- U5b fills the box
## clock_cluster.gd has been holding open at its final size since U5a.
##
## A view onto the map, not a peer of it: it holds a reference to the map view,
## reads visible_lonlat_rect() to draw the viewport rectangle, and calls
## center_on_lonlat() when clicked. Nothing here touches GameState, and the map
## view knows nothing about this file.
##
## Sets no custom_minimum_size on purpose. The slot is sized by
## ClockCluster.MINIMAP_SIZE and this fills it; a minimum of its own would let the
## thumbnail grow the cluster, which moves every control above it -- exactly the
## failure the slot was reserved in advance to avoid.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const MapRaster = preload("res://src/ui/map_raster.gd")

const SEA := Color(0.043, 0.075, 0.129)
const VIEWPORT_BOX := Color(0.788, 0.635, 0.153, 0.95)  ## brass, the one accent
const VIEWPORT_FILL := Color(0.788, 0.635, 0.153, 0.12)
const HOME_MARKER := Color(0.94, 0.96, 1.0, 0.95)
const HOME_RADIUS := 2.0

var _map_view
var _texture: ImageTexture = null
var _home_lonlat := Vector2.ZERO
var _has_home := false

## Never equal to a real view rect, so the first frame redraws.
var _last_view := Rect2(-1.0, -1.0, -1.0, -1.0)


func setup(map_view, loader, state) -> void:
	_map_view = map_view
	_texture = MapRaster.texture()

	_has_home = false
	if state != null and loader != null:
		var player = state.player()
		if player != null and loader.nations.has(player.id):
			var geo_id: String = loader.nations[player.id].geo_id
			if loader.label_points.has(geo_id):
				_home_lonlat = loader.label_points[geo_id]
				_has_home = true
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _process(_delta: float) -> void:
	# The viewport rectangle has to follow every pan and zoom, and the map view
	# emits no signal for those -- it is the background layer and deliberately
	# knows nothing downstream of it. But following a view is polling it, not
	# redrawing at it: the redraw sits behind a change test on the same rect
	# this control always read. The every-frame redraw measured 0.35 ms
	# (frame_probe.gd, the "no minimap" rows) and drew nothing new on a still
	# map; a still view also cannot stale the draw, because this control
	# carries no sim content -- raster, home dot, viewport box only.
	if _map_view == null:
		return
	var view: Rect2 = _map_view.visible_lonlat_rect()
	if view != _last_view:
		_last_view = view
		queue_redraw()


## The world drawn plate carrée into this control, letterboxed rather than
## cropped: the slot is 176x104 and the world is 2:1, so it fits to width and
## centres vertically. Cropping would hide the poles, which is where a viewport
## rectangle dragged too far north would go.
func _world_rect() -> Rect2:
	var lon_span := MapRaster.LON_MAX - MapRaster.LON_MIN
	var lat_span := MapRaster.LAT_MAX - MapRaster.LAT_MIN
	# Not named `scale` -- Control has a property by that name and shadowing it
	# here reads as a transform change that never happens.
	var px_per_deg := minf(size.x / lon_span, size.y / lat_span)
	var drawn := Vector2(lon_span, lat_span) * px_per_deg
	return Rect2((size - drawn) / 2.0, drawn)


func _lonlat_to_local(lon: float, lat: float) -> Vector2:
	var rect := _world_rect()
	var u := (lon - MapRaster.LON_MIN) / (MapRaster.LON_MAX - MapRaster.LON_MIN)
	var v := (MapRaster.LAT_MAX - lat) / (MapRaster.LAT_MAX - MapRaster.LAT_MIN)
	return rect.position + Vector2(u * rect.size.x, v * rect.size.y)


func _local_to_lonlat(point: Vector2) -> Vector2:
	var rect := _world_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ZERO
	var u := (point.x - rect.position.x) / rect.size.x
	var v := (point.y - rect.position.y) / rect.size.y
	return Vector2(
		MapRaster.LON_MIN + u * (MapRaster.LON_MAX - MapRaster.LON_MIN),
		MapRaster.LAT_MAX - v * (MapRaster.LAT_MAX - MapRaster.LAT_MIN)
	)


## Public rather than only reachable through _gui_input, so a headless test can
## drive it -- the same rule map_view.gd states for its own camera methods.
func jump_to_local(point: Vector2) -> void:
	if _map_view == null:
		return
	var lonlat := _local_to_lonlat(point)
	_map_view.center_on_lonlat(lonlat.x, lonlat.y)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		jump_to_local(event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		jump_to_local(event.position)


func _draw() -> void:
	var rect := _world_rect()
	if _texture != null:
		draw_texture_rect(_texture, rect, false)
	else:
		draw_rect(rect, SEA)

	if _has_home:
		draw_circle(_lonlat_to_local(_home_lonlat.x, _home_lonlat.y), HOME_RADIUS, HOME_MARKER)

	if _map_view == null:
		return
	var view: Rect2 = _map_view.visible_lonlat_rect()
	var top_left := _lonlat_to_local(view.position.x, view.position.y + view.size.y)
	var bottom_right := _lonlat_to_local(view.position.x + view.size.x, view.position.y)
	var box := Rect2(top_left, bottom_right - top_left)
	# One pixel minimum on each axis: zoomed all the way in the window is a few
	# tenths of a degree, which rounds to nothing and reads as "no viewport" when
	# the truth is the opposite.
	box.size = box.size.max(Vector2.ONE)
	draw_rect(box, VIEWPORT_FILL, true)
	draw_rect(box, VIEWPORT_BOX, false, 1.0)
