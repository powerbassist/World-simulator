extends SceneTree

## Headless test: godot --headless --script res://tests/test_feelings.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R11 + Q2 (docs/design/v5.2-bplus-spec.md, "relations as feelings"): the
## author's "grudge +0.17" is a feeling, and refusing "cost me nothing, apparently".
##   - CUTS: each register's word at and around every declared cut, on the
##     declared side, exact sums of authored steps included (bands-v5.2.md, the B6
##     amendment: three declines from 0 read -0.30, wary, not cold);
##   - ONE DECLINE from rapport 0 and grudge 0 changes a shown word, and the words
##     the request card promises are the words shown after the answer;
##   - A DATED LINE on the person after a refusal and after a delegation;
##   - A BROKEN DELEGATION changes a word (grudge +0.215, rapport -0.2);
##   - THE LINT: no line of src/ui prints a grudge, rapport or loyalty figure
##     outside a tooltip.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PersonCard = preload("res://src/ui/person_card.gd")

const PLAYER := "FRA"
const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}
const ROOT := "res://src/ui"
## A figure printed on a line that names one of the three registers.
const FIGURE := r"Num\.fs?\("
const REGISTER := r"(?i)grudge|rapport|loyalty"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_check_cuts()
	_check_broken_delegation()
	_check_lint()
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
	else:
		_check_decline()
		_check_delegation_line()
	_finish()


## [register, value, office holder, the word]. "" is the band that shows no word.
func _check_cuts() -> void:
	var three_declines := -0.1 - 0.1 - 0.1
	var cases := [
		["grudge", 0.0, false, ""], ["grudge", 0.049, false, ""], ["grudge", 0.05, false, "annoyed"],
		["grudge", 0.18, false, "annoyed"], ["grudge", 0.20, false, "resentful"], ["grudge", 0.36, false, "resentful"],
		["grudge", 0.45 - 1e-12, false, "hostile, may leak"], ["grudge", 0.45, false, "hostile, may leak"],
		["grudge", 0.5999, false, "hostile, may leak"], ["grudge", 0.60, false, "bitter, may defect"], ["grudge", 1.0, false, "bitter, may defect"],
		["rapport", -1.0, false, "cold"], ["rapport", -0.31, false, "cold"], ["rapport", three_declines, false, "wary"],
		["rapport", -0.30, false, "wary"], ["rapport", -0.06, false, "wary"], ["rapport", -0.05, false, "neutral"],
		["rapport", 0.0, false, "neutral"], ["rapport", 0.10 - 0.05, false, "neutral"], ["rapport", 0.051, false, "warm"],
		["rapport", 0.30, false, "warm"], ["rapport", 0.31, false, "close"], ["rapport", 1.0, false, "close"],
		["loyalty", -0.5, false, "disloyal"], ["loyalty", -0.5, true, "ready to resign"], ["loyalty", -0.40, false, "uncertain"],
		["loyalty", -0.11, false, "uncertain"], ["loyalty", -0.10, false, ""], ["loyalty", 0.0, false, ""],
		["loyalty", 0.10, false, ""], ["loyalty", 0.11, false, "loyal"], ["loyalty", 0.40, false, "loyal"], ["loyalty", 0.41, false, "devoted"],
	]
	for c in cases:
		var got := Feelings.word(String(c[0]), float(c[1]), bool(c[2]))
		if got != String(c[3]):
			_fail("cut: %s %s (office %s) reads '%s', not '%s'" % [c[0], c[1], c[2], got, c[3]])


## A broken delegated commitment: the deferred grudge share reaches resentful from
## 0, and the betrayal's rapport reaches wary from 0 (the spec's band row).
func _check_broken_delegation() -> void:
	var feel := {"grudge": 0.0, "rapport": 0.0, "loyalty": 0.0, "office": false}
	var landing := Feelings.landing(feel, {"grudge": 0.215, "rapport": -0.2})
	if landing.get("grudge", "") != "resentful" or landing.get("rapport", "") != "wary":
		_fail("a broken delegation from 0 lands on %s, not resentful and wary" % [landing])


## One decline from 0 / 0: the card's price names the words it lands in, at least
## one of them moves, and the same words stand after the answer.
func _check_decline() -> void:
	var game := _game_with_request()
	if game.is_empty():
		return
	var state = game["state"]
	var ns = state.player()
	var id := String(game["row"]["id"])
	var pid := String(game["row"]["person_id"])
	ns.person_grudges.erase(pid)
	ns.person_loyalty.erase(pid)
	ns.person_rapport.erase(pid)
	var before := Feelings.of(ns, pid)
	var price := Audiences.decline_price(ns, _loader, id)
	var promised := Feelings.landing(before, price)
	var card := Words.price_text(price, before)
	var moved := false
	for register in promised:
		if not card.contains(String(promised[register])):
			_fail("the card's price '%s' does not name the word %s lands in ('%s')" % [card, register, promised[register]])
		if promised[register] != Feelings.words(before).get(register, ""):
			moved = true
	if not moved:
		_fail("one decline from 0 / 0 moves no shown word: %s" % [promised])
	var r := Audiences.decline(state, ns, _loader, id)
	var after := Feelings.of(ns, pid)
	var now_words := Feelings.words(after)
	for register in promised:
		if now_words.get(register, "") != promised[register]:
			_fail("after the decline %s reads '%s', the card promised '%s'" % [register, now_words.get(register, ""), promised[register]])
	var told := Words.price_text(r.get("price", {}), after, true)
	for register in promised:
		if not told.contains(String(promised[register])):
			_fail("the words told after the answer '%s' miss '%s'" % [told, promised[register]])
	if Words.price_text(price, before).contains("0.1") or told.contains("0.1"):
		_fail("a price still prints a figure: '%s' / '%s'" % [card, told])
	var lines := PersonCard.dated_lines(_loader, ns, pid)
	if lines.size() != 1 or not lines[0].contains("refused") or not lines[0].contains(Words.when(int(state.year) * 12 + int(state.month))):
		_fail("a decline leaves no dated line on the person: %s" % [lines])


## A delegation writes the minister's promise on the person, dated.
func _check_delegation_line() -> void:
	var game := _game_with_request()
	if game.is_empty():
		return
	var state = game["state"]
	var ns = state.player()
	var pid := String(game["row"]["person_id"])
	var r := Audiences.delegate(state, ns, _loader, String(game["row"]["id"]))
	if not bool(r.get("ok", false)):
		_fail("premise: the delegation was refused: %s" % r.get("error", ""))
		return
	var lines := PersonCard.dated_lines(_loader, ns, pid)
	if lines.size() != 1 or not lines[0].contains("minister"):
		_fail("a delegation leaves no dated line on the person: %s" % [lines])


## Every line of src/ui that prints a figure (Num.f / Num.fs) and names one of the
## three registers fails, unless the figure goes to a tooltip.
func _check_lint() -> void:
	var figure := RegEx.create_from_string(FIGURE)
	var register := RegEx.create_from_string(REGISTER)
	if not _flags(figure, register, "row(_body, tr(\"Grudge\"), Num.f(grudge, 2))") or _flags(figure, register, "label.tooltip_text = Num.fs(rapport, 2)") \
			or _flags(figure, register, "row(_body, tr(\"Standing\"), Num.f(standing, 2))"):
		_fail("the lint's own shapes no longer hold")
	var dir := DirAccess.open(ROOT)
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string("%s/%s" % [ROOT, file]).split("\n")
		for i in lines.size():
			if _flags(figure, register, lines[i]):
				_fail("%s:%d prints a feeling as a figure: %s" % [file, i + 1, lines[i].strip_edges()])


func _flags(figure: RegEx, register: RegEx, line: String) -> bool:
	return not line.strip_edges().begins_with("#") and not line.contains("tooltip") \
		and figure.search(line) != null and register.search(line) != null


## A France game ticked (Audiences alone) until its first request arrives.
func _game_with_request() -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	for m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		var lane: Array[Dictionary] = Audiences.pending(state.player())
		if not lane.is_empty():
			return {"state": state, "row": lane[0]}
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
	_fail("no request arrived in 24 months")
	return {}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_feelings: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
