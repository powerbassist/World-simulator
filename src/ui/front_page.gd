extends PanelContainer

## The front pages -- V5.2 d (docs/design/v5.2-d-spec.md section 4; the author,
## 2026-10-25: "des popup de titres de journaux qui marquent des events
## importants"). Two papers headline the month's biggest story, each from its own
## side: the most friendly and the most hostile outlet, masthead over headline,
## and at most two more stories as one line each.
##
## **A note, never a hold.** It touches no clock and no hold reason, sits on the
## HUD and not on the screen stack (it owns no key and no Escape), and puts itself
## away: LIFE_SECONDS of running clock with the pointer off it, so a paused player
## or one reading it loses nothing. Put away, it leaves its headlines as one note
## in the inbox, where the month's news is kept -- the card is the moment, the
## note the record.
##
## **The sim chooses, the card prints.** Which story, which papers and each
## paper's tone come in the month report's `front_page` entry (Systems'): the
## outlet choice reads Media's alignment, and src/ui never copies it. The card
## reads the entry with defaults throughout, so a change to its shape costs one
## function. A paper whose headline is not written is dropped, never shown as a
## key; a card with no headline left does not show (headlines.gd).
##
## Holds no game state: show_entry() is handed the state and the loader each time,
## so a loaded game never prints the previous one's names. The one exception is a
## card HELD for an election night (the parent's call, 2026-10-30): the papers
## must not print the result while the count is still declaring it, so an entry
## handed over with the result plate waits for that plate's `dismissed`, and
## clear() drops it with the rest of a discarded game's furniture.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Motion = preload("res://src/ui/motion.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Headlines = preload("res://src/ui/headlines.gd")
const President = preload("res://src/sim/president.gd")

## Wide enough for two headlines side by side at the lead size, three lines each.
const WIDTH := 640
## Seconds of running clock before the card puts itself away: two headlines and
## two short lines are about forty words, read in well under this.
const LIFE_SECONDS := 15.0
## The spec's cap on "also on the front page".
const ALSO_MAX := 2
const TONE_WORDS := {
	"friendly": "Close to the government",  # i18n: msgid
	"neutral": "Neutral on the government",  # i18n: msgid
	"hostile": "Opposed to the government",  # i18n: msgid
}

## Where the card's record goes when it is put away (hud.gd sets it).
var inbox
var _clock
var _left := 0.0
var _date: Label
var _papers: HBoxContainer
var _also: VBoxContainer
var _record := PackedStringArray()
## A held entry and what show_entry() needs to print it, or empty.
var _held := {}


func _ready() -> void:
	name = "FrontPage"  # i18n: ok a node name, found by tests
	theme_type_variation = UiTheme.PLATE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	var column := PanelKit.padded(self, 14, 10)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	var title := Label.new()
	title.text = tr("FRONT PAGES")
	title.theme_type_variation = UiTheme.HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_date = Label.new()
	_date.theme_type_variation = UiTheme.CAPTION
	header.add_child(_date)
	var close := Button.new()
	close.name = "Close"  # i18n: ok a node name, found by tests
	close.text = "X"  # i18n: ok the inbox cards' own close mark
	close.tooltip_text = tr("Put the papers away. Their headlines stay in your inbox.")
	close.theme_type_variation = UiTheme.SUBROW_BUTTON
	close.pressed.connect(dismiss)
	header.add_child(close)

	_papers = HBoxContainer.new()
	_papers.add_theme_constant_override("separation", 24)
	column.add_child(_papers)
	_also = VBoxContainer.new()
	_also.add_theme_constant_override("separation", 2)
	column.add_child(_also)
	hide()


## Show the month's front page, `entry` as the month report carries it. Replaces a
## card still up (at most one a month, D8; the older goes to the inbox first) --
## but only once there is something to show: an empty month, or an entry whose
## headlines are none of them written, leaves the card the player is reading where
## it is and returns false.
func show_entry(entry: Dictionary, state, loader, clock, count_plate: Control = null) -> bool:
	if entry.is_empty() or state == null or loader == null or state.player() == null:
		return false
	# A month with an election result: the card waits for the count's plate.
	if count_plate != null:
		_held = {"entry": entry, "state": state, "loader": loader, "clock": clock}
		if not count_plate.dismissed.is_connected(_release):
			count_plate.dismissed.connect(_release)
		return false
	var vars := _vars(state.player(), loader)
	var outlets := _outlets(loader, String(state.player_nation_id))
	var kind := String(entry.get("kind", "event"))
	var id := String(entry.get("id", ""))
	var answer := String(entry.get("answer", ""))
	var papers := []   # [masthead, tone, headline]
	for paper in _dicts(entry.get("papers", [])):
		var outlet = outlets.get(String(paper.get("outlet", "")), null)
		var tone := String(paper.get("tone", ""))
		var words := Headlines.text(kind, id, answer, tone, vars)
		if outlet != null and not words.is_empty():
			papers.append([_masthead(outlet), tone, words])
	if papers.is_empty():
		return false
	var also := PackedStringArray()
	for story in _dicts(entry.get("also", [])):
		var outlet = outlets.get(String(story.get("outlet", "")), null)
		var words := Headlines.text(String(story.get("kind", "event")), String(story.get("id", "")),
			String(story.get("answer", "")), String(story.get("tone", "")), vars)
		if outlet != null and not words.is_empty() and also.size() < ALSO_MAX:
			also.append(tr("%s: %s") % [_masthead(outlet), words])

	dismiss()
	for box in [_papers, _also]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for paper in papers:
		_paper(paper[0], paper[1], paper[2])
	if not also.is_empty():
		var heading := Label.new()
		heading.text = tr("ALSO ON THE FRONT PAGE")
		heading.theme_type_variation = UiTheme.MICRO
		_also.add_child(heading)
		for line in also:
			PanelKit.plain_line(_also, line, PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_record.append(line)
	_also.visible = not also.is_empty()
	_date.text = DateText.month_year(int(state.month), int(state.year))
	_clock = clock
	_left = LIFE_SECONDS
	show()
	Motion.arrive(self)
	return true


## Put the card away, its headlines kept as one note in the inbox. A no-op when
## it is not up.
func dismiss() -> void:
	if not visible:
		return
	hide()
	if inbox != null and not _record.is_empty():
		inbox.push(tr("Front pages"), "\n".join(_record))
	_record = PackedStringArray()


## Put the card away with no note: a loaded game's furniture starts empty.
func clear() -> void:
	hide()
	_record = PackedStringArray()
	_held = {}


## The count's plate was dismissed: the held card, if any, now shows. A defeat's
## dismissal leaves for the menu, and the card goes with the scene.
func _release() -> void:
	var held := _held
	_held = {}
	if not held.is_empty():
		show_entry(held["entry"], held["state"], held["loader"], held["clock"])


func _process(delta: float) -> void:
	if visible:
		advance(delta)


## One frame of the card's life: it counts only while the clock runs and the
## pointer is off it. Public so a test can age it without waiting.
func advance(delta: float) -> void:
	if _clock != null and _clock.paused:
		return
	if get_global_rect().has_point(get_global_mouse_position()):
		return
	_left -= delta
	if _left <= 0.0:
		dismiss()


func _paper(masthead: String, tone: String, words: String) -> void:
	var paper := VBoxContainer.new()
	paper.name = "Paper%d" % _papers.get_child_count()  # i18n: ok a node name, found by tests
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.add_theme_constant_override("separation", 2)
	_papers.add_child(paper)
	var name_label := Label.new()
	name_label.text = masthead.to_upper()
	name_label.theme_type_variation = UiTheme.MICRO
	paper.add_child(name_label)
	if TONE_WORDS.has(tone):
		PanelKit.plain_line(paper, tr(TONE_WORDS[tone]))
	var headline := Label.new()
	headline.text = words
	# LEAD twice, a deliberate exception to "one LEAD per panel" (parent, #179): a front page is not a panel, and its headlines are its content.
	headline.theme_type_variation = UiTheme.LEAD
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper.add_child(headline)
	_record.append(tr("%s: %s") % [masthead, words])


## {{president}}, {{party}} and {{nation}}, the three a headline may name. One
## with no value (no incumbent party, a vacant seat) is left out, so a headline
## naming it stays unfilled and is dropped rather than printed with a hole.
static func _vars(ns, loader) -> Dictionary:
	var party := ""
	for row in loader.parties.get(String(ns.id), []):
		if String(row.id) == String(ns.incumbent_party_id):
			party = String(row.party_name)
	var out := {
		"president": loader.person_name(President.leader_id(ns)),
		"party": party,
		"nation": loader.nation_name(String(ns.id)),
	}
	for key in out.keys():
		if String(out[key]).is_empty():
			out.erase(key)
	return out


## The Dictionaries of a list from the entry; anything else in it is skipped, as a
## shape this card does not read.
static func _dicts(list) -> Array:
	var out := []
	if list is Array:
		for item in list:
			if item is Dictionary:
				out.append(item)
	return out


static func _outlets(loader, nation_id: String) -> Dictionary:
	var out := {}
	for outlet in loader.outlets.get(nation_id, []):
		out[String(outlet.id)] = outlet
	return out


static func _masthead(outlet) -> String:
	return Strings.row("outlets", String(outlet.id), "name", String(outlet.outlet_name))
