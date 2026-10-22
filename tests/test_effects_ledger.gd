extends SceneTree

## Headless test: godot --headless --script res://tests/test_effects_ledger.gd
## Non-zero exit on any failure.
##
## V5.1-d1b3. QA on #69: the Feb 1 close pushed FIVE consequence cards, each
## claiming the same month's movement -- the winter bill credited with the
## budget's growth jump, Programme set with the budget's deficit, a referendum's
## call and call-off as two cards with one title. The parent's call: a month's
## decisions cannot be told apart in a month's numbers, so the close says so --
##   - ONE card per close: "This month you decided: A, B", then what moved since
##     the earliest of them, worded as the month's movement after them;
##   - the same labels once (a call and its call-off are one name);
##   - ONE recent_effects entry, so the Overview's list groups the same way;
##   - a flat month says "nothing moved", not lines of 0.0;
## and the Deficit sign (QA): deficit_pct_gdp is spending - revenue, so rising is
## worse -- the Overview coloured a growing deficit good, and worst() never chose it.

const EffectsLedger = preload("res://src/ui/effects_ledger.gd")
const RecentEffects = preload("res://src/sim/recent_effects.gd")
const RecentEffectsK = preload("res://src/sim/recent_effects_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const Inbox = preload("res://src/ui/inbox.gd")

var _failures: Array[String] = []
var _frame := 0
var _inbox


func _init() -> void:
	_inbox = Inbox.new()
	root.add_child(_inbox)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_check_one_card_per_close()
	_check_a_flat_month()
	_check_defaults_are_not_decisions()
	_check_the_deficit_sign()
	_check_the_bound()
	_check_one_writer()
	_finish()
	return true


class FakeState:
	var recent_effects: Array[Dictionary] = []


func _snap(approval: float, deficit: float, growth: float) -> Dictionary:
	return {"overall_approval_pct": approval, "deficit_pct_gdp": deficit, "growth_annual_pct": growth,
		"unemployment_pct": 7.0, "debt_to_gdp_pct": 110.0, "year": 2026, "month": 1}


func _check_one_card_per_close() -> void:
	var state := FakeState.new()
	var pending := [
		{"label": "Budget change", "before": _snap(50.0, 5.0, 1.0)},
		{"label": "Single-Term Presidency Act", "before": _snap(50.0, 5.0, 1.0)},
		{"label": "Single-Term Presidency Act", "before": _snap(49.0, 6.0, 1.2)},
		{"label": "The winter bill: Freeze the household tariff", "before": _snap(48.0, 7.0, 1.4)},
	]
	var cards_before: int = _inbox.card_count()
	EffectsLedger.record(state, pending, _snap(41.3, 10.1, 6.3), 2026, 2, _inbox)
	if state.recent_effects.size() != 1:
		_fail("one close recorded %d entries, not one" % state.recent_effects.size())
		return
	if _inbox.card_count() != cards_before + 1:
		_fail("one close pushed %d cards, not one" % (_inbox.card_count() - cards_before))
	var label := String(state.recent_effects[0]["label"])
	if label.count("Single-Term Presidency Act") != 1:
		_fail("a call and its call-off are named twice: %s" % label)
	for name in ["Budget change", "The winter bill"]:
		if not label.contains(name):
			_fail("the close's entry does not name '%s': %s" % [name, label])
	# Measured from the EARLIEST baseline: approval 50 -> 41.3, not 48 -> 41.3.
	for m in state.recent_effects[0]["movements"]:
		if String(m["key"]) == "deficit_pct_gdp" and not is_equal_approx(float(m["change"]), 5.1):
			_fail("the movement is not from the earliest decision's baseline: deficit %+.2f" % float(m["change"]))
	var card := _last_card_text()
	if not card.to_lower().contains("this month you decided"):
		_fail("the close's card does not say what was decided this month: %s" % card)
	if not card.to_lower().contains("since"):
		_fail("the card does not word the figures as the month's movement since the decisions: %s" % card)


func _check_a_flat_month() -> void:
	var state := FakeState.new()
	var pending := [{"label": "Cabinet reassigned", "before": _snap(50.0, 5.0, 1.0)}]
	EffectsLedger.record(state, pending, _snap(50.01, 5.02, 1.0), 2026, 3, _inbox)
	var card := _last_card_text()
	if not card.contains("nothing moved") or card.contains("0.0"):
		_fail("a flat month does not say 'nothing moved': %s" % card)


## QA on #73: a month whose only entry is a default ("Decided for you") is not a
## month the player decided anything; a mixed month names the two apart.
func _check_defaults_are_not_decisions() -> void:
	var state := FakeState.new()
	EffectsLedger.record(state, [{"label": "The harvest that failed over there", "before": _snap(50.0, 5.0, 1.0), "defaulted": true}],
		_snap(52.0, 5.0, 1.0), 2026, 4, _inbox)
	var card := _last_card_text().to_lower()
	if card.contains("you decided") or not card.contains("decided for you"):
		_fail("a month of defaults reads as the player's decisions: %s" % card)
	EffectsLedger.record(state, [
		{"label": "Budget change", "before": _snap(50.0, 5.0, 1.0)},
		{"label": "The harvest that failed over there", "before": _snap(50.0, 5.0, 1.0), "defaulted": true},
	], _snap(52.0, 5.0, 1.0), 2026, 5, _inbox)
	card = _last_card_text().to_lower()
	var title_line: String = card.split(char(10))[0]
	if title_line.contains("harvest"):
		_fail("a default is listed with what the player decided: %s" % title_line)
	if not card.contains("decided for you"):
		_fail("a mixed month does not name its default apart: %s" % card)


func _check_the_deficit_sign() -> void:
	var rows := Trends.movements_between(_snap(50.0, 5.0, 1.0), _snap(50.0, 7.0, 1.0))
	for row in rows:
		if String(row["key"]) == "deficit_pct_gdp" and float(row["severity"]) <= 0.0:
			_fail("a deficit growing from 5 to 7 points of GDP reads as good news (severity %.2f)" % float(row["severity"]))
	var worst := Trends.worst_of(rows)
	if String(worst.get("key", "")) != "deficit_pct_gdp":
		_fail("the worst of a month whose only move is a growing deficit is '%s'" % worst.get("key", ""))


## The register keeps the newest RecentEffectsK.KEPT, newest first.
func _check_the_bound() -> void:
	var state := FakeState.new()
	for i in RecentEffectsK.KEPT + 2:
		RecentEffects.record(state, {"label": "close %d" % i, "year": 2026, "month": i + 1, "movements": []})
	if state.recent_effects.size() != RecentEffectsK.KEPT:
		_fail("the register kept %d closes, not %d" % [state.recent_effects.size(), RecentEffectsK.KEPT])
	elif String(state.recent_effects[0]["label"]) != "close %d" % (RecentEffectsK.KEPT + 1):
		_fail("the newest close is not first: %s" % state.recent_effects[0]["label"])


## AGENTS.md rule 2: the UI never writes GameState. recent_effects has ONE writer,
## src/sim/recent_effects.gd's record(); game_state.gd's from_dict() rebuilds it on
## load. What the scan catches, in any other .gd under src/ (src/ui above all): a
## mutating call on the name (push_front, append, insert, remove_at, erase, clear,
## resize, the pops, the sorts, reverse, fill, shuffle, assign), an indexed store
## (`recent_effects[i] = ...`), and an assignment or compound assignment to it.
## What it does not: a write through an alias (`var r = state.recent_effects` then
## `r.clear()`), which a writer would have to go out of its way to hide. Scanned
## over code with string literals and comments removed, so neither can trip it.
const WRITERS_ALLOWED := ["res://src/sim/recent_effects.gd", "res://src/core/game_state.gd"]
const WRITE := "recent_effects\\s*(\\.\\s*(push_front|push_back|append|append_array|insert|remove_at|erase|clear|resize|pop_front|pop_back|pop_at|sort|sort_custom|reverse|fill|shuffle|assign)\\s*\\(|\\[[^\\]]*\\]\\s*[-+*/]?=(?!=)|\\s*[-+*/]?=(?!=))"

func _check_one_writer() -> void:
	var write := RegEx.create_from_string(WRITE)
	var strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
	var files: Array = []
	_gd_files("res://src", files)
	if files.size() < 100:
		_fail("the writer scan found %d files under src/ -- it is not reading the tree" % files.size())
	var seen_writer := false
	for path in files:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			# Strings out first, so a `#` inside one (a colour, a hint) is not read
			# as the start of a comment and does not hide the code after it.
			var bare := strings.sub(line, "\"\"", true)
			var cut := bare.find("#")
			code += (bare if cut < 0 else bare.substr(0, cut)) + "\n"
		var found := write.search(code)
		if found == null:
			continue
		if WRITERS_ALLOWED.has(path):
			seen_writer = seen_writer or path == WRITERS_ALLOWED[0]
			continue
		_fail("%s writes recent_effects (`%s`) -- RecentEffects.record() is the one writer" % [path, found.get_string().strip_edges()])
	if not seen_writer:
		_fail("src/sim/recent_effects.gd no longer writes the register -- the scan lost its positive control")


func _gd_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path + "/" + name)
	for sub in dir.get_directories():
		_gd_files(dir_path + "/" + sub, out)


func _last_card_text() -> String:
	var newest := ""
	for id in _inbox._cards:
		newest = id
	var out := ""
	for node in _all(_inbox._cards[newest]):
		if node is Label:
			out += node.text + "\n"
		elif node is RichTextLabel:
			out += node.get_parsed_text() + "\n"
	return out


func _all(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_effects_ledger: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
