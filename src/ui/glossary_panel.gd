extends PanelContainer

const PanelKit = preload("res://src/ui/panel_kit.gd")
const TermText = preload("res://src/ui/term_text.gd")
const Glossary = preload("res://src/ui/glossary.gd")
const Strings = preload("res://src/ui/strings.gd")

## The A-Z Glossary tab -- V5.1-d3. The tooltips explain a word where it is read;
## this is where the words are found without having been read first: every term of
## data/glossary/terms.json, in alphabetical order under its letter, each one a
## marked term (hover or click it for its plate: the live reading, the deeper terms)
## with its definition and the term's own cross-references beside it. The author's
## aim: a game that teaches -- the play gate's tooltips were never seen, and a tab
## named for what it holds is a thing a player can walk to.
##
## Built from Glossary alone: it reads no GameState, so there is no setup(). Rebuilt
## only while visible (the language is read on build), and N1 per ENTRY -- each
## entry is a section of its own, so a term is marked at its own line and its See-also
## marks every entry it lists (a list, not prose: TermText.cap).
##
## French is parked: the order and the letters are by the raw first character, with
## no accent folding.

var _dirty := true
var _scroll: ScrollContainer
var _bar: HFlowContainer
var _body: VBoxContainer
## letter -> its heading, for the bar's jump.
var _headings := {}
## The language the list was built in: a month's sweep marks every panel dirty, and a
## rebuild would put a reader back at the top, so only a change of language (the one
## thing that moves a word here) rebuilds it.
var _built_in := ""


func _ready() -> void:
	custom_minimum_size = Vector2(520, 560)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_bar = PanelKit.buttons(root)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION * 2)
	_scroll.add_child(_body)


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree():
		return
	_dirty = false
	if _built_in != Strings.language():
		_refresh()


## Every term id, ordered by its shown word, case-insensitively. The shown word, so
## a translated glossary sorts in its own language.
static func entry_ids() -> Array:
	var words := {}
	for id in Glossary.ids():
		words[String(id)] = Glossary.term(String(id))
	var ids: Array = words.keys()
	# The id breaks a tie: sort_custom is not stable, and two calls must agree.
	ids.sort_custom(func(a, b) -> bool:
		var order := String(words[a]).naturalnocasecmp_to(String(words[b]))
		return order < 0 if order != 0 else String(a) < String(b))
	return ids


## The heading letter of a word: its first character, upper-cased; "#" for one that
## is not a letter.
static func letter_of(word: String) -> String:
	var first := word.substr(0, 1)
	return "#" if first.is_empty() or first.to_lower() == first.to_upper() else first.to_upper()


## The letters present, in the order the entries run.
static func letters() -> Array:
	var out: Array = []
	for id in entry_ids():
		var letter := letter_of(Glossary.term(String(id)))
		if not out.has(letter):
			out.append(letter)
	return out


func _refresh() -> void:
	for child in _bar.get_children():
		child.queue_free()
	for child in _body.get_children():
		child.queue_free()
	_headings.clear()
	_built_in = Strings.language()

	var current := ""
	for id in entry_ids():
		var term := Glossary.term(String(id))
		var letter := letter_of(term)
		if letter != current:
			current = letter
			_headings[letter] = PanelKit.heading(_body, letter)
			var jump := Button.new()
			jump.text = letter
			jump.pressed.connect(_jump.bind(letter))
			_bar.add_child(jump)
		_entry(String(id), term)


## One term: its marked word, what it means, and where to read on.
func _entry(id: String, term: String) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	box.set_meta(TermText.SECTION_META, {})
	_body.add_child(box)

	PanelKit.rich(box, "[g=%s]%s[/g]" % [id, term], PanelKit.Tone.PLAIN)
	PanelKit.line(box, Glossary.definition(id), PanelKit.Tone.PLAIN)
	var detail := Glossary.body(id)
	if not detail.is_empty():
		PanelKit.line(box, detail)

	var others: Array = []
	for other in Glossary.see_also(id):
		if Glossary.has(String(other)):
			others.append("[g=%s]%s[/g]" % [other, Glossary.term(String(other))])
	if not others.is_empty():
		var see = PanelKit.rich(box, "", PanelKit.Tone.DIM)  # a TermText: cap is its own
		see.cap = others.size()
		see.set_marked(tr("See also: %s") % ", ".join(others))


func _jump(letter: String) -> void:
	var heading: Control = _headings.get(letter)
	if heading == null or heading.is_queued_for_deletion():
		return
	# A frame's layout may be pending after a rebuild: the offset is read once it lands.
	await get_tree().process_frame
	if is_instance_valid(heading) and heading.is_inside_tree():
		_scroll.scroll_vertical = int(heading.global_position.y - _body.global_position.y)
