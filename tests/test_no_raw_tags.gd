extends SceneTree

## Headless test: godot --headless --script res://tests/test_no_raw_tags.gd
## Non-zero exit on any failure.
##
## V5.1-d2, the rendered-panel assertion the brief asked for: no marked-term tag
## ([g=...] / [p=...]) reaches the screen raw. The markup is the writers' (data rows,
## msgids); a line that prints it through a plain Label, a button or a tooltip shows
## the player "[g=approval]approval[/g]". Every registered window is opened in the
## real game and every Label, Button, rich line (its parsed text) and tooltip under
## it, the inbox's cards and the strip included, is read -- in English and French.

const Strings = preload("res://src/ui/strings.gd")

const RAW := ["[g=", "[/g]", "[p=", "[/p]"]

var _failures: Array[String] = []
var _main
var _frame := 0
var _ids: Array = []
var _at := 0
var _language := "en"


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _ids.is_empty():
		_ids = _main._windows.panel_ids()
	if _at < _ids.size():
		_main._windows.close_all()
		_main._windows.open(String(_ids[_at]))
		_at += 1
		return false
	# The last window has had its frame; then the HUD and the inbox.
	if _at == _ids.size():
		_scan(_main._windows, "the windows")
		_scan(_main._hud, "the HUD")
		_at += 1
		if _language == "en":
			_language = "fr"
			Strings.set_language("fr")
			_main._windows.mark_all_dirty()
			_at = 0
		return false
	Strings.set_language("en")
	_finish()
	return true


## Runs over every window as it opens, too: a window shows its body only while open.
func _scan(node: Node, where: String) -> void:
	for child in _all(node):
		var text := ""
		if child is RichTextLabel:
			text = (child as RichTextLabel).get_parsed_text()
		elif child is Label or child is Button:
			text = String(child.text)
		if child is Control:
			text += " " + String((child as Control).tooltip_text)
		for raw in RAW:
			if text.contains(raw):
				_fail("%s (%s): a raw tag reaches the screen in %s: %s" % [where, _language, child.name, text.strip_edges().left(160)])
				break


func _all(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


func _fail(message: String) -> void:
	if not _failures.has(message):
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_no_raw_tags: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
