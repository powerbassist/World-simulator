extends SceneTree

## Headless test: godot --headless --script res://tests/test_load_hygiene.gd
## Non-zero exit on any failure.
##
## V5.1-a2. Two things an in-game Load left behind from the DISCARDED game, both
## seen by QA on PR #32 and both what a play gate hits the first time a player loads:
##
##   - its cards. The load path reset the announce MEMORIES and dismissed the
##     decision cards, but every other card stayed up -- "You hold Germany until
##     FEB 2029" over a loaded France game. A load drops the whole stack.
##   - its desk, put back. V5.1-c3.2: the inbox is where a decision is answered,
##     so a load that drops every row must rebuild the Decisions lane from the
##     LOADED desk -- a pending question with no row could be answered only from
##     Dispatches (Review focus 2).
##   - the ribbon's caption. The ribbon redraws only when marked dirty and
##     setup() did not mark it, so after a load it kept the old game's month while
##     the clock showed the loaded one (MAR 2026 over 20 APR 2026).
##
## Driven through main.gd's real handlers, a frame at a time (a Control is half
## dead outside the tree, docs/engine-decision.md).

const SaveManager = preload("res://src/core/save_manager.gd")

const SLOT := "__test_load_hygiene__"
const OTHER_SLOT := "__test_load_hygiene_deu__"
const GameState = preload("res://src/core/game_state.gd")
## Fields that are not a game's: a repaint flag, set by every load's setup() either way.
const IGNORED := {"_dirty": true}

var _failures: Array[String] = []
var _main
var _frame := 0
var _stale_ids: Array[String] = []
var _desk_event := ""
## A main that never played, loading the same Germany save (the general guard's yardstick).
var _fresh
## The People tab's removal confirm card, asked in the France game.
var _confirm


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_save_in_april_then_wander_to_march()
		5:
			_premise()
			_main._clock.set_speed(3)  # the player's speed rides the load (#396 pass 2, T2)
			_main = _load(_main, SLOT)
		9:
			_check_cards()
			_check_load_rebuilds_the_decisions_lane()
			_check_load_restores_the_consequence_card()
			_check_ribbon()
			if int(_main._clock.speed) != 3:
				_fail("a load at speed 3 opened the rebuilt game at speed %d" % int(_main._clock.speed))
			# The loaded game's music band is set at once, not at its first month end (T1).
			var music = _main.get_node_or_null("Music")
			if music == null or (music.band_state as Dictionary).is_empty():
				_fail("after a load the music has no band: the bed stays silent until a month ends")
			_cleanup()
		11:
			_act_in_the_france_game()
			_save_another_nation()
		13:
			_main = _load(_main, OTHER_SLOT)
			# The fresh main boots straight into the loaded nation (QA's TAKE on #396): booted on
			# France as the played one was, a value a panel caches at its FIRST setup would read
			# France in both mains and pass.
			_fresh = load("res://src/ui/main.tscn").instantiate()
			_fresh.pending_player_id = "DEU"
			root.add_child(_fresh)
		16:
			_fresh = _load(_fresh, OTHER_SLOT)
		20:
			_check_no_panel_keeps_the_old_game()
			_cleanup()
			_finish()
	return false


## The general guard (the parent's card after #391/#393, 2026-11-16): a load leaving one
## panel's per-game state behind was fixed six times, one panel at a time. Here the player
## acts in a France game -- a region opened, a programme stop picked, a goods filter, a firm
## verb refused, a person picked -- and then loads a Germany save through main's real load
## path. A second main that never played loads the same save. Every REGISTERED panel (the
## window manager's registry, as the load's own setup() sweep walks it) must then hold the
## same plain values in both: any difference is a field the load kept from the old game.
## Object references (nodes, textures) are not compared as values: they are always new. A reference
## to a GameState or the loader is checked instead: it must be that main's own (_foreign_refs).
##
## Outside the field walk, on purpose (QA's RECORDs on #396): fields of types _plain() does not list
## (Packed*Array, Vector3i, NodePath) and helpers deeper than one level below a panel. Since a load
## rebuilds the game, those are new objects anyway; the three per-game statics are checked by name.
func _act_in_the_france_game() -> void:
	var w = _main._windows
	var ns = _main._state.player()
	var regions: Array = _main._loader.regions.get(ns.id, [])
	if not regions.is_empty():
		w.content("region").open_region(String(regions[0].id))
	var sector = w.content("sector_industry")
	if sector == null:
		_fail("premise: no sector_industry panel to act in")
	else:
		preload("res://src/ui/sector_programme.gd")._pick(sector, 1)
		sector._good_filter = "__a_good_of_the_old_game__"
		sector._last_refusal = "refused in the old game"
	var companies = w.content("companies")
	if companies == null:
		_fail("premise: no companies panel to act in")
	else:
		companies._last_refusal = "refused in the old game"
	var people = w.content("people")
	if people == null:
		_fail("premise: no people panel to act in")
	else:
		for person in _main._loader.people.get(String(ns.id), []):
			people.focus(String(person.id))
			break
		# A removal asked and left on its confirm card: its question is the old game's. (The
		# tab's refresh syncs its verbs; the tab is not open here.)
		people._verbs.sync(_main._state, _main._loader)
		for portfolio in ns.cabinet:
			if String(ns.cabinet[portfolio]) != "":
				people._verbs.dismiss(String(portfolio))
				break
		_confirm = people._verbs._confirm
		if _confirm == null or not _confirm.visible:
			_fail("premise: no removal confirm card up in the France game")
		# A chip other than the default pressed, a name typed in the search, a refusal left on
		# the verbs (QA's TAKE on #396: no act reached these three resets).
		for button in people._chips.get_children():
			if String(button.get_meta("chip", "")) != "needs":
				button.pressed.emit()
				break
		people._search.text = "old game"
		people._search.text_changed.emit("old game")
		people._verbs._refused("Refused in the old game.")
		if people._chip == "needs" or people._verbs.status_text() == "":
			_fail("premise: the People tab's chip or refusal did not take")
	# Two more confirms from other verbs, each on its own card: the Assembly's dissolution and
	# an irreversible firm verb. A load closes every one, whatever asked it (the load's own
	# ConfirmCard.close_all, not each verb's).
	var dissolve = _main._government_panel._dissolve_button
	dissolve.sync(_main._state, ns)
	dissolve.pressed.emit()
	if companies != null:
		var firms: Array = preload("res://src/sim/companies.gd").firms_of(_main._loader, ns.id)
		for action in _main._loader.company_actions:
			if bool(action.irreversible) and not firms.is_empty():
				preload("res://src/ui/firm_commands.gd").act(companies, ns, firms[0], action)
				break
	# Per-game state some panels keep in a static (QA's RECORD on #396): set here, empty after.
	preload("res://src/ui/counter_chips.gd")._picked["__old__"] = "old"
	preload("res://src/ui/law_sheet.gd")._open["__old__"] = true
	preload("res://src/ui/poll_strip.gd")._picked["__old__"] = "old"
	var up: Array = _main.find_children("ConfirmCard", "", true, false).filter(func(c) -> bool: return (c as Control).visible)
	if up.size() < 3:
		_fail("premise: %d confirm cards up before the load, not the removal's, the dissolution's and the firm verb's" % up.size())


## A load REBUILDS the game (the author's call, 2026-11-16: "la solution 2"): main's load hands
## back a new main built from the save, and the one that asked is out of the tree and freed. Every
## check after a load reads the main it returned.
var _old_mains: Array = []

func _load(main, slot: String):
	var parent: Node = main.get_parent()
	var next = main._on_load_requested(slot)
	if next == null or next == main:
		_fail("a load of '%s' did not hand back a new main" % slot)
		return main
	_old_mains.append(main)
	if main.get_parent() != null:
		_fail("the main that asked for the load is still in the tree after it")
	if next.get_parent() != parent:
		_fail("the rebuilt main is not where the old one was")
	# The drivers' per-main entries go with the main they were made for (pass 1, a leak per load).
	var id: int = main.get_instance_id()
	for driver in [preload("res://src/ui/audience_driver.gd"), preload("res://src/ui/briefing_driver.gd"),
			preload("res://src/ui/phone_driver.gd")]:
		if driver._games.has(id):
			_fail("%s keeps the replaced main's entry after a load" % String(driver.resource_path).get_file())
	return next


func _save_another_nation() -> void:
	var other = GameState.new_game(_main._loader, "DEU", "")
	other.year = _main._clock.year
	other.month = _main._clock.month
	var error := SaveManager.save_game(other, _main._clock, OTHER_SLOT)
	if error != "":
		_fail("could not save the Germany game: %s" % error)


func _check_no_panel_keeps_the_old_game() -> void:
	var played: Array = _main._windows.panels()
	var fresh: Array = _fresh._windows.panels()
	if played.size() != fresh.size() or played.is_empty():
		_fail("premise: the two mains register %d and %d panels" % [played.size(), fresh.size()])
		return
	if _main._state.player_nation_id != "DEU" or _fresh._state.player_nation_id != "DEU":
		_fail("premise: a load did not land on Germany")
		return
	# A helper still holding the discarded game's state or loader: every reference to a
	# GameState or the loader must be that main's own (QA's TAKE on #396).
	for side in [_main, _fresh]:
		for panel in side._windows.panels():
			for stale in _foreign_refs(panel, side):
				_fail("%s holds %s from another game after a load" % [String(panel.get_script().resource_path).get_file(), stale])
	# Any confirm card, not only the one asked here: a question asked in the old game is not
	# answered in the loaded one (the cards sit on the screen stack, outside the panels).
	for card in root.find_children("ConfirmCard", "", true, false):
		if (card as Control).visible and card.is_inside_tree():
			_fail("a confirm card asked in the old game is still up after a load (%s)" % card.get_path())
	for old in _old_mains:
		if is_instance_valid(old) and old.is_inside_tree():
			_fail("a main from before a load is still in the tree")
	for holder in [[preload("res://src/ui/counter_chips.gd")._picked, "counter_chips._picked"],
			[preload("res://src/ui/law_sheet.gd")._open, "law_sheet._open"],
			[preload("res://src/ui/poll_strip.gd")._picked, "poll_strip._picked"]]:
		if (holder[0] as Dictionary).has("__old__"):
			_fail("%s keeps the old game's entry after a load" % holder[1])
	# Two of the People tab's are a node's text, not a script variable: read them directly.
	for side in [[_main, "the played game"], [_fresh, "a fresh game"]]:
		var people = side[0]._windows.content("people")
		if people._search.text != "" or people._verbs.status_text() != "":
			_fail("after a load in %s the People tab keeps search '%s', refusal '%s'" % [side[1], people._search.text, people._verbs.status_text()])
	var caught := 0
	for i in played.size():
		var a: Dictionary = _plain_fields(played[i])
		var b: Dictionary = _plain_fields(fresh[i])
		for field in a:
			if IGNORED.has(field) or not b.has(field):
				continue
			if not _same(a[field], b[field]):
				caught += 1
				_fail("%s keeps %s = %s from the old game after a load (a fresh game's load: %s)" % [
					String(played[i].get_script().resource_path).get_file(), field, _short(a[field]), _short(b[field])])
	print("load hygiene: %d registered panels compared, %d stale fields" % [played.size(), caught])


## A panel's script variables whose values are plain data (no Object anywhere inside), and
## those of a UI-owned helper it holds (a script under src/ui/: a state object, as
## region_panel.gd's RegionState, or a node of its own subtree, as people_panel.gd's CabinetVerbs -- not main, not the map), named
## "holder.field". The game's own objects are not UI's.
func _plain_fields(panel: Object, prefix := "") -> Dictionary:
	var out := {}
	for prop in panel.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value = panel.get(String(prop["name"]))
		if _plain(value):
			out[prefix + String(prop["name"])] = value
		elif value is Dictionary or value is Array:
			# A container holding an object (a callable, a node): its size and plain keys.
			out[prefix + String(prop["name"])] = _shape(value)
		elif prefix == "" and (value is RefCounted or (value is Node and panel.is_ancestor_of(value))) 				and value.get_script() != null and String(value.get_script().resource_path).begins_with("res://src/ui/"):
			out.merge(_plain_fields(value, String(prop["name"]) + "."))
	return out


## The fields of a panel, and of the UI-owned helpers it holds (walked the way _plain_fields walks
## them), that reference a GameState or a loader other than `main`'s own.
func _foreign_refs(panel: Object, main, prefix := "") -> Array[String]:
	var out: Array[String] = []
	for prop in panel.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value = panel.get(String(prop["name"]))
		if not (value is Object) or not is_instance_valid(value) or value.get_script() == null:
			continue
		var script: Script = value.get_script()
		if script == main._state.get_script() and not is_same(value, main._state):
			out.append(prefix + String(prop["name"]) + " (a GameState)")
		elif script == main._loader.get_script() and not is_same(value, main._loader):
			out.append(prefix + String(prop["name"]) + " (a loader)")
		elif prefix == "" and (value is RefCounted or (value is Node and panel.is_ancestor_of(value))) 				and String(script.resource_path).begins_with("res://src/ui/"):
			out.append_array(_foreign_refs(value, main, String(prop["name"]) + "."))
	return out


func _shape(v) -> Dictionary:
	var keys: Array = []
	if v is Dictionary:
		keys = (v as Dictionary).keys().filter(func(k) -> bool: return _plain(k))
		keys.sort()
	return {"#size": (v as Dictionary).size() if v is Dictionary else (v as Array).size(), "#keys": keys}


func _plain(v) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_COLOR, TYPE_RECT2:
			return true
		TYPE_ARRAY:
			return (v as Array).all(func(x) -> bool: return _plain(x))
		TYPE_DICTIONARY:
			return (v as Dictionary).keys().all(func(k) -> bool: return _plain(k)) and (v as Dictionary).values().all(func(x) -> bool: return _plain(x))
	return false


func _same(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return typeof(a) == typeof(b) and a == b


func _short(v) -> String:
	var text := str(v)
	return text if text.length() <= 80 else text.substr(0, 77) + "..."


func _save_in_april_then_wander_to_march() -> void:
	var state = _main._state
	state.month = 4
	state.day = 20
	_main._clock.month = 4
	_main._clock.day = 20
	# One quiet question on the saved desk (not an interrupt: the lane must come
	# back for any decision, not only the one that re-raises the pause).
	var Events := load("res://src/sim/events.gd")
	var ns = state.player()
	ns.event_queue.clear()
	for ev in _main._loader.events:
		if not bool(ev.interrupt):
			_desk_event = String(ev.id)
			Events.announce(ns, ev, Events._absolute_month(4, 4), Events.region_names(ns, _main._loader))
			break
	# someday.md C6 (the parent's ruling): the latest consequence is saved state,
	# so a load puts its card back; the discarded game's register is emptied first.
	state.recent_effects.clear()
	state.recent_effects.append({"label": "The saved decision", "year": 2026, "month": 3,
		"movements": [{"label": "Approval", "change": -2.0, "unit": "pp", "severity": -0.4}]})
	_main._on_save_requested(SLOT)
	state.recent_effects.clear()
	ns.event_queue.clear()
	# The "other game": a different month, and cards that only it would have shown.
	state.month = 3
	_main._clock.month = 3
	_main._hud.ribbon.mark_dirty()
	var stack = _main._hud.inbox
	_stale_ids.append(stack.push("Your term", "You hold Germany until FEB 2029 -- 37 months."))
	_stale_ids.append(stack.push("Firm in difficulty", "A firm of the discarded game."))
	_stale_ids.append(stack.push("A decision", "Decide.", [{"label": "Do it", "id": "x"}]))
	_stale_ids.append(stack.push("The term's programme", "Choose.", [], null, true))


func _premise() -> void:
	var title: String = _main._hud.ribbon._title.text
	if not title.begins_with("MAR"):
		_fail("premise: the ribbon shows '%s' before the load, not MAR" % title)
	if _main._hud.inbox.card_count() < _stale_ids.size():
		_fail("premise: the stack holds %d cards, fewer than the %d staged" % [_main._hud.inbox.card_count(), _stale_ids.size()])


## The staged cards were the old main's: a load rebuilds the game, so its inbox is a new one (whose
## card ids start over, so ids say nothing) and none of the staged texts is in it.
func _check_cards() -> void:
	var inbox = _main._hud.inbox
	for id in inbox._cards.keys():
		var text := _text(inbox._cards[id])
		for staged in ["You hold Germany until FEB 2029", "A firm of the discarded game.", "Decide."]:
			if text.contains(staged):
				_fail("the discarded game's card '%s' survived the load" % staged)


func _check_load_rebuilds_the_decisions_lane() -> void:
	var inbox = _main._hud.inbox
	if _desk_event.is_empty():
		_fail("premise: no quiet event to stage on the saved desk")
		return
	var found := ""
	for card_id in _main._event_cards.keys():
		if String(_main._event_cards[card_id]) == _desk_event:
			found = String(card_id)
	if found.is_empty():
		_fail("the loaded desk's '%s' has no row in the inbox" % _desk_event)
	elif inbox.lane_of(found) != "decisions":
		_fail("the loaded desk's row sits in '%s', not Decisions" % inbox.lane_of(found))


func _check_load_restores_the_consequence_card() -> void:
	var inbox = _main._hud.inbox
	for id in inbox._cards.keys():
		if _text(inbox._cards[id]).to_lower().contains("the saved decision"):
			if not _text(inbox._cards[id]).contains("Approval"):
				_fail("the restored consequence card does not say what moved")
			return
	_fail("after a load the inbox has no card for the latest consequence (recent_effects[0])")


func _text(node: Node) -> String:
	var out := ""
	if node is Label or node is RichTextLabel:
		out += String(node.text) + "
"
	for child in node.get_children():
		out += _text(child)
	return out


func _check_ribbon() -> void:
	var title: String = _main._hud.ribbon._title.text
	if not title.begins_with("APR"):
		_fail("after loading an April save the ribbon reads '%s'" % title)


func _cleanup() -> void:
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX,
			SaveManager._path_for(OTHER_SLOT), SaveManager._path_for(OTHER_SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_load_hygiene: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
