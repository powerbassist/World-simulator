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
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")

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


## The window manager hands every panel `setup(state, loader)` on a load: the file the discarded game
## showed is gone with it.
func setup(_state, _loader) -> void:
	_file_id = ""
	_dirty = true


func attach(main) -> void:
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
	_file_id = AudienceDriver.lane_of(_main).current(_file_id)
	var page := FileRead.describe(_main, InboxFiles.of(inbox, _file_id))
	FileView.build(_body, page, func(index: int) -> void:
		InboxFiles.press(inbox, _file_id, index)
		_dirty = true)
	if page.is_empty():
		_still_on_the_desk(inbox)


## After an answer (the void pass, the author's pick "Encore sur ton bureau"): the page says what is
## still on the desk, one button per open file that opens it here, or that nothing waits.
func _still_on_the_desk(inbox) -> void:
	var rest := InboxFiles.list(inbox)
	if rest.is_empty():
		PanelKit.line(_body, Strings.t("Nothing else waits on your signature."), PanelKit.Tone.DIM)
		return
	PanelKit.heading(_body, Strings.t("Still on your desk"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", PanelKit.BUTTON_SEPARATION)
	_body.add_child(column)
	for file in rest:
		var open := PanelKit.sized(Button.new())
		open.text = FileRead.list_title(_main, file)
		var id := String(file["id"])
		# Where the card's own click goes (main.gd's card_activated route, #400 pass 2 T4): the term's
		# programme to the Agenda, an industry card to its tab, a file to this page.
		open.pressed.connect(func() -> void: _main._hud.inbox.card_activated.emit(id))
		column.add_child(open)
