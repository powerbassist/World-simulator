extends SceneTree

## V2.3. The portrait pipeline's load-bearing properties, each named by the
## doc that owns it:
##
##   - NO ORPHAN ART. A PNG in assets/portraits/ that belongs to no person in
##     the register is stale weight the next art run would silently carry
##     forward -- the orphan precedent _validate_people() sets for content,
##     pointed at assets (docs/tiers/v2.md §3's warning box).
##   - THE BYTES PATH, NOT load(). A portrait loaded through the import system
##     passes in the editor and fails here, exactly as tests/test_map_view.gd's
##     raster check argues: tools/run_tests.sh runs headless from a fresh clone
##     with no .godot/, and the fonts, the icons, the Blue Marble and now the
##     portraits are all read as bytes for that one reason.
##   - MISSING ART FALLS BACK. A person with no portrait draws the silhouette
##     and the game does not error -- the policy v2.md §3 left to this session
##     to make and record, deliberately the lenient precedent: the register can
##     grow a session ahead of the art run.
##   - EVERY REGISTERED WINDOW CARRIES AN ICON, AND EVERY ICON FILE IS
##     COMMITTED. register() is the one place a window's glyph is written;
##     reading it back off the registry here means this check cannot drift the
##     way the hand-written lists did. The file-exists half is the fresh-clone
##     rule CLAUDE.md states for addons: src/ may reference an at-icons file
##     only if that file is committed, and a referenced-but-uncommitted SVG is
##     invisible until the clone that cannot load it.
##   - THE CARD SHOWS THE PLAYER'S LEADER'S ART. The one surface the session
##     was named for. Derived off the player's own nation, never a person id.
##
## Driven a frame at a time because a Control outside the scene tree has not
## run _ready() -- see docs/engine-decision.md and test_map_view.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const Portrait = preload("res://src/ui/portrait.gd")

const PORTRAITS_DIR := "res://assets/portraits"

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % loader.errors)

	var art: Array[String] = []
	for f in DirAccess.get_files_at(PORTRAITS_DIR):
		if f.ends_with(".png"):
			art.append(f)

	_check_no_orphan_art(loader, art)
	_check_bytes_path(art)
	_check_missing_falls_back()
	_check_window_icons()
	_check_card_shows_art()


func _check_no_orphan_art(loader, art: Array[String]) -> void:
	if art.is_empty():
		_fail("assets/portraits/ holds no PNGs at all -- the duotone pass has not been run or committed")
	for f in art:
		if not loader.person_by_id.has(f.get_basename()):
			_fail("portrait '%s' belongs to no person in the register" % f)


## The headless-fresh-clone half of the bytes rule: whatever art exists must
## materialise as a texture here, where no .godot/ import has ever run.
func _check_bytes_path(art: Array[String]) -> void:
	for f in art:
		var tex := Portrait.texture_for(f.get_basename())
		if tex == null:
			_fail("portrait '%s' did not load from bytes -- read via load() rather than the disk?" % f)
		elif tex.get_width() < 200:
			_fail("portrait '%s' is %d px wide, far below the shipped 216" % [f, tex.get_width()])


func _check_missing_falls_back() -> void:
	var id := "ZZZ_never_authored"
	if Portrait.texture_for(id) != null:
		_fail("an id in no register returned a texture")
	var control = Portrait.control_for(id, Vector2(22, 30))
	if control is TextureRect:
		_fail("a person with no art got a TextureRect rather than the silhouette fallback")


func _check_window_icons() -> void:
	for id in _main._windows.panel_ids():
		var path: String = _main._windows.icon_path(id)
		if path.is_empty():
			_fail("window '%s' registered with no icon" % id)
			continue
		if not FileAccess.file_exists(path):
			_fail("window '%s' references '%s', which is not committed -- a fresh clone fails headless" % [id, path])


func _check_card_shows_art() -> void:
	# The card's bust is a Framed wrapper (the nation band) around the art, so
	# the check walks in one level -- the same reach-through test_map_view.gd
	# uses for map._texture.
	var bust = _main._hud.portrait_card._bust
	if bust == null or bust.get_child_count() == 0 or not (bust.get_child(0) is TextureRect):
		_fail("the portrait card is showing the silhouette -- the player's own leader has no art")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_portraits: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
