extends SceneTree

## Headless test: godot --headless --script res://tests/test_pregate_records.gd
## Non-zero exit on any failure.
##
## V5.2 pre-gate B, QA's Interface RECORDs (.superpowers/sdd/v5.2-pregate-b-report.md),
## each on the surface that showed it:
##   1. the Budget, Polling and Legislature titles name the nation, not its id;
##   2. Polling's change column compares with the previous published poll on the
##      FIRST view (the history), not only with a poll this panel happened to show;
##   4. a hold line comes down when what it named is answered on a paused clock;
##   5. the person card shows rapport, the register a decline or a lapse writes;
##   7. a promise already given shows ITS date on the greyed Promise row;
##   8. a refused answer on a card does not look like a live one;
##   9. a call with nothing to ask opens without an empty line.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const AudienceVerbs = preload("res://src/ui/audience_verbs.gd")
const PhoneDialog = preload("res://src/ui/phone_dialog.gd")
const Words = preload("res://src/ui/lever_words.gd")
const K = preload("res://src/sim/opinion_constants.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _card: PersonCard
var _verbs: AudienceVerbs
var _phone: PhoneDialog
var _given := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_check_titles()
			_check_poll_change()
			_check_hold_line_clears()
			_stage_card()
			_stage_promise_row()
			_phone = PhoneDialog.new()
			_main.add_child(_phone)
		4:
			_phone.open({"name": "Diane Villedary", "why_not": "", "levers": [], "topics": [{"topic": "opinion", "offered": true}]})
		6:
			_check_card()
			_check_promise_row()
			_check_refused_answer_looks_refused()
			if _phone._line.visible or _phone._result.visible:
				_fail("RECORD 9: a call with nothing to ask opens on an empty line")
			_phone.show_result("They agree.")
			if _phone._why.visible:
				_fail("RECORD 9: a call's result leaves the cleared reason line as an empty row")
			_finish()
			return true
	return false


func _check_titles() -> void:
	var id := String(_main._state.player().id)
	var name: String = _main._loader.nation_name(id)
	if name == id:
		_fail("premise: the loader has no name for %s" % id)
	for panel in [_main._budget_panel, _main._polling_panel, _main._law_panel]:
		var title: String = panel._title.text
		if not title.ends_with("— " + name):
			_fail("RECORD 1: a title reads '%s', not the nation's name %s" % [title, name])


## A previous month in the history with each bloc ten points away: the column
## must read the move between the two published polls on the first refresh.
func _check_poll_change() -> void:
	var state = _main._state
	var ns = state.player()
	var id := PollNoise.poll_id(state.year, state.month)
	var prev_year := floori((id - 1 - 1) / 12.0)
	var before := {}
	for bloc in K.BLOC_KEYS:
		before[bloc] = clampf(float(ns.bloc_approval.get(bloc, 0.0)) - 10.0, 0.0, 100.0)
	state.history.append({"year": prev_year, "month": id - 1 - prev_year * 12, "bloc_approval": before,
		"overall_approval_pct": float(ns.overall_approval_pct)})
	var panel = _main._polling_panel
	panel.show()
	panel._refresh()
	for bloc in K.BLOC_KEYS:
		var now := PollNoise.displayed(id, bloc, float(ns.bloc_approval.get(bloc, 0.0)))
		var then := PollNoise.displayed(id - 1, bloc, float(before[bloc]))
		var moved := roundf(now - then)
		var want := "0" if moved == 0.0 else "%+.0f" % moved
		var got := _bloc_cell(panel, String(K.BLOC_LABEL[bloc]), 3)
		if got != want:
			_fail("RECORD 2: %s's change reads '%s' on the first view; the polls moved %s" % [bloc, got, want])
	state.history.pop_back()


## A clock the player paused, a hold line left from an event: the answer's door
## re-reads why the clock holds, and nothing does now.
func _check_hold_line_clears() -> void:
	# Nothing holds: the term's programme offer (which does hold at boot) set aside.
	_main._clock.paused = true
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	_main._hud.clock_cluster.refresh(_main._clock, "Paused: The queue at the crossing needs an answer.")
	_main._hud.inbox.card_dismissed.emit("card_none")
	if _main._hud.clock_cluster.hold_reason() != "":
		_fail("RECORD 4: the hold line still reads '%s' once nothing holds" % _main._hud.clock_cluster.hold_reason())


## A person a decline cost rapport and nothing else (QA's Valsergent).
func _stage_card() -> void:
	var ns = _main._state.player()
	var people: Array = _main._loader.people.get(String(ns.id), [])
	if people.is_empty():
		_fail("premise: the played nation has no people")
		return
	var pid := String(people[0].id)
	for register in [ns.person_grudges, ns.person_loyalty, ns.person_standing]:
		register.erase(pid)
	ns.person_rapport[pid] = -0.10
	_card = PersonCard.new()
	_main.add_child(_card)
	_card.show_for(pid, _main._loader, ns, Vector2(40, 40))


func _check_card() -> void:
	if _card == null:
		return
	var text := _text(_card)
	if not text.contains("Rapport") or not text.contains("-0.10"):
		_fail("RECORD 5: the person card does not show a rapport of -0.10:\n%s" % text)


## Given for 15 months on, the row refused ("your word is given"): the window the
## picker offers from today would default to a year out.
func _stage_promise_row() -> void:
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	_given = now + 15
	_verbs = AudienceVerbs.new()
	_main.add_child(_verbs)
	_verbs.show_verbs([{"lever": "promise_date", "offered": false, "why_not": "your word is given", "odds_lo": 0.3, "odds_hi": 0.6,
		"spends": {"promise": 1.0}}], [], 1, {"now": now, "given_due": _given})


func _check_promise_row() -> void:
	var due := _verbs.find_child("Due", true, false) as OptionButton
	var said := Words.when(_given)
	if due == null or due.text != said:
		_fail("RECORD 7: the greyed promise row reads '%s', not the date given, %s" % [due.text if due != null else "", said])
	if not _text(_verbs).contains(said):
		_fail("RECORD 7: the promise row's cost line does not name %s" % said)


## The inbox draws a card's answers as SubrowButtons: a refused one must differ
## from a live one in its text colour, or only the hover tells them apart.
func _check_refused_answer_looks_refused() -> void:
	var theme := UiTheme.build()
	var live := theme.get_color("font_color", UiTheme.SUBROW_BUTTON)
	var refused := theme.get_color("font_disabled_color", UiTheme.SUBROW_BUTTON)
	if not theme.has_color("font_disabled_color", UiTheme.SUBROW_BUTTON) or live.is_equal_approx(refused):
		_fail("RECORD 8: a refused card answer is drawn in the live answer's colour")
	if not theme.has_stylebox("disabled", UiTheme.SUBROW_BUTTON):
		_fail("RECORD 8: a refused card answer falls back to the slab button's disabled fill")


func _bloc_cell(panel: Node, wanted: String, column: int) -> String:
	for grid in panel.find_children("*", "GridContainer", true, false):
		var columns: int = grid.columns
		var cells: Array = grid.get_children()
		for i in range(0, cells.size(), columns):
			if cells[i] is Label and cells[i].text == wanted and i + column < cells.size():
				return (cells[i + column] as Label).text
	return ""


func _text(node: Node) -> String:
	var out := ""
	if node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	elif node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_pregate_records: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
