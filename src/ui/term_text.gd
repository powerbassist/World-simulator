extends RichTextLabel

## Prose that can mark a glossary term -- V5.1-c, docs/design/glossary-tooltips.md.
## A writer puts [g=id]word[/g] around a word (the author's call: markup in the
## source, the only way to tell the two meanings of "bloc" apart); this label draws
## it as the engine's own dashed term and routes its hover and click to the tooltip
## layer.
##
## **The look is the engine's, proven at step 0 (windowed, 4.7.2):** a word inside
## [url=term:id][hint=]...[/hint][/url] with META_UNDERLINE_NEVER is underlined by
## [hint]'s dashes alone, in the text's own colour at the theme's underline_alpha,
## and the EMPTY hint suppresses the engine's tooltip -- no _make_custom_tooltip
## override, which would hand the engine a control to wrap in an empty plate.
##
## **PASS, not STOP:** a Label's clicks fall through to its row, and an inbox card
## opens on a click on its body. The price, also measured at step 0: an ancestor
## with tooltip_text shows its tip over a term. No row the terms reach has one. A
## press ON a term is taken (N4: a term on a clickable row must not fire the row).
##
## The layer is found through GROUP at hover time, so a label with none around it
## (the menu, a bare test) simply does nothing.

const Glossary = preload("res://src/ui/glossary.gd")

const GROUP := &"glossary_tip"
## N2: a block marks at most this many terms; past the cap they read as words.
const MAX_MARKED := 3
const META_PREFIX := "term:"

## The tooltip level this text sits in: 0 for prose on a panel or a card, n for
## the body of the n-th plate, whose terms open plate n + 1.
var level := 0
## Ids open up the chain (N5): drawn plain here.
var exclude := PackedStringArray()

var _hovered := ""

static var _tag: RegEx
static var _plain_tag: RegEx


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_underlined = RichTextLabel.META_UNDERLINE_NEVER
	mouse_filter = Control.MOUSE_FILTER_PASS
	meta_hover_started.connect(_on_hover_started)
	meta_hover_ended.connect(_on_hover_ended)


## The only writer of `text`: prose in, the engine's markup out.
func set_marked(source: String) -> void:
	text = markup(source, exclude)


## Every "[" of the prose escaped first -- prose is not BBCode -- then each
## [g=id]word[/g] made a term, under N1 (once an id), N2 (MAX_MARKED a block) and
## N5 (`skip`). An unknown id reads as its word, loudly: the table is the list.
static func markup(source: String, skip := PackedStringArray()) -> String:
	if _tag == null:
		_tag = RegEx.create_from_string("\\[lb\\]g=([A-Za-z0-9_]+)\\](.*?)\\[lb\\]/g\\]")
	var escaped := source.replace("[", "[lb]")
	var out := ""
	var at := 0
	var marked := {}
	for m in _tag.search_all(escaped):
		out += escaped.substr(at, m.get_start() - at)
		var id := m.get_string(1)
		var word := m.get_string(2)
		if not Glossary.has(id):
			push_error("glossary: text marks '%s', which is no entry" % id)
			out += word
		elif marked.has(id) or skip.has(id) or marked.size() >= MAX_MARKED:
			out += word
		else:
			marked[id] = true
			out += "[url=%s%s][hint=]%s[/hint][/url]" % [META_PREFIX, id, word]
		at = m.get_end()
	return out + escaped.substr(at)


## The same prose with its marks dropped and their words kept, for a sink that
## cannot draw a term: a Button's tooltip_text is a plain string. Silent on an
## unknown id -- markup() is the loud reader, and P1 fails the id before it ships.
static func plain(source: String) -> String:
	if _plain_tag == null:
		_plain_tag = RegEx.create_from_string("\\[g=[A-Za-z0-9_]+\\](.*?)\\[/g\\]")
	return _plain_tag.sub(source, "$1", true)


func _gui_input(event: InputEvent) -> void:
	if _hovered.is_empty():
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		var tip := _tip()
		if tip != null:
			tip.click(_hovered, _anchor(), level)


func _notification(what: int) -> void:
	# A card dismissed or a window closed under the pointer: the term is gone,
	# so it is no longer hovered.
	if (what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not visible)) \
			and not _hovered.is_empty():
		_on_hover_ended(META_PREFIX + _hovered)


func _on_hover_started(meta) -> void:
	var meta_text := String(meta)
	if not meta_text.begins_with(META_PREFIX):
		return
	_hovered = meta_text.substr(META_PREFIX.length())
	var tip := _tip()
	if tip != null:
		tip.enter(_hovered, _anchor(), level)


func _on_hover_ended(meta) -> void:
	if String(meta) != META_PREFIX + _hovered:
		return
	_hovered = ""
	var tip := _tip()
	if tip != null:
		tip.leave(level)


func _tip() -> Node:
	return get_tree().get_first_node_in_group(GROUP) if is_inside_tree() else null


## No glyph rectangle exists (the class reference has none), so the term is where
## the pointer is: one line tall, centred on it.
func _anchor() -> Rect2:
	var line := get_theme_font("normal_font").get_height(get_theme_font_size("normal_font_size"))
	var at := get_global_mouse_position()
	return Rect2(at.x, at.y - line / 2.0, 1.0, line)
