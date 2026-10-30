extends SceneTree

## Headless test: godot --headless --script res://tests/test_speaker_lines.gd
## Non-zero exit on any failure.
##
## V5.2d, the speakers' lines. A speaker_line is what the person says in their own
## voice (a stake, a demand, a warning); the summary already carries the fact and the
## deadline. The first draft of the lines echoed their summaries, so the card read the
## same sentence twice (the parent's smoke frame: 26 of 112 lines above a difflib ratio
## of 0.6, two identical). This pins the fix: no line may reuse more than half of its
## own word pairs from its event's summary. The measure is the share of the line's
## consecutive word pairs that also occur in the summary, because it is exact, needs no
## fuzzy matcher, and catches a lifted phrase that single-word overlap (every sentence
## shares "the" and "and") would hide. The same lines scored at most 0.38 on it when
## it was fixed.

const DataLoader = preload("res://src/core/data_loader.gd")

const BAR := 0.5

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
	var seen := 0
	for event in loader.events:
		if String(event.speaker_line).strip_edges() == "":
			continue
		seen += 1
		var share := echo_share(String(event.speaker_line), String(event.summary))
		if share >= BAR:
			_fail("%s: the speaker's line reuses %.2f of its word pairs from the summary (bar %.2f)" % [event.id, share, BAR])
	if seen == 0:
		_fail("no event carries a speaker_line, this check is looking at nothing")
	_check_the_measure()
	_finish()


## The share of `line`'s consecutive word pairs that also occur in `summary`.
static func echo_share(line: String, summary: String) -> float:
	var pairs := _pairs(line)
	if pairs.is_empty():
		return 0.0
	var theirs := _pairs(summary)
	var shared := 0
	for pair in pairs.keys():
		if theirs.has(pair):
			shared += 1
	return float(shared) / float(pairs.size())


static func _pairs(text: String) -> Dictionary:
	var rx := RegEx.new()
	rx.compile("[a-z']+")
	var words: Array[String] = []
	for m in rx.search_all(text.to_lower()):
		words.append(m.get_string())
	var out := {}
	for i in range(words.size() - 1):
		out[words[i] + " " + words[i + 1]] = true
	return out


## The measure itself, on fixed sentences: an echo scores high, an own-voice line low.
func _check_the_measure() -> void:
	var summary := "The treasury does not have the week's cash, and the payroll file clears on Wednesday."
	if echo_share(summary, summary) < 0.99:
		_fail("a line identical to its summary does not score as an echo")
	if echo_share("I will do whatever you decide, but I need the order today.", summary) >= BAR:
		_fail("an own-voice line scores as an echo")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_speaker_lines: all checks passed")
		quit(0)
	else:
		for message in _failures:
			print("FAIL: %s" % message)
		quit(1)
