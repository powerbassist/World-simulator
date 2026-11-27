## A screenshot.gd frame plus the visible Control tree behind it, as JSON. Dev-only, never shipped.
##
## Takes every flag screenshot.gd takes (it is that script with one more step at capture time)
## and writes `<out>.json` beside `<out>.png`, for the panel-critique page: each node's path,
## owning script and rect in WINDOW pixels, so a comment on the page leads to the code.
##
##   godot --path "<repo>" --resolution 2560x1440 --script res://tools/panel_dump.gd -- --open budget --out DIR/books.png
extends "res://tools/screenshot.gd"

## The stylebox a class draws behind itself. A Button's follows its draw mode instead.
const BOXES := {"Panel": "panel", "PanelContainer": "panel", "ScrollContainer": "panel", "LineEdit": "normal",
	"Label": "normal", "RichTextLabel": "normal", "ProgressBar": "background"}
const BUTTON_STATES := {BaseButton.DRAW_NORMAL: "normal", BaseButton.DRAW_PRESSED: "pressed",
	BaseButton.DRAW_HOVER: "hover", BaseButton.DRAW_DISABLED: "disabled", BaseButton.DRAW_HOVER_PRESSED: "hover_pressed"}


func _write_frame(path: String, note: String) -> bool:
	if not super(path, note):
		return false
	var nodes: Array = []
	_walk(root, root.get_final_transform(), Rect2(Vector2.ZERO, Vector2(root.size)), 1.0, 0, 0, "", nodes)
	var file := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		printerr("could not write the dump beside %s: %d" % [path, FileAccess.get_open_error()])
		quit(1)
		return false
	file.store_string(JSON.stringify({"width": root.size.x, "height": root.size.y, "frame": path.get_file(), "nodes": nodes}, " "))
	print("dumped %d nodes" % nodes.size())
	return true


## `base` maps the current viewport to window pixels; `clip` is what the ancestors leave visible.
## `layer` and `z` are kept so the page can restore draw order, which is otherwise list order.
func _walk(node: Node, base: Transform2D, clip: Rect2, alpha: float, layer: int, z: int, script: String, out: Array) -> void:
	var own := node.get_script() as Script
	if own != null:
		script = own.resource_path
	if node != root:
		if node is Window:
			var window := node as Window
			if not window.visible:
				return
			base = base * Transform2D(0.0, Vector2(window.position)) * window.get_final_transform()
		elif node is Viewport:
			return  # a SubViewport draws into a texture, not at these coordinates
	if node is CanvasLayer:
		if not (node as CanvasLayer).visible:
			return
		layer = (node as CanvasLayer).layer
	if node is CanvasItem:
		var item := node as CanvasItem
		if not item.visible:
			return
		alpha *= item.modulate.a
		if alpha < 0.01:
			return
		z = z + item.z_index if item.z_as_relative else item.z_index
	if node is Control:
		var control := node as Control
		var rect: Rect2 = base * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
		var shown := rect.intersection(clip)
		if shown.has_area():
			var entry := _describe(control, (base * control.get_global_transform_with_canvas()).get_scale().y)
			entry.merge({"path": str(control.get_path()), "index_path": _index_path(control), "script": script,
				"rect": _list(rect), "clip": _list(shown), "alpha": alpha * control.self_modulate.a, "layer": layer, "z": z})
			out.append(entry)
		if control.clip_contents:
			if not shown.has_area():
				return
			clip = shown
	for child in node.get_children(true):
		_walk(child, base, clip, alpha, layer, z, script, out)


func _describe(control: Control, scale: float) -> Dictionary:
	var own := control.get_script() as Script
	var custom := not control.draw.get_connections().is_empty()
	if own != null:
		custom = custom or own.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "_draw")
	var d := {"class": control.get_class(), "name": str(control.name), "variation": str(control.theme_type_variation),
		"tooltip_text": control.tooltip_text, "custom_draw": custom, "material": control.material != null,
		"image": control is TextureRect or control is TextureButton, "icon": "", "text": ""}
	var box_name: String = BOXES.get(control.get_class(), "")
	var color_name := "font_color"
	if control is Button:
		var button := control as Button
		box_name = BUTTON_STATES[button.get_draw_mode()]
		if box_name != "normal":
			color_name = "font_%s_color" % box_name
		d.text = button.text
		d.align = button.alignment
		if button.icon != null:
			d.image = true
			d.icon = button.icon.resource_path
	elif control is Label:
		var label := control as Label
		d.text = label.text.to_upper() if label.uppercase else label.text
		d.align = label.horizontal_alignment
		d.valign = label.vertical_alignment
		d.wrap = label.autowrap_mode != TextServer.AUTOWRAP_OFF
	elif control is RichTextLabel:
		d.text = (control as RichTextLabel).get_parsed_text()
		d.wrap = true
		color_name = "default_color"
	elif control is LineEdit:
		var edit := control as LineEdit
		d.text = edit.text if edit.text != "" else edit.placeholder_text
	if control is TextureRect and (control as TextureRect).texture != null:
		d.icon = (control as TextureRect).texture.resource_path
	if d.text != "":
		var size_name := "normal_font_size" if control is RichTextLabel else "font_size"
		var font_name := "normal_font" if control is RichTextLabel else "font"
		d.color = _css(control.get_theme_color(color_name))
		d.font_px = control.get_theme_font_size(size_name) * scale
		var font := control.get_theme_font(font_name)
		if font is FontVariation:
			var server := TextServerManager.get_primary_interface()
			var axes: Dictionary = (font as FontVariation).variation_opentype
			d.weight = axes.get(server.name_to_tag("wght"), 400)
			d.width_axis = axes.get(server.name_to_tag("wdth"), 100)
	if box_name != "":
		var box := control.get_theme_stylebox(box_name)
		if box is StyleBoxFlat:
			var flat := box as StyleBoxFlat
			d.box = {"bg": _css(flat.bg_color) if flat.draw_center else "", "border": _css(flat.border_color),
				"widths": [flat.border_width_top * scale, flat.border_width_right * scale,
					flat.border_width_bottom * scale, flat.border_width_left * scale],
				"radii": [flat.corner_radius_top_left * scale, flat.corner_radius_top_right * scale,
					flat.corner_radius_bottom_right * scale, flat.corner_radius_bottom_left * scale]}
	return d


## Child indices from the root: finds the same node in another run of the same state, where an
## auto-generated name (@Label@123) may differ.
func _index_path(node: Node) -> Array:
	var out: Array = []
	while node != root:
		out.push_front(node.get_index(true))
		node = node.get_parent()
	return out


func _list(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.01), snappedf(r.position.y, 0.01), snappedf(r.size.x, 0.01), snappedf(r.size.y, 0.01)]


func _css(c: Color) -> String:
	return "rgba(%d,%d,%d,%.3f)" % [roundi(c.r * 255), roundi(c.g * 255), roundi(c.b * 255), c.a]
