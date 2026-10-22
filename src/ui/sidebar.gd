extends PanelContainer

## The left dock -- V5.1-c2.3, the BUREAU board's sidebar, replacing U5a's
## bottom action bar. Who you are (the portrait card, compact), the Inbox and
## the Agenda, then the domains, each marked when something in it awaits the
## player.
##
## The domains are `domains.gd`'s table filtered by what is registered, so a
## domain with no tab is not listed (the author's call 1) and a surface added
## with a row in that table appears here without an edit to this file.
##
## Proposes, never commands: an entry emits `navigate`, and main.gd decides
## what opens -- refused under a scene, as the keys are.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const Domains = preload("res://src/ui/domains.gd")

signal navigate(domain_id: String)

const WIDTH := 232
## The Inbox's id in `navigate`, beside the domain ids. Until V5.1-c3 builds
## the inbox, it opens Dispatches.
const INBOX := "inbox"
const ENTRY_HEIGHT := 36

var portrait_card: Control
var _list: VBoxContainer
var _entries := {}      # domain id -> its Button
var _pills := {}        # domain id -> its count Label
var _selected := ""
var _pending: Array = []


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size = Vector2(WIDTH, 0)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)


## The portrait card goes on top; hud.gd builds it so main.gd keeps reaching it
## as `_hud.portrait_card`.
func add_portrait(card: Control) -> void:
	portrait_card = card
	_list.add_child(card)
	_list.move_child(card, 0)


## One entry per visible domain, after every tab is registered. The Inbox and
## the Agenda lead, as on the board; then the heading and the rest in the
## table's order.
func build(registered: Array) -> void:
	for child in _list.get_children():
		if child != portrait_card:
			_list.remove_child(child)
			child.queue_free()
	_entries.clear()
	_pills.clear()
	_add_link(INBOX, tr("Inbox"), Domains.ICONS + "mail.svg")
	var shown := Domains.visible(registered)
	if shown.has("agenda"):
		_add_link("agenda", tr(Domains.title("agenda")), Domains.icon_path("agenda"))
	var heading := Label.new()
	heading.text = tr("DOMAINS")
	heading.theme_type_variation = UiTheme.MICRO
	_list.add_child(heading)
	for id in shown:
		if id != "agenda":
			_add_link(id, tr(Domains.title(id)), Domains.icon_path(id))
	select(_selected)
	show_pending(_pending)


## Every listed id in order, the Inbox first.
func entry_ids() -> Array:
	return _entries.keys()


## The open domain wears the pressed state -- the accent, "you are here".
func select(domain_id: String) -> void:
	_selected = domain_id
	for id in _entries.keys():
		_entries[id].set_pressed_no_signal(id == domain_id)


func selected() -> String:
	return _selected


## The windows holding something that awaits the player (pending.gd's ids),
## counted per domain. Dispatches counts on the Inbox too, where a decision is
## answered.
func show_pending(window_ids: Array) -> void:
	_pending = window_ids.duplicate()
	var counts := {}
	for window_id in window_ids:
		var domain := Domains.domain_of(String(window_id))
		counts[domain] = int(counts.get(domain, 0)) + 1
		if window_id == "events":
			counts[INBOX] = int(counts.get(INBOX, 0)) + 1
	for id in _pills.keys():
		var count: int = int(counts.get(id, 0))
		_pills[id].text = str(count)
		_pills[id].visible = count > 0


func pending_domains() -> Array:
	var out: Array = []
	for id in _pills.keys():
		if _pills[id].visible:
			out.append(id)
	return out


func _add_link(id: String, title: String, icon_path: String) -> void:
	var button := Button.new()
	button.text = title
	button.tooltip_text = title
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)
	button.theme_type_variation = UiTheme.SUBROW_BUTTON
	# No focus, as on every piece of chrome: a clicked entry that kept the focus
	# would take Space, the pause key, for itself (V5.1-0c's forfeited Agenda).
	button.focus_mode = Control.FOCUS_NONE
	if not icon_path.is_empty():
		button.icon = Icon.load_icon(icon_path, UiTheme.TEXT, 18)
	button.pressed.connect(func():
		# The press is a request; the mark follows what actually opened.
		button.set_pressed_no_signal(id == _selected)
		navigate.emit(id)
	)
	_list.add_child(button)
	_entries[id] = button

	# The count is a STATUS tone -- something waits on you, the attention colour --
	# never the played nation's accent, which marks only "you are here".
	var pill := Label.new()
	pill.add_theme_color_override("font_color", UiTheme.WARN)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	pill.offset_left = -28.0
	pill.offset_right = -8.0
	pill.offset_top = -10.0
	pill.offset_bottom = 10.0
	pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.hide()
	button.add_child(pill)
	_pills[id] = pill
