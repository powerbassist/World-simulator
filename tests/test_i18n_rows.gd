extends SceneTree

## Headless test: godot --headless --script res://tests/test_i18n_rows.gd
## Non-zero exit on any failure.
##
## V5.1b3. A translated data row reaches the screen -- one row of every kind, on the
## real game scene. "240/240 translated" once meant nothing on screen (the law
## summaries, #38; the programme and the pledges, #39), so this checks the screen and
## not the table: for each kind it opens the surface that shows such rows, finds a row
## whose English is on screen, gives that row a French text in a fixture table written
## here (user://, the run's own), switches the language, and requires the French on
## screen. The rows are picked from what the panel shows, so a content edit moves the
## pick, not the test. The chrome stays English (the fixture's ui table is empty).

const Strings = preload("res://src/ui/strings.gd")
const Projects = preload("res://src/sim/projects.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const Relations = preload("res://src/core/relations.gd")

const DIR := "user://i18n_rows_fixture"
## A row's English must be at least this long to be picked: a short name ("Aid") can sit
## on screen inside some other word.
const MIN_PICK := 6

var _main
var _failures: Array[String] = []
var _probed := 0
var _adopted_id := ""


func _initialize() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(3)
	_write_languages()
	var loader = _main._loader
	var state = _main._state
	var ns = state.player()

	# The term starts on day one: the agenda holds the programme's offer.
	await _probe("programme", "agenda", loader.programme, "name")
	await _probe("laws", "legislature", loader.laws, "name")
	await _probe("laws", "legislature", loader.laws, "summary")
	# An id the panel prints as a word goes through Labels and the UI table.
	await _probe_label("legislature", "institutional")
	await _probe("orgs", "orgs", loader.orgs, "name")
	_adopt_a_rule(state, loader)
	await _probe("bloc-proposals", "orgs", _proposals(loader), "name")
	await _probe("companies:company-actions", "companies", loader.company_actions, "name")
	await _probe("companies:investment-actions", "companies", loader.investment_actions, "name")
	await _probe("energy-actions", "energy", loader.energy_actions, "name")
	await _probe("project-actions", "projects", loader.project_actions, "name")
	_main._on_nation_clicked("DEU")
	await _probe("diplomatic-actions", "", loader.diplomatic_actions, "name")
	# A record that copies a row's name beside its id: an org's common measure is keyed by
	# the bloc PROPOSAL's id, not a diplomatic action's (#49 pass 1). The orgs window
	# closes first, so only the measure line can show the proposal's name.
	_main._windows.close("orgs")
	var measure = _measure_from(state, "DEU", ns.id, _proposals(loader))
	_main._on_nation_clicked("DEU")
	await _probe("measure:bloc-proposals", "", [measure], "name")

	# A project under way names its NOUN, not the imperative on the button.
	for action in loader.project_actions:
		if Projects.execute(state, ns, loader.project_actions, action).get("applied", false):
			break
	await _probe("project-actions", "projects", loader.project_actions, "effects.project.project_name")

	# The run-up: the vote two months out opens the campaign's offers and the pledges.
	_vote_in(state, ns, 2)
	await _probe("campaign-actions", "campaign", loader.campaign_actions, "name")
	await _probe("campaign-actions", "campaign", loader.campaign_actions, "effects.campaign.effort_name")
	await _probe("pledges", "campaign", loader.pledges, "name")
	await _probe("pledges", "campaign", loader.pledges, "effects.pledge.pledge_name")

	# An event on the desk through the console's staging (the UI's own arrival path).
	var ev = loader.events[0]
	_console().run_command("event %s" % ev.id)
	await _probe("events", "events", loader.events, "name")
	await _probe("events", "events", loader.events, "choices")

	Strings.set_language("en")
	Strings.dir = Strings.DIR
	if _probed < 19:
		_fail("only %d of 19 probes ran" % _probed)
	_finish()


## One row of `kind` shown in `window` (opened unless empty), translated through a fixture.
## `kind` may carry a "label:" prefix to tell two probes of one window apart in messages.
## `field` is "name", "summary", a dotted noun path, or "choices" (an event choice label).
func _probe(label: String, window: String, rows: Array, field: String) -> void:
	_probed += 1
	var kind := label.get_slice(":", 1) if label.contains(":") else label
	_set_language("en")
	if window != "":
		_main._windows.open(window)
	_main._windows.mark_all_dirty()
	await _frames(3)
	var english_screen := _screen_text()
	var key := ""
	var english := ""
	for row in rows:
		for pair in _texts(row, field):
			if String(pair[1]).length() >= MIN_PICK and _shows(english_screen, String(pair[1])):
				key = pair[0]
				english = pair[1]
				break
		if key != "":
			break
	if key == "":
		_fail("%s %s: no row's English is on screen in '%s' -- the probe cannot pick one" % [label, field, window])
		return
	var french := "FR %s %s %d" % [kind, field, _probed]
	_write_table(kind, {key: french})
	_set_language("fr")
	_main._windows.mark_all_dirty()
	await _frames(3)
	if not _shows(_screen_text(), french):
		_fail("%s %s: '%s' (%s) is on screen in English, and its French '%s' did not appear; still English in: %s" % [
			label, field, english, key, french, _showing(_main, english)])
	_set_language("en")


## An id word `english` shown in `window` (a Labels table's msgid) is translated by the
## UI table: the fixture's ui.json gets it for the one check.
func _probe_label(window: String, english: String) -> void:
	_probed += 1
	_set_language("en")
	_main._windows.open(window)
	_main._windows.mark_all_dirty()
	await _frames(3)
	if not _screen_text().contains(english):
		_fail("label '%s': not on screen in '%s' -- the probe cannot check it" % [english, window])
		return
	var french := "FR label %d" % _probed
	_write_json(DIR + "/fr/ui.json", {english: french})
	_set_language("fr")
	_main._windows.mark_all_dirty()
	await _frames(3)
	if not _shows(_screen_text(), french):
		_fail("label '%s': its French '%s' did not appear; still English in: %s" % [english, french, _showing(_main, english)])
	_write_json(DIR + "/fr/ui.json", {})
	_set_language("en")


## [[table key, English]] of one row for a field: a loaded object or a row Dictionary.
func _texts(row, field: String) -> Array:
	var id := String(row.get("id")) if row is Dictionary else String(row.id)
	if field == "choices":
		var out: Array = []
		for choice in row.choices:
			out.append(["%s.choices.%s.label" % [id, choice.get("id", "")], String(choice.get("label", ""))])
		return out
	if field.begins_with("effects."):
		var parts := field.split(".")
		var terms: Dictionary = row.effects.get(parts[1], {})
		return [["%s.%s" % [id, field], String(terms.get(parts[2], ""))]] if terms.has(parts[2]) else []
	if row is Dictionary:
		return [["%s.%s" % [id, field], String(row.get(field, ""))]]
	if field == "summary":
		return [["%s.summary" % id, String(row.summary)]]
	var property := {"laws": "law_name", "events": "event_name", "bloc-proposals": "proposal_name", "orgs": "name"}
	for kind in property:
		if row.get(property[kind]) != null:
			return [["%s.name" % id, String(row.get(property[kind]))]]
	return [["%s.name" % id, String(row.action_name)]]


## A council rule in force, its register entry in the shape the sim adopts one with
## (tools/screenshot.gd's --orgs staging): the orgs window lists it by name.
func _adopt_a_rule(state, loader) -> void:
	for org_id in loader.org_proposals:
		if not state.orgs.has(org_id) or not state.player().orgs.has(org_id):
			continue
		for proposal in loader.org_proposals[org_id]:
			if proposal.constraint.is_empty():
				continue
			_adopted_id = String(proposal.id)
			state.orgs[org_id]["rules"][proposal.id] = {
				"name": proposal.proposal_name, "field": String(proposal.constraint["field"]),
				"op": String(proposal.constraint["op"]), "value": float(proposal.constraint["value"]),
				"tolerance": float(proposal.constraint["tolerance"]), "severity": float(proposal.constraint["severity"]),
				"transfer_pct_gdp": 0.0, "since_year": state.year, "since_month": state.month,
			}
			return
	_fail("premise: no council the player sits on has a proposal with a constraint")


## An org's common external measure from `from_id` on `to_id`, every field the sim
## stores one with (orgs.gd _apply_external_measure): its action_id is the PROPOSAL's id.
## A proposal that carries a measure, and not the rule adopted above.
func _measure_from(state, from_id: String, to_id: String, proposals: Array):
	var proposal = null
	for p in proposals:
		if not p.external_measure.is_empty() and String(p.id) != _adopted_id:
			proposal = p
	if proposal == null:
		_fail("premise: no proposal with an external measure besides the adopted rule")
		return proposals[-1]
	state.measures[Relations.directed_key(from_id, to_id)] = {
		"action_id": proposal.id, "action_name": proposal.proposal_name,
		"kind": String(proposal.external_measure["kind"]), "severity": float(proposal.external_measure["severity"]),
		"since_year": state.year, "since_month": state.month, "org": String(proposal.org_id), "retaliated": true,
	}
	return proposal


func _proposals(loader) -> Array:
	var out: Array = []
	for org_id in loader.org_proposals:
		out.append_array(loader.org_proposals[org_id])
	return out


## The player's vote `months` ahead, inside the run-up -- the clock is not ticked.
func _vote_in(state, ns, months: int) -> void:
	if months > CampaignK.CAMPAIGN_WINDOW_MONTHS:
		_fail("premise: the run-up is shorter than %d months" % months)
	var index: int = state.year * 12 + state.month - 1 + months
	ns.next_executive_year = floori(index / 12.0)
	ns.next_executive_month = index % 12 + 1


func _console():
	for child in _main.get_children():
		if child.has_method("run_command"):
			return child
	_fail("premise: no dev console in the game scene")
	return null


## Every text a player can read in the scene right now: labels, buttons, rich text,
## option items and tooltips of visible controls.
func _screen_text() -> String:
	var out := PackedStringArray()
	_collect(_main, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Label or node is Button or node is RichTextLabel or node is LineEdit:
		out.append(String(node.get("text")))
	if node is Control and String((node as Control).tooltip_text) != "":
		out.append(String((node as Control).tooltip_text))
	if node is OptionButton:
		for i in (node as OptionButton).item_count:
			out.append((node as OptionButton).get_item_text(i))
	for child in node.get_children():
		_collect(child, out)


## `text` as written, or as an upper-case heading prints it -- never a case-blind match,
## which found a proposal's name inside an org's summary sentence.
func _shows(screen: String, text: String) -> bool:
	return screen.contains(text) or screen.contains(text.to_upper())


## The visible nodes whose text holds `needle`: where a row still prints its English,
## for the failure message.
func _showing(node: Node, needle: String) -> String:
	var out := PackedStringArray()
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return ""
	var own := PackedStringArray()
	_collect_own(node, own)
	if _shows("\n".join(own), needle):
		out.append("%s \"%s\"" % [node.name, "\n".join(own).left(120)])
	for child in node.get_children():
		var below := _showing(child, needle)
		if below != "":
			out.append(below)
	return ", ".join(out)


func _collect_own(node: Node, out: PackedStringArray) -> void:
	if node is Label or node is Button or node is RichTextLabel or node is LineEdit:
		out.append(String(node.get("text")))
	if node is Control and String((node as Control).tooltip_text) != "":
		out.append(String((node as Control).tooltip_text))


func _set_language(code: String) -> void:
	Strings.dir = DIR
	if not Strings.set_language(code):
		_fail("the fixture language '%s' was refused" % code)


func _write_languages() -> void:
	DirAccess.make_dir_recursive_absolute(DIR + "/fr")
	_write_json(DIR + "/languages.json", {"languages": [
		{"code": "en", "name": "English", "plural_forms": 2, "decimal": "."},
		{"code": "fr", "name": "Français (fixture)", "plural_forms": 2, "decimal": ","},
	]})
	_write_json(DIR + "/fr/ui.json", {})


func _write_table(kind: String, table: Dictionary) -> void:
	_write_json("%s/fr/%s.json" % [DIR, kind], table)


func _write_json(path: String, data) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_i18n_rows: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr("FAIL: %s" % message)
	printerr("test_i18n_rows: %d check(s) failed" % _failures.size())
	quit(1)
