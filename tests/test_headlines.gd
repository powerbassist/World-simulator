extends SceneTree

## Headless test: godot --headless --script res://tests/test_headlines.gd
## Non-zero exit on any failure.
##
## V5.2d, the front pages' text. data/headlines/events.json holds one headline per
## event, answer and tone ({event_id: {answer_id: {friendly, neutral, hostile}}},
## docs/design/v5.2-d-spec.md section 4), for every event the game calls major or
## critical (severity 2 or 3). The coverage is a contract: an event that earns a
## front page with a missing cell would print an empty masthead line, so a new
## event of that weight, or a new answer, turns this red until its headlines exist.
## The wording rules (whole headline, ASCII, the three variables) are the writer's,
## pinned here so a later edit cannot slip a colon or an unknown variable in.

const DataLoader = preload("res://src/core/data_loader.gd")

const PATH := "res://data/headlines/events.json"
const MOMENTS_PATH := "res://data/headlines/moments.json"
## The moments the press marks besides events (docs/design/v5.2-d-spec.md section 4) and their
## outcomes, as Systems emits them in the month report's front_page entry.
const MOMENTS := {
	"election": ["executive_won", "executive_lost", "legislative_majority", "legislative_minority", "legislative_opposition"],
	"censure": ["government_fell"],
	"dissolution": ["called"],
	"article_49_3": ["carried"],
	"character": ["minister_resigned", "defected"],
}
const TONES := ["friendly", "neutral", "hostile"]
const VARIABLES := ["president", "party", "nation"]

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("%s is not a JSON object" % PATH)
		_finish()
		return
	_check_coverage(loader, parsed)
	_check_wording(parsed)
	_check_moments()
	_finish()


func _check_coverage(loader, headlines: Dictionary) -> void:
	var by_id := {}
	for event in loader.events:
		by_id[String(event.id)] = event
	for event_id in headlines.keys():
		if not by_id.has(event_id):
			_fail("headlines name event '%s', which does not exist" % event_id)
			continue
		var answers: Dictionary = headlines[event_id]
		var known := {}
		for choice in by_id[event_id].choices:
			known[String(choice["id"])] = true
		for answer_id in answers.keys():
			if not known.has(answer_id):
				_fail("%s: headlines for answer '%s', which the event does not offer" % [event_id, answer_id])
	for event in loader.events:
		if int(event.severity) < 2:
			continue
		var id := String(event.id)
		if not headlines.has(id):
			_fail("event '%s' (severity %d) has no headlines" % [id, int(event.severity)])
			continue
		for choice in event.choices:
			var answer_id := String(choice["id"])
			var tones = headlines[id].get(answer_id, null)
			if typeof(tones) != TYPE_DICTIONARY:
				_fail("%s.%s has no headlines" % [id, answer_id])
				continue
			for tone in TONES:
				if String(tones.get(tone, "")).strip_edges() == "":
					_fail("%s.%s has no %s headline" % [id, answer_id, tone])


## data/headlines/moments.json: {moment: {outcome: {tones}}}, exactly the table above,
## under the same wording rules as the events'.
func _check_moments() -> void:
	var moments = JSON.parse_string(FileAccess.get_file_as_string(MOMENTS_PATH))
	if typeof(moments) != TYPE_DICTIONARY:
		_fail("%s is not a JSON object" % MOMENTS_PATH)
		return
	for moment in MOMENTS.keys():
		if not moments.has(moment):
			_fail("moments.json has no moment '%s'" % moment)
			continue
		for outcome in MOMENTS[moment]:
			var tones = moments[moment].get(outcome, null)
			if typeof(tones) != TYPE_DICTIONARY:
				_fail("%s.%s has no headlines" % [moment, outcome])
				continue
			for tone in TONES:
				if String(tones.get(tone, "")).strip_edges() == "":
					_fail("%s.%s has no %s headline" % [moment, outcome, tone])
	for moment in moments.keys():
		if not MOMENTS.has(moment):
			_fail("moments.json names the unknown moment '%s'" % moment)
		else:
			for outcome in moments[moment].keys():
				if not MOMENTS[moment].has(outcome):
					_fail("moments.json names the unknown outcome '%s.%s'" % [moment, outcome])
	_check_wording(moments)


func _check_wording(headlines: Dictionary) -> void:
	var seen := {}
	for event_id in headlines.keys():
		for answer_id in headlines[event_id].keys():
			for tone in headlines[event_id][answer_id].keys():
				var cell := "%s.%s.%s" % [event_id, answer_id, tone]
				if not TONES.has(tone):
					_fail("%s: '%s' is not a tone" % [cell, tone])
					continue
				var text := String(headlines[event_id][answer_id][tone])
				for ch in text:
					if ch.unicode_at(0) > 126:
						_fail("%s carries a non-ASCII character" % cell)
						break
				for banned in [":", ";", "[", "]", "|", "~", "?"]:
					if text.contains(banned):
						_fail("%s carries '%s'" % [cell, banned])
				var rx := RegEx.new()
				rx.compile("\\{\\{(\\w+)\\}\\}")
				for m in rx.search_all(text):
					if not VARIABLES.has(m.get_string(1)):
						_fail("%s uses the unknown variable {{%s}}" % [cell, m.get_string(1)])
				var words := rx.sub(text, "X", true).split(" ", false)
				if words.size() < 4 or words.size() > 18:
					_fail("%s is %d words, not a headline" % [cell, words.size()])
				if seen.has(text):
					_fail("%s repeats the headline of %s" % [cell, seen[text]])
				seen[text] = cell


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_headlines: all checks passed")
		quit(0)
	else:
		for message in _failures:
			print("FAIL: %s" % message)
		quit(1)
