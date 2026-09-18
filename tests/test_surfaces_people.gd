extends SceneTree

## V4.3's surface scanner: THE REGISTER IS THE LIST, everywhere a person is
## named in the UI. The panel-system's own law (no hand-written panel lists,
## the sixth-list failure) applied one register down: a file under src/ui/
## that names three or more PERSON ids in one literal is a bench list the
## register did not write -- it will drift the first time content grows and
## nobody will know, which is people-model 9's finding in a new place.
##
## Also pinned: the People panel and the person card exist, take state and
## loader through the standard setup() contract, and the top bar's People
## figure reads the registers the panel reads. These are the structural
## halves a headless suite CAN see; the visual pass is close-out's.

const PeoplePanel = preload("res://src/ui/people_panel.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_no_person_lists_in_ui()
	_check_people_panel_contract()
	_check_person_card_contract()
	_check_top_bar_people_figure()

	if _failures.is_empty():
		print("test_surfaces_people: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## Same shape as test_panel_kit's panel-list scanner, one register down: any
## file under src/ui/ naming three or more distinct person ids (the
## `<NATION>_<surname>` pattern) in string literals is a hand-written list.
## The People panel, the card and the bar name ZERO -- the register names
## everyone.
func _check_no_person_lists_in_ui() -> void:
	var da := DirAccess.open("res://src/ui")
	if da == null:
		_fail("could not open res://src/ui")
		return
	da.list_dir_begin()
	var f := da.get_next()
	var files: Array[String] = []
	while f != "":
		if f.ends_with(".gd"):
			files.append(f)
		f = da.get_next()
	da.list_dir_end()

	for file in files:
		var src := FileAccess.get_file_as_string("res://src/ui/%s" % file)
		if src.is_empty():
			continue
		# String literals only: ids in code come from the register at runtime,
		# which is exactly right. Quotes bound the literal.
		var found: Dictionary = {}
		var rest := src
		var idx := rest.find("\"")
		while idx != -1:
			var close := rest.find("\"", idx + 1)
			if close == -1:
				break
			var literal := rest.substr(idx + 1, close - idx - 1)
			# Split on EVERY separator a list might use -- spaces alone let a
			# comma-joined list of ids collapse into one token and evade the
			# count (the review's finding).
			var token := ""
			for c in literal:
				if c == " " or c == "," or c == ";" or c == "\t":
					var w := _strip_punct(token)
					if w.length() > 4 and w.contains("_") and _looks_like_person_id(w):
						found[w] = true
					token = ""
				else:
					token += c
			var w_last := _strip_punct(token)
			if w_last.length() > 4 and w_last.contains("_") and _looks_like_person_id(w_last):
				found[w_last] = true
			rest = rest.substr(close + 1)
			idx = rest.find("\"")
		if found.size() >= 3:
			_fail("src/ui/%s names %d person ids in string literals (%s) -- the register is the list; grow the register, not the file" % [
				file, found.size(), ", ".join(found.keys().slice(0, 4))])


## A person id is <NATION>_<surname> where NATION is one of the roster's
## three-letter codes and the surname is lowercase. DERIVED from data/nations/
## at run time, not hand-carried: a 30th nation would silently stop matching
## a hand-written 29 (the review's finding), where the directory listing
## cannot drift from the roster it is.
func _roster() -> Array:
	var out: Array = []
	var da := DirAccess.open("res://data/nations")
	if da == null:
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.ends_with(".json"):
			out.append(f.get_basename().to_upper())
		f = da.get_next()
	da.list_dir_end()
	return out


func _looks_like_person_id(w: String) -> bool:
	var parts := w.split("_")
	if parts.size() < 2:
		return false
	if not _roster().has(parts[0]):
		return false
	for i in range(1, parts.size()):
		if parts[i].is_empty() or parts[i] != parts[i].to_lower():
			return false
	return true


## String.strip_edges() plus the punctuation a person id might pick up in
## prose (commas, periods, quotes). Godot has no strip_punctuation; the ids
## themselves never carry punctuation, so the strip is only for the literal's
## surrounding text.
func _strip_punct(w: String) -> String:
	var out := w
	for c in [",", ".", ";", ":", "(", ")", "—", "·"]:
		out = out.replace(String(c), "")
	return out.strip_edges()


## The panel contract: state + loader through setup(), dirty-refresh, and the
## character groups built from the register with no id literals.
func _check_people_panel_contract() -> void:
	var panel = PeoplePanel.new()
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		return
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game(FRA) reported %s" % [state.errors])
		return
	panel.setup(state, loader)
	if panel._loader != loader or panel._state != state:
		_fail("people_panel.setup() did not take the state and loader it was handed")
	# The source half: the panel reads loader.people, never a name literal.
	var src := FileAccess.get_file_as_string("res://src/ui/people_panel.gd")
	if not src.contains("loader.people") and not src.contains("_loader.people"):
		_fail("people_panel.gd does not read the people register -- what is it listing?")


func _check_person_card_contract() -> void:
	var card = PersonCard.new()
	# The card's contract is show_for(person_id, loader, ns, position) and
	# hide; a card that needed state of its own would be a second register.
	var src := FileAccess.get_file_as_string("res://src/ui/person_card.gd")
	if not src.contains("func show_for("):
		_fail("person_card.gd has no show_for -- the shared hover contract is missing")


func _check_top_bar_people_figure() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/top_bar.gd")
	if not src.contains("\"people\""):
		_fail("top_bar.gd has no people figure -- the interim surface was dropped")
	if not src.contains("person_grudges") or not src.contains("person_loyalty"):
		_fail("top_bar.gd's people figure does not read the character registers")


func _fail(message: String) -> void:
	_failures.append(message)
