extends PanelContainer

## The polling screen. Headline approval, a row per voter bloc, and what the
## electorate currently cares about.
##
## Reads simulation state and never writes it — there is no command to send back,
## because you cannot act on a poll, only on the budget. See engine-decision.md
## Rule 2.
##
## Every figure on this panel is passed through PollNoise first. The live state
## holds the true numbers; the player never sees them. The noise is deterministic
## in the poll id, so the figures hold still between repaints and move once a
## month, which is how a published poll behaves.
##
## Built in code rather than as a .tscn for the same reason the budget screen is:
## it is a generated grid of identical rows.

const Opinion = preload("res://src/sim/opinion.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Trends = preload("res://src/ui/trends.gd")

const TOP_ISSUE_COUNT := 4
const HEADLINE_KEY := "overall"

signal closed

var _state
var _loader = null
## B3: the chamber this panel's clock counts -- always the ASSEMBLY schedule
## (ns.next_election_*), named off the loader's nation data when one is wired in.
var _chamber := "assembly"
var _title: Label
var _headline: Label
var _election_countdown: Label
## V2.1b. Both tables were RETAINED -- built once in _ready() and updated cell by
## cell through two dictionaries of Label references -- and both are now rebuilt
## from PanelKit.ledger() on each refresh, which is what every other panel in this
## interface already did. The bookkeeping that went with them went too. The reason
## is V1.6f rather than tidiness: the four columns each carried their own
## custom_minimum_size.x, which is two value columns measured apart in the exact
## shape that ran the budget panel off the window edge.
var _body: VBoxContainer
var _dirty := true
var _close_button: Button

## What the previous poll said, so the change column compares like with like:
## two noised figures, not a noised one against a true one.
var _shown_poll_id := -1
var _shown := {}
var _previous := {}


func _ready() -> void:
	# Placement is the owner's job — see the note in budget_panel.gd.
	custom_minimum_size = Vector2(560, 460)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	_headline = Label.new()
	root.add_child(_headline)

	_election_countdown = Label.new()
	root.add_child(_election_countdown)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_body)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	root.add_child(_build_footer())


func _build_footer() -> Control:
	var row := HBoxContainer.new()

	var caveat := Label.new()
	caveat.text = tr("Polls carry a margin of error of about %.0f points.") % PollNoise.NOISE_MAX_PCT
	caveat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caveat)

	var close := Button.new()
	close.text = tr("Close (P)")
	close.pressed.connect(func(): hide(); closed.emit())
	row.add_child(close)
	_close_button = close

	return row


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


## `loader` is optional so every registered panel takes the same two arguments,
## which is what lets main.gd's load path re-setup() them off WindowManager.panels()
## instead of a hand-written list. B3 (playtest 2026-09-16): the loader names the
## chamber when given, so this countdown and the top bar's executive one stop
## reading as a contradiction -- but main.gd's first setup passes only state, so
## "assembly" is the fallback wording.
func setup(state, loader = null) -> void:
	_state = state
	_loader = loader
	_chamber = "assembly"
	if loader != null and loader.nations.has(state.player().id):
		_chamber = String(loader.nations[state.player().id].chamber_name)
	_title.text = tr("POLLING — %s") % _state.player().id
	_dirty = true


## Coalesce to at most one refresh per frame, the same shape the budget panel
## uses. Cheaper here — there is no projection to run — but the owner marks this
## dirty on every simulated month either way.
func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return

	var id := PollNoise.poll_id(_state.year, _state.month)
	var fresh_poll := id != _shown_poll_id

	var current := {}
	current[HEADLINE_KEY] = PollNoise.displayed(id, HEADLINE_KEY, ns.overall_approval_pct)
	for bloc in K.BLOC_KEYS:
		current[bloc] = PollNoise.displayed(id, bloc, float(ns.bloc_approval.get(bloc, 0.0)))

	if fresh_poll:
		_previous = _shown
		_shown = current
		_shown_poll_id = id

	_headline.text = tr("Approval  %.0f%%") % current[HEADLINE_KEY]
	_election_countdown.text = tr("Next %s election: %s") % [_chamber, _months_until_text(ns)]

	for child in _body.get_children():
		child.queue_free()

	var bloc_rows: Array = [["", "share", "approval", "change"]]
	for bloc in K.BLOC_KEYS:
		bloc_rows.append([
			K.BLOC_LABEL[bloc],
			"%.0f%%" % (float(K.BLOC_SIZE[bloc]) * 100.0),
			"%.0f%%" % current[bloc],
			_change_text(bloc, current[bloc]),
		])
	PanelKit.ledger(PanelKit.section(_body, tr("Approval by bloc")), bloc_rows)

	var issue_rows: Array = []
	for entry in Opinion.top_issues(ns, TOP_ISSUE_COUNT):
		issue_rows.append([K.ISSUE_LABEL[entry[0]], "%.0f%%" % (float(entry[1]) * 100.0)])
	PanelKit.ledger(PanelKit.section(_body, tr("What the country is thinking about")), issue_rows)


func _change_text(key: String, value: float) -> String:
	if not _previous.has(key):
		return "—"
	return "%+.0f" % (value - float(_previous[key]))


## B3: one shared query -- Trends.months_text carries the plural and the clamp,
## so this panel and the top bar cannot print two grammars for one kind of
## countdown. This still counts the ASSEMBLY clock (ns.next_election_*) directly;
## vote_date() would switch to the executive schedule where one exists.
func _months_until_text(ns) -> String:
	var months: int = (int(ns.next_election_year) - _state.year) * 12 + (int(ns.next_election_month) - _state.month)
	return Trends.months_text(months)
