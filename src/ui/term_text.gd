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
## V5.1-d1b2 (G9): a person's name, marked [p=id]Name[/p], links to their card --
## a solid underline, so a name never reads as a dashed glossary term.
const PERSON_PREFIX := "person:"
## The meta a section carries: term id -> WeakRef of the line that marks it (N1).
const SECTION_META := &"term_section"

## The tooltip level this text sits in: 0 for prose on a panel or a card, n for
## the body of the n-th plate, whose terms open plate n + 1.
var level := 0
## Ids open up the chain (N5): drawn plain here.
var exclude := PackedStringArray()
## N2's cap for this text. A LIST of terms (a plate's See-also line) lifts it: it
## is not prose, and every entry in it is the reason it is there (V5.1-d2).
var cap := MAX_MARKED

var _hovered := ""
var _person := ""

static var _tag: RegEx
static var _plain_tag: RegEx
static var _person_tag: RegEx
static var _marked_ids: RegEx = RegEx.create_from_string("\\[url=term:([A-Za-z0-9_]+)\\]")


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
	# N1 per SECTION (V5.1-d2, in code where Content cut by hand): an id another
	# live line of this section already marks is drawn plain here.
	var section := _section()
	var taken := exclude.duplicate()
	if section != null:
		var marks: Dictionary = section.get_meta(SECTION_META)
		for id in marks:
			var holder = (marks[id] as WeakRef).get_ref()
			if holder != null and holder != self and not holder.is_queued_for_deletion():
				taken.append(id)
	text = markup(source, taken, cap)
	if section != null:
		# What this line marked before and no longer does is free again (review pass 1).
		var marks: Dictionary = section.get_meta(SECTION_META)
		for id in marks.keys():
			if (marks[id] as WeakRef).get_ref() == self:
				marks.erase(id)
		for m in _marked_ids.search_all(text):
			marks[m.get_string(1)] = weakref(self)


## The term ids `label` marks, in reading order.
static func term_ids(label: RichTextLabel) -> PackedStringArray:
	var ids := PackedStringArray()
	for m in _marked_ids.search_all(label.text):
		ids.append(m.get_string(1))
	return ids


## The nearest ancestor that is a section for N1: a PanelKit.section body, or the
## panel a window is registered with (window_manager.gd). None for a card or a plate:
## each is its own block.
func _section() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_meta(SECTION_META):
			return node
		node = node.get_parent()
	return null


## Every "[" of the prose escaped first -- prose is not BBCode -- then each
## [g=id]word[/g] made a term, under N1 (once an id), N2 (MAX_MARKED a block) and
## N5 (`skip`). An unknown id reads as its word, loudly: the table is the list.
## Last, each [p=id]Name[/p] made a person link (no cap: a name is not a term).
static func markup(source: String, skip := PackedStringArray(), limit := MAX_MARKED) -> String:
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
		elif marked.has(id) or skip.has(id) or marked.size() >= limit:
			out += word
		else:
			marked[id] = true
			out += "[url=%s%s][hint=]%s[/hint][/url]" % [META_PREFIX, id, word]
		at = m.get_end()
	out += escaped.substr(at)
	if _person_tag == null:
		_person_tag = RegEx.create_from_string("\\[lb\\]p=([A-Za-z0-9_]+)\\](.*?)\\[lb\\]/p\\]")
	return _person_tag.sub(out, "[url=%s$1][u]$2[/u][/url]" % PERSON_PREFIX, true)


## The same prose with its marks dropped and their words kept, for a sink that
## cannot draw a term: a Button's tooltip_text is a plain string. Silent on an
## unknown id -- markup() is the loud reader, and P1 fails the id before it ships.
static func plain(source: String) -> String:
	if _plain_tag == null:
		_plain_tag = RegEx.create_from_string("\\[([gp])=[A-Za-z0-9_]+\\](.*?)\\[/\\1\\]")
	return _plain_tag.sub(source, "$2", true)


func _gui_input(event: InputEvent) -> void:
	if _hovered.is_empty() and _person.is_empty():
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		var tip := _tip()
		if tip != null and not _person.is_empty():
			tip.person_click(_person, _anchor())
		elif tip != null:
			tip.click(_hovered, _anchor(), level)


func _notification(what: int) -> void:
	# A card dismissed or a window closed under the pointer: the term is gone,
	# so it is no longer hovered.
	if what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not visible):
		if not _hovered.is_empty():
			_on_hover_ended(META_PREFIX + _hovered)
		if not _person.is_empty():
			_on_hover_ended(PERSON_PREFIX + _person)


func _on_hover_started(meta) -> void:
	var meta_text := String(meta)
	if meta_text.begins_with(PERSON_PREFIX):
		_person = meta_text.substr(PERSON_PREFIX.length())
		var host := _tip()
		if host != null:
			host.person_enter(_person, _anchor())
		return
	if not meta_text.begins_with(META_PREFIX):
		return
	_hovered = meta_text.substr(META_PREFIX.length())
	var tip := _tip()
	if tip != null:
		tip.enter(_hovered, _anchor(), level)


func _on_hover_ended(meta) -> void:
	if not _person.is_empty() and String(meta) == PERSON_PREFIX + _person:
		_person = ""
		var host := _tip()
		if host != null:
			host.person_leave()
		return
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
