extends SceneTree

## V4.4 T11. The event art library's load-bearing properties, each named by
## the doc that owns it (docs/event-art-plan.md §gate):
##
##   - THE GENERATOR AND THE DISPLAY AGREE. tools/event_art_generate.py owns
##     the prompts, src/ui/event_art.gd owns the display read, and
##     tools/event_art.gd owns the name check at post-pass time -- three
##     lists of one vocabulary is the hand-written-list failure this repo
##     keeps re-finding, so the generator's own --dry-run output is parsed
##     here and pinned set-equal to what the helper can name (python is
##     already a gate dependency).
##   - EVERY NAMEABLE PLATE EXISTS AND BYTES-LOADS -- ALL OR NOTHING. Until
##     any art ships, nothing is demanded (the portraits' Phase-A discipline:
##     missing art is silent, every surface draws without it). Once ANY plate
##     exists, a missing sibling is refused: a partial library is the one
##     incompleteness the lenient fallback does not extend to, because it
##     would degrade a whole category-band silently. And every file must
##     decode through the BYTES path -- load() lives in .godot/ and is absent
##     exactly on the fresh clone the suite stands in for.
##   - NO ORPHAN ART. A webp in assets/event_art/ that parses to no category
##     and band the vocabulary holds, or a plate with no committed
##     importer="keep" .import beside it, is the stale-art and fresh-clone
##     failures in one file each.
##   - ONE READER. No file under src/ui/ other than the helper names the
##     plate directory -- a panel that builds its own plate path is the
##     hand-written-list failure aimed at assets, and it would drift from the
##     assignment rule the helper owns.
##   - THE ASSIGNMENT IS STABLE. The variant pick is a pure function of
##     (event id, category) -- the same event must keep its art between the
##     arrival card and the desk, and across sessions; String.hash() would
##     not guarantee it, so the djb2 is pinned by running it twice.

const EventArt = preload("res://src/ui/event_art.gd")
const EventsK = preload("res://src/sim/events_constants.gd")

const ART_DIR := "res://assets/event_art"
const UI_DIR := "res://src/ui"

var _failures: Array[String] = []


func _init() -> void:
	_check_generator_and_display_agree()
	_check_plates_on_disk()
	_check_no_orphans()
	_check_one_reader()
	_check_plates_reach_a_surface()
	_check_assignment_is_stable()

	if _failures.is_empty():
		print("test_event_art: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## What the helper can name: the whole category x band x variant grid.
func _nameable_plates() -> Array[String]:
	var plates: Array[String] = []
	for category in EventsK.CATEGORIES:
		for band in EventArt.BANDS:
			for n in EventArt.VARIANTS:
				plates.append("%s_%s_%d" % [category, band, n])
	return plates


## The generator's --dry-run output is the prompt registry, printed and
## parsed rather than re-listed here -- the two-sources rule with the pin on
## the side that would otherwise drift silently.
func _check_generator_and_display_agree() -> void:
	var out: Array = []
	# SUITE_PYTHON: tools/run_tests.sh exports the interpreter it found (python or python3).
	var code := OS.execute(OS.get_environment("SUITE_PYTHON") if OS.has_environment("SUITE_PYTHON") else "python",
		[ProjectSettings.globalize_path("res://tools/event_art_generate.py"), "--dry-run"], out)
	if code != 0:
		_fail("the plate generator --dry-run failed (exit %d): %s" % [code, out])
		return
	var generated := {}
	# Windows' OS.execute hands the whole stream back as ONE element, so the
	# lines are split here rather than read off the array -- reading the array
	# directly matched one plate and called the lists unequal (this test's own
	# first run, caught by its own pin).
	var stream := "\n".join(out)
	for line in stream.split("\n"):
		var text := String(line).strip_edges()
		if not text.contains(" (seed "):
			continue
		var plate := text.split(" (seed ")[0]
		if not _is_wellformed_plate(plate):
			_fail("generator printed '%s', which is not a <category>_<band>_<n> plate" % plate)
			continue
		generated[plate] = true
	var nameable := _nameable_plates()
	if generated.size() != nameable.size():
		_fail("generator offers %d plates, the display names %d -- the two lists disagree" % [generated.size(), nameable.size()])
	for plate in nameable:
		if not generated.has(plate):
			_fail("the display names plate '%s' the generator never offers" % plate)
	for plate in generated:
		if not nameable.has(plate):
			_fail("generator offers plate '%s' the display can never name" % plate)


func _is_wellformed_plate(plate: String) -> bool:
	var parts := plate.split("_")
	if parts.size() != 3:
		return false
	if not EventsK.CATEGORIES.has(parts[0]) or not EventArt.BANDS.has(parts[1]):
		return false
	return parts[2].is_valid_int() and int(parts[2]) < EventArt.VARIANTS


## All-or-nothing: vacuous while no art ships, total once any does.
func _check_plates_on_disk() -> void:
	if not DirAccess.dir_exists_absolute(ART_DIR):
		return
	var present := 0
	for f in DirAccess.get_files_at(ART_DIR):
		if f.ends_with(".webp"):
			present += 1
	if present == 0:
		return  # Phase A: the post-pass has not run or has not landed -- nothing to demand
	for plate in _nameable_plates():
		var path := ART_DIR.path_join(plate + ".webp")
		if not FileAccess.file_exists(path):
			_fail("plate '%s' missing while %d sibling(s) ship -- a partial library degrades a category-band silently" % [plate, present])
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			_fail("plate '%s' is unreadable" % plate)
			continue
		var img := Image.new()
		if img.load_webp_from_buffer(bytes) != OK:
			_fail("plate '%s' did not decode through the bytes path" % plate)
			continue
		if img.get_width() != 432 or img.get_height() != 243:
			_fail("plate '%s' is %dx%d, expected 432x243 (16:9)" % [plate, img.get_width(), img.get_height()])


func _check_no_orphans() -> void:
	if not DirAccess.dir_exists_absolute(ART_DIR):
		return
	for f in DirAccess.get_files_at(ART_DIR):
		if f.ends_with(".webp"):
			if not _is_wellformed_plate(f.get_basename()):
				_fail("'%s' parses to no plate the vocabulary holds -- orphan art" % f)
				continue
			var import_path := ART_DIR.path_join(f + ".import")
			if not FileAccess.file_exists(import_path):
				_fail("plate '%s' has no .import beside it -- a fresh clone cannot resolve it" % f)
				continue
			var content := FileAccess.get_file_as_string(import_path)
			if not content.contains("importer=\"keep\""):
				_fail("plate '%s' .import does not carry importer=\"keep\" -- the editor would import-pass files nothing load()s" % f)


## One reader: the helper owns the directory name, so no other src/ui file
## names it. The scan reads files, not symbols -- a string built by indirection
## still lands in a file this can see.
func _check_one_reader() -> void:
	for f in DirAccess.get_files_at(UI_DIR):
		if not f.ends_with(".gd") or f == "event_art.gd":
			continue
		var content := FileAccess.get_file_as_string(UI_DIR.path_join(f))
		if content.contains("assets/event_art"):
			_fail("%s names the plate directory itself -- plates go through src/ui/event_art.gd, or the assignment rule has a second owner" % f)


## The plate has to REACH a surface. Missing art is silent by design, so deleting
## the call that draws it leaves every other check here green and the cards plain
## -- the silent-UI-failure class AGENTS.md asks a test for. Pinned at source:
## both surfaces that show a plate call the helper, and the card stack still turns
## a texture it is handed into a drawn TextureRect. And tools/event_art.gd's own
## table, the post-pass's name check, is held equal to the vocabulary it mirrors
## (its header used to claim a pin this file did not carry).
func _check_plates_reach_a_surface() -> void:
	for path in ["res://src/ui/events_panel.gd", "res://src/ui/main.gd"]:
		if not FileAccess.get_file_as_string(path).contains("EventArt.plate_texture("):
			_fail("%s no longer asks EventArt for a plate -- the desk or the arrival card draws none" % path)
	var stack := FileAccess.get_file_as_string("res://src/ui/inbox.gd")
	if not stack.contains("art: Texture2D") or not stack.contains("TextureRect"):
		_fail("inbox.gd push() no longer turns its art argument into a TextureRect")

	var tool := FileAccess.get_file_as_string("res://tools/event_art.gd")
	var start := tool.find("const CATEGORIES := [")
	if start < 0:
		_fail("tools/event_art.gd no longer defines CATEGORIES as a list literal")
		return
	var body := tool.substr(start, tool.find("]", start) - start)
	var rx := RegEx.new()
	rx.compile("\"([a-z_]+)\"")
	var found: Array[String] = []
	for m in rx.search_all(body):
		found.append(m.get_string(1))
	var want: Array[String] = []
	for category in EventsK.CATEGORIES:
		want.append(String(category))
	found.sort()
	want.sort()
	if found != want:
		_fail("tools/event_art.gd CATEGORIES %s differs from events_constants %s" % [found, want])


func _check_assignment_is_stable() -> void:
	# Pure and repeatable: the same event keeps the same plate everywhere.
	for category in EventsK.CATEGORIES:
		for n in 12:
			var id := "TEST_EVENT_%d" % n
			var first := EventArt.variant_for(id, category)
			if first != EventArt.variant_for(id, category):
				_fail("variant_for('%s', %s) moved between calls -- the pick is not pure" % [id, category])
			if first < 0 or first >= EventArt.VARIANTS:
				_fail("variant_for('%s', %s) = %d, outside [0, %d)" % [id, category, first, EventArt.VARIANTS])
	# Both variants must be reachable across the vocabulary's own ids, or the
	# second render of every plate is dead weight.
	var seen := {}
	for category in EventsK.CATEGORIES:
		for id in ["procurement_scandal", "honours_scandal", "bond_market_panic", "general_strike"]:
			seen[EventArt.variant_for(id, category)] = true
	if seen.size() < EventArt.VARIANTS:
		_fail("real event ids reach only %d of %d variants -- the pool is shallower than the render" % [seen.size(), EventArt.VARIANTS])
	# Band mapping: severity 1..3 is events_constants' own reading, clamped
	# outside.
	if EventArt.band_for(1) != "minor" or EventArt.band_for(2) != "major" or EventArt.band_for(3) != "critical":
		_fail("band_for() does not read 1 minor / 2 major / 3 critical")
	if EventArt.band_for(0) != "minor" or EventArt.band_for(9) != "critical":
		_fail("band_for() does not clamp out-of-range severity")
	# A category and id that name no file read null, not an error -- the
	# lenient precedent, held at the seatbelt as at the disk.
	if EventArt.plate_texture("no_such_category", 2, "no_such_event") != null:
		_fail("an unknown category returned a texture")


func _fail(message: String) -> void:
	_failures.append(message)
