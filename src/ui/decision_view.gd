extends MarginContainer

## The docked file page -- V5.3 screen 3, B's card (the author picked decision C: the month's
## folder, with this docked card for a file met mid-month). A click on an event or request
## card in the inbox opens it as a workspace tab, as the audience opens: the same page the
## folder shows (file_view.gd), in the dock's room.
##
## It owns no state but WHICH file. A file that is gone -- answered here or in the folder,
## lapsed at a month tick, a load -- reads "This file has been answered." and nothing else;
## the page is rebuilt when marked dirty (every command marks every panel) while it is shown,
## and its answer is Inbox.press, the card's own door, so main.gd and the request lane keep
## every rule they had.

const FileRead = preload("res://src/ui/file_read.gd")
const FileView = preload("res://src/ui/file_view.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")

var _main
var _file_id := ""
var _body: VBoxContainer
var _dirty := true


## The workspace page wraps this in its own plate and scroll (tab_page.gd), so this is content only.
func _ready() -> void:
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_%s" % side, 18)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)


func setup(main) -> void:
	_main = main
	main._hud.inbox.card_dismissed.connect(func(id: String) -> void:
		if id == _file_id:
			_dirty = true)


func show_file(card_id: String) -> void:
	_file_id = card_id
	_dirty = true


func file_id() -> String:
	return _file_id


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and is_visible_in_tree() and _main != null and _main._state != null:
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var inbox = _main._hud.inbox
	var page := FileRead.describe(_main, InboxFiles.of(inbox, _file_id))
	FileView.build(_body, page, func(index: int) -> void:
		InboxFiles.press(inbox, _file_id, index)
		_dirty = true)
