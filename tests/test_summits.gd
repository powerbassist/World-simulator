extends SceneTree

## Headless test: godot --headless --script res://tests/test_summits.gd
## Non-zero exit on any failure.
##
## V2.4b's summit scenes. Model: docs/tiers/v2.md section 4,
## docs/calendar-model.md section 12's successor notes.
##
## The load-bearing properties:
##
##   - src/sim/summits.gd is a LEAF. It preloads Cycle (the shared hash, a
##     leaf itself) and nothing else. A summit module that reached for
##     Diplomacy or Legislature would be the calendar's failure -- the widest
##     dependency in src/sim/ with the narrowest job.
##   - the draw is DETERMINISTIC. Same meeting stamp, same scene -- the event
##     hazard's discipline, because a replay or a reload that produced a
##     different dinner would be a save that lies.
##   - the sidecar's contract is ENFORCED AT LOAD. Every response label priced,
##     every price carried by a real response, every channel one a law or an
##     event choice could reach. The two live bugs this project names most
##     often -- the live button that refuses silently, the figure printed into
##     nothing -- are both this shape.
##   - NO NEW SERIALISED STATE. A summit is ephemeral: what it changed is
##     already in the channels it applied through. GameState.to_dict() must
##     carry nothing new, and SAVE_VERSION stays 27.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Summits = preload("res://src/sim/summits.gd")
const Summit = preload("res://src/core/summit.gd")
const DM = preload("res://addons/dialogue_manager/dialogue_manager.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader
var _state


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_state = GameState.new_game(_loader, PLAYER)
	_state.year = 2026
	_state.month = 3

	_check_leaf()
	_check_draw_is_deterministic_and_covering()
	_check_content_compiles()
	_check_sidecar_contract_refuses_bad_content()
	_check_scene_field()
	_check_no_new_state()
	_check_arrival_chain_by_source()
	_finish()


## The leaf rule, read off the source like calendar.gd's: Cycle is the one
## allowed preload -- the shared hash both events.gd and economy already use --
## and anything else is the scheduler failure in a new costume.
func _check_leaf() -> void:
	var file := FileAccess.open("res://src/sim/summits.gd", FileAccess.READ)
	if file == null:
		_fail("could not read src/sim/summits.gd")
		return
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const ") or not trimmed.contains("preload("):
			continue
		if trimmed.contains("cycle.gd"):
			continue
		_fail("summits.gd preloads a system: `%s` -- the draw must stay a leaf" % trimmed)


## Same stamp, same scene; a nation with no pool draws nothing; and the draw
## stays inside the pool and never panics across many stamps. With one summit
## per shipped nation the index cannot be observed directly -- the coverage
## clause that would catch a hash returning entry 0 forever needs a pool of
## two, and that is exercised through from_dict + the same modulo the draw
## uses, not through surgery on the loader's register.
func _check_draw_is_deterministic_and_covering() -> void:
	var a := Summits.draw(_state, _loader, "DEU")
	var b := Summits.draw(_state, _loader, "DEU")
	if a.is_empty() or b.is_empty():
		_fail("a nation with summit content drew nothing")
	elif String(a["id"]) != String(b["id"]):
		_fail("the same meeting drew two different scenes: %s then %s" % [a["id"], b["id"]])

	if not Summits.draw(_state, _loader, "ESP").is_empty():
		_fail("ESP has no summit content but drew one -- the empty pool must read as no scene")

	# The index over a synthetic pool of two, with the SAME Cycle call draw()
	# makes: both entries must appear across stamps, or the draw is a constant
	# wearing a pool's clothes.
	var pool: Array = []
	var errs: Array[String] = []
	for i in 2:
		pool.append(Summit.from_dict(
			"~ start\nA: Line.\n- One => One\n- Two => Two\n~ One\nA: One. => END\n~ Two\nA: Two. => END\n",
			"ESP", "ESP_syn%d" % i,
			{"name": "S%d" % i, "summary": "s", "effects": {"One": {}, "Two": {}}},
			"syn%d" % i, errs,
			["income_tax", "vat"], ["health", "defence"], ["business", "workers"],
			["agriculture", "industry", "services"]
		))
	if not errs.is_empty():
		_fail("the synthetic pool did not build: %s" % [errs])
	else:
		var seen := {}
		var probe = GameState.new_game(_loader, PLAYER)
		probe.year = 2026
		probe.month = 3
		probe.player_nation_id = PLAYER
		for stamp in range(64):
			probe.met_months["ESP|FRA"] = probe.year * 12 + probe.month + stamp
			var pick: float = Summits.Cycle.unit("summit|ESP", int(probe.met_months["ESP|FRA"]))
			var index: int = int(pick * float(pool.size())) % pool.size()
			seen[index] = true
		if seen.size() != 2:
			_fail("the draw's index never left entry %s across 64 stamps -- a pool of one wearing a pool of two" % [str(seen.keys())])

	# And many stamps never panic or leave the pool on shipped content.
	for stamp in range(64):
		_state.met_months["DEU|FRA"] = _state.year * 12 + _state.month + stamp
		var d := Summits.draw(_state, _loader, "DEU")
		if d.is_empty():
			_fail("draw came back empty at stamp %d" % stamp)
			break
	_state.met_months.erase("DEU|FRA")


## Every shipped scene compiles through the addon, right here, the way the
## game will compile it at draw time. A scene that fails here is content that
## ships a window that opens onto nothing.
func _check_content_compiles() -> void:
	var manager = DM.new()
	for nation_id in _loader.summits.keys():
		for summit in _loader.summits[nation_id]:
			var resource = manager.create_resource_from_text(String(summit.dialogue_text))
			if resource == null:
				_fail("'%s' did not compile through dialogue_manager" % summit.id)
				continue
			var titles: PackedStringArray = resource.get_titles()
			if titles.size() < 2:
				_fail("'%s' compiled to %d titles -- a scene is more than a start" % [summit.id, titles.size()])


## The sidecar contract, refused loudly. Three bad fixtures: a price with no
## response behind it, a response with no price, and a channel that is not
## one. Each must land in the errors list, by the exact clause written for it.
func _check_sidecar_contract_refuses_bad_content() -> void:
	var dialogue := "~ start\nA: Line.\n- Sign it => Sign it\n- Refuse => Refuse\n~ Sign it\nA: Signed. => END\n~ Refuse\nA: Refused. => END\n"
	var tax := ["income_tax", "vat"]
	var spend := ["health", "education", "defence", "pensions", "infrastructure"]
	var bloc := ["business", "workers", "rural", "urban", "students", "pensioners"]
	var sectors := ["agriculture", "industry", "services"]

	# Each fixture runs against a scratch list so the assertion is about the
	# refusal, not about this test's own failure list.
	var errs: Array[String] = []
	Summit.from_dict(dialogue, "DEU", "X1",
		{"name": "n", "summary": "s", "effects": {"Not offered": {"bloc_offset": {"business": 0.1}}}},
		"X1", errs, tax, spend, bloc, sectors)
	if errs.is_empty():
		_fail("a price with no response behind it was accepted")

	# The complete sidecar -- every offered response priced, no orphan price --
	# is the one that must pass clean.
	errs = []
	Summit.from_dict(dialogue, "DEU", "X2",
		{"name": "n", "summary": "s", "effects": {"Sign it": {}, "Refuse": {}}},
		"X2", errs, tax, spend, bloc, sectors)
	if not errs.is_empty():
		_fail("a complete sidecar was refused: %s" % [errs])

	errs = []
	Summit.from_dict(dialogue, "DEU", "X3",
		{"name": "n", "summary": "s", "effects": {"Sign it": {"relations": 5.0}}},
		"X3", errs, tax, spend, bloc, sectors)
	if errs.is_empty():
		_fail("a channel no law or event choice could reach (relations) was accepted -- pair state has one writer with an actor behind it, and a summit is neither")

	errs = []
	Summit.from_dict(dialogue, "DEU", "X4",
		{"name": "n", "summary": "s", "effects": {"Refuse": {}}},
		"X4", errs, tax, spend, bloc, sectors)
	if errs.is_empty():
		_fail("a response offered with no price at all was accepted")


## The ephemeris. A summit is a scene, not a register: nothing new on
## GameState's dict, and summits.gd itself never earns a bump. The number
## below tracks the CURRENT version rather than freezing at V2.4b's 27,
## because two sessions since have moved it for reasons that have nothing to
## do with summits: V2.5 took it to 28 for NationState.region_gdp_eur_bn,
## since national GDP became the sum of the regions and an absent register
## means the country has no economy at all; V2.6a took it to 29 for
## NationState.region_pop_share and city_pop_share, since the two population
## partitions became live state and absent, every city's population is zero.
## test_save_load.gd pins the version; THIS file pins the absence, because a
## session that serialises a summit history has to come here and say why the
## diary of dinners cannot be derived from the state it already changed.
func _check_no_new_state() -> void:
	# 30 is V2.6b2's, on the campaign-sited registers -- not on anything a summit
	# carries. The pin below that nothing summit-shaped is serialised still stands;
	# a bump FOR a summit surface is what this check exists to catch.
	if GameState.SAVE_VERSION != 35:
		_fail("SAVE_VERSION moved for an ephemeral surface -- the bump is %d; if its recorded reason is a summit field, stop. V3.2's bump is the bloc->orgs rename, not a summit field; V3.3's reason is recorded and is NO field -- the roster is content and round-trips through data/, but the roster a save was made against is part of its contract: from_dict builds nations from the save dictionary ALONE and the gate refuses only version MISMATCHES, so a version-32 save made against the ten-nation roster would load, unrefused, as a silent ten-nation world against twenty-seven-member org data -- nineteen nations dropped without an error anywhere -- so the bump is the loader saying the roster changed; V3.5's reason is recorded and is `start_co2e_per_capita_t` -- the measured per-capita emissions baseline, a fourth content-derived static beside V2.8's three: from_dict() never sees the loader, so absent it a reloaded France reads 0.0 t/capita against a live 4.0 and the accord's baseline is silently gone; V4.1's reason is recorded and is the government's programme on two fields -- `ns.programme`, the chosen register, and `programme_stock`, the credit its conclusion pulses feed -- not a summit field: a save that dropped either un-prices a term the player already lived" % GameState.SAVE_VERSION)
	var d: Dictionary = _state.to_dict()
	if d.has("summits") or d.has("summit_history"):
		_fail("GameState serialises summit state -- a summit is ephemeral by construction")


## The arrival chain, read at source the way test_ribbon.gd reads its wiring:
## the dispatch fires a summit only for a KEPT meeting-carrying arrival, and
## the conclusion applies effects through Legislature's applier. A summit on a
## refused arrival would be a scene about a journey home; effects applied
## anywhere but the applier would be a new channel wearing the old name.
func _check_arrival_chain_by_source() -> void:
	var file := FileAccess.open("res://src/ui/main.gd", FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	if not text.contains("action2.opens_meeting"):
		_fail("the arrival chain does not read opens_meeting -- the summit would fire on acts that are not meetings")
	if not text.contains("_open_summit("):
		_fail("main.gd never opens a summit")
	if not text.contains("Legislature.apply_effects"):
		_fail("summit effects do not apply through the shared applier")
	# and the panel never applies its own
	var panel := FileAccess.open("res://src/ui/summit_panel.gd", FileAccess.READ)
	var panel_text := panel.get_as_text()
	panel.close()
	# Comments talk ABOUT the applier -- the header names it -- so the check
	# reads only code lines, the same discipline the preload checks use.
	for line in panel_text.split("
"):
		if line.strip_edges().begins_with("#"):
			continue
		if line.contains("apply_effects") or line.contains("Budget.commit"):
			_fail("summit_panel applies effects -- the panel owns the frame, the orchestrator owns the state: %s" % line.strip_edges())
			break


## The V3.7 scene field: which backdrop the portrait system stages behind the
## leader. It is DISPLAY data, but it is carried by the CONTENT, so the
## validation lives where the other sidecar clauses live -- at load. An
## unknown name must be refused loudly (a summit staged into a room the game
## cannot draw is the unread refusal wearing a backdrop), and the absent key
## must default to the summit hall -- ConfigFile has no per-key erase and a
## Dictionary does, so "the default fires on absence" is tested by rebuilding
## the dict WITHOUT the key, the established pattern.
func _check_scene_field() -> void:
	var dialogue := "~ start\nA: Line.\n- Sign it => Sign it\n~ Sign it\nA: Signed. => END\n"
	var errs: Array[String] = []
	var s = Summit.from_dict(dialogue, "DEU", "X5",
		{"name": "n", "summary": "s", "scene": "nightclub", "effects": {"Sign it": {}}},
		"X5", errs,
		["income_tax", "vat"], ["health", "defence"], ["business", "workers"],
		["agriculture", "industry", "services"])
	if errs.is_empty():
		_fail("a scene the game cannot stage ('nightclub') was accepted")
	if String(s.scene) != "summit_hall":
		_fail("a refused scene must leave the field at the default, got '%s'" % s.scene)

	# Absent key -> the default. Same fixture minus the key.
	errs = []
	var s2 = Summit.from_dict(dialogue, "DEU", "X6",
		{"name": "n", "summary": "s", "effects": {"Sign it": {}}},
		"X6", errs,
		["income_tax", "vat"], ["health", "defence"], ["business", "workers"],
		["agriculture", "industry", "services"])
	if not errs.is_empty():
		_fail("a sidecar with no scene key was refused: %s" % [errs])
	if String(s2.scene) != "summit_hall":
		_fail("an absent scene must default to summit_hall, got '%s'" % s2.scene)

	# The shipped content: every sidecar's scene is one the game can stage, and
	# the draw carries it through to the panel.
	for nation_id in _loader.summits.keys():
		for summit in _loader.summits[nation_id]:
			var drawn := Summits.draw(_state, _loader, nation_id)
			if drawn.is_empty():
				continue
			if String(drawn.get("scene", "")) == "":
				_fail("draw for %s carries no scene -- the panel cannot stage it" % summit.id)
				break


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_summits: all checks passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
