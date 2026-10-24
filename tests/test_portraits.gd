extends SceneTree

## V2.3. The portrait pipeline's load-bearing properties, each named by the
## doc that owns it:
##
##   - NO ORPHAN ART. A PNG in assets/portraits/ that belongs to no person in
##     the register is stale weight the next art run would silently carry
##     forward -- the orphan precedent PeopleLoader.validate_people() sets for content,
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
##     rule AGENTS.md states for addons: src/ may reference an at-icons file
##     only if that file is committed, and a referenced-but-uncommitted SVG is
##     invisible until the clone that cannot load it.
##   - THE CARD SHOWS THE PLAYER'S LEADER'S ART. The one surface the session
##     was named for. Derived off the player's own nation, never a person id.
##   - V3.7 -- EMOTION COMPLETENESS. A person with one emotion carries all
##     five; a partial person is the one incompleteness the lenient fallback
##     policy does not extend to (a missing mood would fall back mid-session).
##   - V3.7 -- ALPHA IS REAL. A matting step that silently no-ops ships a grey
##     rectangle over every backdrop; a sampled transparent pixel proves it.
##   - V3.7 -- EVERY SCENE HAS ITS FILES. src/ names a backdrop per Scene
##     value; the fresh-clone rule makes committed-ness a test, not a promise.
##   - V3.7 -- THE TWO SCENE LISTS AGREE. Summit.SCENES validates the data,
##     Portrait.SCENE_NAMES composites the display; either alone is a summit
##     whose room cannot exist.
##   - V3.7 -- THE PROMPT BUILDER IS GATED. python --self-check runs on every
##     suite pass: the likeness policy, sidecar coverage, roles, regions and
##     determinism, enforced headless with no GPU.
##
## Driven a frame at a time because a Control outside the scene tree has not
## run _ready() -- see docs/engine-decision.md and test_map_view.gd.

const DataLoader = preload("res://src/core/data_loader.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Summit = preload("res://src/core/summit.gd")

const PORTRAITS_DIR := "res://assets/portraits"
const SCENES_DIR := "res://assets/portrait_scenes"
const WIDE_DIR := "res://assets/portrait_scenes_wide"
const EMOTIONS := ["neutral", "pleased", "stern", "worried", "weary"]

var _failures: Array[String] = []
var _main
var _frame := 0

## V3.7's two art layers, probed from the tree state that actually exists:
## the flat legacy PNGs (the Phase A/B bridge) and the per-emotion WebPs.
## Floors differ because the two generations are different rasters -- 216px
## duotone sources vs 432px photographic cut-outs.


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
	for emotion in ["neutral", "pleased", "stern", "worried", "weary"]:
		var sub := PORTRAITS_DIR.path_join(emotion)
		if not DirAccess.dir_exists_absolute(sub):
			continue
		for f in DirAccess.get_files_at(sub):
			if f.ends_with(".webp"):
				art.append(emotion + "/" + f)

	_check_no_orphan_art(loader, art)
	_check_bytes_path(art)
	_check_missing_falls_back()
	_check_window_icons()
	_check_card_shows_art()
	_check_emotion_completeness()
	_check_every_executive_has_a_face(loader)
	_check_every_met_cast_has_a_face(loader)
	_check_emotion_axis()
	_check_alpha_is_real()
	_check_scene_files()
	_check_wide_scene_files()
	_check_scene_set_pin()
	_check_python_teeth()


func _check_no_orphan_art(loader, art: Array[String]) -> void:
	if art.is_empty():
		_fail("assets/portraits/ holds no art at all in either layer -- neither generation has been run or committed")
	for f in art:
		if not loader.person_by_id.has(_pid_of(f)):
			_fail("portrait '%s' belongs to no person in the register" % f)


## The art list carries two shapes: flat legacy names ("AUT_kettler.png") and
## per-emotion paths ("neutral/AUT_kettler.webp"). The person id is the
## basename of the FILE part in both -- a get_basename() on the whole string
## kept the directory in the id and failed every WebP as an orphan.
func _pid_of(f: String) -> String:
	var file_part := f.get_slice("/", 1) if "/" in f else f
	return file_part.get_basename()


## The headless-fresh-clone half of the bytes rule: whatever art exists must
## materialise as a texture here, where no .godot/ import has ever run.
func _check_bytes_path(art: Array[String]) -> void:
	for f in art:
		var emotion: int = _emotion_index(f.get_slice("/", 0)) if "/" in f else 0
		var tex = Portrait.texture_for(_pid_of(f), emotion)
		if tex == null:
			_fail("portrait '%s' did not load from bytes -- read via load() rather than the disk?" % f)
			continue
		var floor_px := 400 if "/" in f else 200
		if tex.get_width() < floor_px:
			_fail("portrait '%s' is %d px wide, below the %d floor" % [f, tex.get_width(), floor_px])


func _emotion_index(name: String) -> int:
	return Portrait.EMOTION_DIRS.find(name)


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
	# The card's bust is a plain frame (or, from Phase B, a Staged composite)
	# around the art, so the check walks in one level -- the same reach-through
	# test_map_view.gd uses for map._texture.
	var bust = _main._hud.portrait_card._bust
	if bust == null or bust.get_child_count() == 0 or not (bust.get_child(0) is TextureRect):
		_fail("the portrait card is showing the silhouette -- the player's own leader has no art")


func _fail(message: String) -> void:
	_failures.append(message)


## V3.7: a person with one emotion's art must have all five, or the game
## silently falls back mid-session on one mood and not another -- the
## generation pass writes whole people or the wall is lying. Partial WALLS are
## fine (a person with no art at all reads the silhouette, the standing
## policy); partial PEOPLE are the one incompleteness the lenient policy does
## not extend to.
func _check_emotion_completeness() -> void:
	if not DirAccess.dir_exists_absolute(PORTRAITS_DIR.path_join("neutral")):
		return  # Phase A: no WebP art exists yet, nothing to be incomplete
	var loader := DataLoader.new()
	loader.load_all()
	var bench_ids: Dictionary = {}
	for nation_id in loader.people.keys():
		for person in loader.people[nation_id]:
			bench_ids[person.id] = bool(person.bench)
	var per_person := {}
	for emotion in EMOTIONS:
		var dir := PORTRAITS_DIR.path_join(emotion)
		if not DirAccess.dir_exists_absolute(dir):
			_fail("emotion dir '%s' missing while 'neutral' exists -- a partial generation run" % emotion)
			continue
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".webp"):
				var pid := f.get_basename()
				per_person[pid] = int(per_person.get(pid, 0)) + 1
	for pid in per_person:
		# V4.3's tiers: the met cast (bench: false) carries all five emotions;
		# the deep bench (bench: true) ships the single neutral. A bench person
		# with five emotions is fine -- an upgraded tier -- and a met-cast
		# person with fewer than five is the one mood that falls back.
		var required := 1 if bool(bench_ids.get(pid, false)) else EMOTIONS.size()
		if per_person[pid] < required:
			_fail("'%s' carries %d of %d emotions -- one mood would fall back mid-session"
				% [pid, per_person[pid], required])


## V5.2a: an executive is someone the president sits across from in an
## audience (the builder's price talk is one), and a chief with no face draws
## the silhouette on the one card a scene is built around. The silhouette
## fallback stays lenient for the deep bench; it is not for them. Checked off
## the register's own `kind`, never a list here, so a fifth hundred firms
## cannot ship faceless.
func _check_every_executive_has_a_face(loader) -> void:
	var seen := 0
	for nation_id in loader.people.keys():
		for person in loader.people[nation_id]:
			if person.kind != "executive":
				continue
			seen += 1
			var path := PORTRAITS_DIR.path_join("neutral").path_join(person.id + ".webp")
			if not FileAccess.file_exists(path):
				_fail("executive '%s' has no neutral portrait at %s" % [person.id, path])
	if seen == 0:
		_fail("the register holds no executives -- this check is looking at nothing")


## V5.2a: the met cast (bench: false) are the people the president actually
## faces, and the silhouette fallback is for the deep bench only. The 88 the
## V4.3 harvest left bare (the generated nations' majors) now carry all five
## moods; _check_emotion_completeness holds the "all five" half once any art
## exists, this holds the "has art at all" half.
func _check_every_met_cast_has_a_face(loader) -> void:
	for nation_id in loader.people.keys():
		for person in loader.people[nation_id]:
			if person.bench:
				continue
			var path := PORTRAITS_DIR.path_join("neutral").path_join(person.id + ".webp")
			if not FileAccess.file_exists(path):
				_fail("met-cast person '%s' has no neutral portrait at %s" % [person.id, path])


## The emotion vocabulary is hand-carried in tools/ and src/ -- the scene
## lists got a two-sources pin, so the emotion axis gets its own: the
## display's directory list is exactly the five names in enum order, and this
## test's local copy agrees. Without it, a -1 find() silently reads "weary".
func _check_emotion_axis() -> void:
	if Portrait.EMOTION_DIRS.size() != EMOTIONS.size():
		_fail("EMOTION_DIRS carries %d entries, expected %d" % [Portrait.EMOTION_DIRS.size(), EMOTIONS.size()])
	for i in mini(Portrait.EMOTION_DIRS.size(), EMOTIONS.size()):
		if String(Portrait.EMOTION_DIRS[i]) != EMOTIONS[i]:
			_fail("EMOTION_DIRS[%d] is '%s', expected '%s'" % [i, Portrait.EMOTION_DIRS[i], EMOTIONS[i]])


## V3.7: the matting step's silent failure mode. A bust with no transparent
## pixel is a grey rectangle that would sit over every backdrop. Sampled with
## a stride, on the WebP the game actually decodes -- alpha that died in the
## post-pass shows up here, not in play.
func _check_alpha_is_real() -> void:
	var dir := PORTRAITS_DIR.path_join("neutral")
	if not DirAccess.dir_exists_absolute(dir):
		return
	var sampled := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".webp") or sampled >= 5:
			continue
		sampled += 1
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(dir.path_join(f))) != OK:
			_fail("committed bust '%s' is not decodable WebP" % f)
			continue
		var transparent := false
		var total := img.get_width() * img.get_height()
		for i in range(0, total, 997):
			if img.get_pixel(i % img.get_width(), i / img.get_width()).a < 0.05:
				transparent = true
				break
		if not transparent:
			_fail("bust '%s' has no transparent pixel -- the matting no-oped" % f)


## V3.7: src/ names a scene file for every Scene value, so every one of those
## files must be committed -- the window-icon rule for the new asset class.
## Until assets/portrait_scenes/ exists (Phase A) there is nothing to demand.
## V5.2a: the 16:9 audience backdrops. The four rooms the first audiences are
## held in must each carry their pool of three, every file must be a scene
## name plus a variant, and every file must decode at exactly 1280x720 -- a
## wrong-sized backdrop is a letterboxed audience window nobody notices in a
## headless run. Absent directory = the batch has not landed (Phase A rule).
func _check_wide_scene_files() -> void:
	if not DirAccess.dir_exists_absolute(WIDE_DIR) or DirAccess.get_files_at(WIDE_DIR).is_empty():
		return
	for scene_name in ["office", "cabinet_room", "corridor", "press_room"]:
		for variant in 3:
			if not FileAccess.file_exists(WIDE_DIR.path_join("%s_%d.webp" % [scene_name, variant])):
				_fail("wide backdrop '%s_%d' is missing -- the audience window would have no room" % [scene_name, variant])
	for f in DirAccess.get_files_at(WIDE_DIR):
		if not f.ends_with(".webp"):
			continue
		var scene_name := f.get_basename().rsplit("_", true, 1)[0]
		if not Portrait.SCENE_NAMES.values().has(scene_name):
			_fail("wide backdrop '%s' names no scene the display knows" % f)
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(WIDE_DIR.path_join(f))) != OK:
			_fail("wide backdrop '%s' is not a decodable WebP" % f)
		elif img.get_size() != Vector2i(1280, 720):
			_fail("wide backdrop '%s' is %s, expected 1280x720" % [f, img.get_size()])


func _check_scene_files() -> void:
	# The class arrives when its FILES arrive: the post-pass can leave an empty
	# directory behind (it ran on a tree with no raws), and an empty dir is
	# still Phase A -- nothing in src/ can resolve.
	if not DirAccess.dir_exists_absolute(SCENES_DIR) or DirAccess.get_files_at(SCENES_DIR).is_empty():
		return
	for scene_name in Portrait.SCENE_NAMES.values():
		for variant in 3:
			var path := SCENES_DIR.path_join("%s_%d.webp" % [scene_name, variant])
			if not FileAccess.file_exists(path):
				_fail("scene '%s' is missing its committed backdrop '%s' -- the composite would degrade silently for every person" % [scene_name, path])

	# Per-nation variants (<scene>_<NATION>_<n>.webp): optional per scene and
	# nation, but never partial -- the variant pool exists as a pool of three
	# or not at all, and every name must parse as a scene the display stages
	# plus a nation code. This is the flag-in-the-office rule: a Belgian
	# monarch's backdrop must not be somebody else's country.
	var nation_counts := {}
	for f in DirAccess.get_files_at(SCENES_DIR):
		if not f.ends_with(".webp"):
			continue
		var base := f.get_basename()
		# Longest scene name wins: "airport_tarmac_0" is the scene
		# airport_tarmac + variant 0, not something called "airport".
		var scene_name := ""
		var tail := ""
		for candidate in Portrait.SCENE_NAMES.values():
			if base.begins_with(candidate + "_") and candidate.length() > scene_name.length():
				scene_name = candidate
				tail = base.substr(candidate.length() + 1)
		if scene_name == "":
			_fail("backdrop '%s' matches no scene naming convention" % f)
			continue
		var us := tail.rfind("_")
		if us == -1:
			continue  # the generic <scene>_<n>
		if not tail.substr(us + 1).is_valid_int():
			_fail("backdrop '%s' matches no scene naming convention" % f)
			continue
		var head := tail.substr(0, us)
		if head != "":
			if head.length() != 3 or head != head.to_upper():
				_fail("backdrop '%s' carries no valid nation code" % f)
			else:
				var key: String = scene_name + "_" + head
				nation_counts[key] = int(nation_counts.get(key, 0)) + 1
	for key in nation_counts:
		if nation_counts[key] != 3:
			_fail("nation backdrop '%s' has %d of 3 variants" % [key, nation_counts[key]])


## The two-sources rule: Summit.SCENES is what the loader VALIDATES the data
## against; Portrait.SCENE_NAMES is what the display COMPOSITES from. Either
## list edited alone is a summit whose room cannot exist, refused here.
func _check_scene_set_pin() -> void:
	var display: Array = Portrait.SCENE_NAMES.values()
	if display.size() != Summit.SCENES.size():
		_fail("scene lists disagree in size: display %d vs validation %d" % [display.size(), Summit.SCENES.size()])
	for scene_name in Summit.SCENES:
		if not display.has(scene_name):
			_fail("validation accepts scene '%s' that the display cannot stage" % scene_name)
	for scene_name in display:
		if not Summit.SCENES.has(scene_name):
			_fail("display stages scene '%s' that validation would refuse" % scene_name)


## Phase A's real teeth: the prompt builder is gated on every suite run -- the
## likeness policy, sidecar coverage, role derivation, region variety and
## determinism all enforced headless with no GPU. python is already a gate
## dependency (the suite runner itself).
func _check_python_teeth() -> void:
	var out: Array = []
	# SUITE_PYTHON: tools/run_tests.sh exports the interpreter it found (python or python3).
	var code := OS.execute(OS.get_environment("SUITE_PYTHON") if OS.has_environment("SUITE_PYTHON") else "python",
		[ProjectSettings.globalize_path("res://tools/portraits_generate.py"), "--self-check"], out)
	if code != 0:
		_fail("the portrait prompt builder failed --self-check (exit %d): %s" % [code, out])


func _finish() -> void:
	if _failures.is_empty():
		print("test_portraits: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
