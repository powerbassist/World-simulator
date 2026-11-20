extends SceneTree

## Headless test: godot --headless --script res://tests/test_register_follow.gd
## Non-zero exit on any failure.
##
## V5.3 c' register slice 2 (the author's pick "A pour commander + C en suivi"):
##   - THE GATE: a region warning (UnitWarnings.tick's note) reaches the player. It ended a
##     quiet month with nothing on screen; now an inbox card names the region, and its Open
##     puts the register on that region, the type's band_units placed, with the warning's
##     answers as the sim offers them (UnitWarnings.answers: leave it, or build).
##   - A: the band (Units.band, read once a redraw) marks its rows and says its threshold;
##     Who it moves names the blocs the vote moves (UnitBuild.blocs); the Union line reads
##     the envelope (nothing for a nation in no organisation).
##   - C, the Programmes tab: each programme under way with its months, money paid and
##     left and its opening; an overrun card with its answers (UnitOverrun.asks), answered
##     through UnitOverrun.answer.
##
## Driven through the real inbox and controls a frame apart.

const Units = preload("res://src/sim/units.gd")
const UK = preload("res://src/sim/units_constants.gd")
const UnitWarnings = preload("res://src/sim/unit_warnings.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UnitOverrun = preload("res://src/sim/unit_overrun.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const RegisterWarning = preload("res://src/ui/register_warning.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _note := {}
var _register
var _follow


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_register = _main._windows.content("register")
			_follow = _main._windows.content("programmes")
			if _register == null or _follow == null:
				_fail("no window registered as 'register' and 'programmes' (%s, %s)" % [_register, _follow])
				_finish()
				return false
			# Pass 2 T10: the tab's name is not the finance bill's sector "programmes".
			if _main._windows.title("programmes") != _follow.tr("Building"):
				_fail("the follow-up tab is called '%s', not Building" % _main._windows.title("programmes"))
			_main._windows.open("programmes")
		4:
			if not _text_under(_follow).contains(_follow.tr("No programme is building.")):
				_fail("the empty Programmes tab does not say so: '%s'" % _text_under(_follow))
			_check_envelope()
			_warn()
		5:
			_check_card_arrived()
			_check_one_card_a_subject()
			_check_refused_open_keeps_the_card()
			_press(_go())
		7:
			_check_opened_from_the_warning()
			_check_band_marks()
			_check_blocs_line()
			_check_union_line()
			_press(_with_meta("warning_build", _register))
		9:
			_check_built_from_the_warning()
			_check_restored_after_a_load()
			# Leave it, on a sheet opened from the warning again with the bill empty.
			_main._state.player().tabled_bill = {}
			_register.open_from_warning(String(_note["type"]), String(_note["region"]), 1)
		11:
			_press(_with_meta("warning_leave", _register))
		13:
			if _with_meta("warning_bar", _register) != null:
				_fail("Leave it did not put the warning away")
			# Pass 2 T1: a door that is not the warning's puts the warning away.
			_register.open_from_warning(String(_note["type"]), String(_note["region"]), 1)
			_register.open_for(_other_region())
			if not _register._warning.is_empty():
				_fail("the warning survives a door to another region")
			# C: a programme under way, then its overrun card.
			_open_programme()
			_main._windows.open("programmes")
		15:
			_check_follow_rows()
			_check_overrun_card()
			_check_overrun_arrivals()
			_press(_with_meta("overrun_pay", _follow))
		17:
			var p: Dictionary = _main._state.player().unit_programmes[0]
			if String(p.get("answer", "")) != UK.OVERRUN_PAY:
				_fail("Pay did not answer the card: %s" % [p.get("answer", "")])
			if _with_meta("overrun_card", _follow) != null:
				_fail("the overrun card stays after its answer")
			# Pass 2 T6: a reservation gone (a Delay past its year, the Union left) says the share is lost.
			if p.has("union"):
				p["union"]["reserved_eur_m"] = 0.0
			_follow.mark_dirty()
		19:
			var q: Dictionary = _main._state.player().unit_programmes[0]
			if q.has("union") and (_with_meta("union_lost", _follow) == null or _text_under(_follow).contains(" 0.00 bn for it")):
				_fail("a lost Union share still reads as held: '%s'" % _text_under(_follow))
			_check_no_union_line()
		21:
			if _with_meta("union", _register) != null:
				_fail("a nation in no organisation still shows a Union line")
			_finish()
	return false


## Build here tables the warning's programme (the type's band_units in that region) and
## puts the bar away.
func _check_built_from_the_warning() -> void:
	var held: Array = (_main._state.player().tabled_bill.get("finance", {}) as Dictionary).get("units", [])
	var band_units := int(_main._loader.unit_types[String(_note["type"])]["band_units"])
	if held.size() != 1 or String(held[0]["type"]) != String(_note["type"]) \
			or held[0]["rows"] != [{"region": String(_note["region"]), "units": band_units}]:
		_fail("Build here did not table %d units in %s: %s" % [band_units, _note["region"], held])
	if _with_meta("warning_bar", _register) != null:
		_fail("the warning bar stays after Build here")


## The Union's envelope on C for a member, its figure the sim's.
func _check_envelope() -> void:
	var ns = _main._state.player()
	var org := UnitEnvelope.org_of(_main._loader, ns)
	var section = _with_meta("envelope", _follow)
	if org == "":
		if section != null:
			_fail("an envelope for a nation in no organisation")
		return
	var left := UnitEnvelope.left_eur_m(_main._loader, ns, UnitEnvelope.year_of(UnitPrice.now(_main._state)))
	if section == null or not _text_under(section).contains(Num.f(left / 1000.0, 2)):
		_fail("the envelope does not say the %s bn left" % Num.f(left / 1000.0, 2))
		return
	var period: Dictionary = UnitEnvelope.period_of(_main._loader, org, UnitEnvelope.year_of(UnitPrice.now(_main._state)))
	if not _text_under(section).contains("until %d" % int(period["last_year"])):
		_fail("the envelope does not name its last vote year %d: '%s'" % [int(period["last_year"]), _text_under(section)])


## The month's own arrival: the sim's warning note, through the month's end.
func _warn() -> void:
	var state = _main._state
	var ns = state.player()
	var notes: Array = []
	UnitWarnings.tick(state, ns, _main._loader, UnitPrice.now(state), notes)
	for n in notes:
		if String(n.get("kind", "")) == UnitWarnings.KIND:
			_note = n
	if _note.is_empty():
		_fail("premise: France has no region warning at the start")
		_finish()
		return
	BriefingDriver.month_end(_main, {"units": notes})


func _check_card_arrived() -> void:
	# Out of government the warning is not the player's: no second card.
	var ns = _main._state.player()
	var before: int = _main._hud.inbox.find_children("*", "Button", true, false).size()
	ns.in_government = false
	RegisterWarning.arrive(_main, {"units": [_note]})
	ns.in_government = true
	if _main._hud.inbox.find_children("*", "Button", true, false).size() != before:
		_fail("a warning card arrived out of government")
	if _go() == null:
		_fail("the region warning reached no inbox card")
		return
	var card = _card(_go())
	var name := _region_name(String(_note["region"]))
	if card == null or not _text_under(card).contains(name):
		_fail("the warning card does not name %s: '%s'" % [name, "" if card == null else _text_under(card)])


func _check_opened_from_the_warning() -> void:
	if not _main._windows.is_open("register"):
		_fail("Open did not open the register")
		return
	var type_id := String(_note["type"])
	var region := String(_note["region"])
	if _register.selected_type() != type_id or String(_register.selected_region()) != region:
		_fail("the register opened on %s / %s, not %s / %s" % [_register.selected_type(), _register.selected_region(), type_id, region])
	var band_units := int(_main._loader.unit_types[type_id]["band_units"])
	if _register.rows() != [{"region": region, "units": band_units}]:
		_fail("the warning placed %s, not %d units in %s" % [_register.rows(), band_units, region])
	if _with_meta("warning_bar", _register) == null:
		_fail("no warning bar on a sheet opened from the warning")
	var build = _with_meta("warning_build", _register)
	var answers: Array = UnitWarnings.answers(_main._state, _main._state.player(), _main._loader, type_id, region)
	var debt := Num.f(float(answers[1]["debt_eur_bn"]), 2)
	if build == null or not _text_under(build.get_parent().get_parent()).contains(debt):
		_fail("the build answer does not say the sim's %s bn" % debt)
	if _with_meta("warning_leave", _register) == null:
		_fail("no Leave it on the warning")


## The band read once: the chart's warning rows are the sim's band, and the chip says why.
func _check_band_marks() -> void:
	var ns = _main._state.player()
	var band: Dictionary = Units.band(ns, _main._loader, _register.selected_type())
	var dots = _with_meta("dots", _register)
	if dots == null:
		_fail("no dot plot")
		return
	var rows: Array = dots.data()
	for i in rows.size():
		if dots.in_band(i) != band.has(String(rows[i]["id"])):
			_fail("row %s: marked %s, the sim's band says %s" % [rows[i]["id"], dots.in_band(i), band.has(String(rows[i]["id"]))])
	var chip = _with_meta("band_chip", _register)
	if band.is_empty() != (chip == null):
		_fail("the band chip is %s while the band holds %d regions" % ["shown" if chip != null else "missing", band.size()])
	elif chip != null and not (_text_under(chip).contains(Num.f(100.0 * UK.UNIT_REGION_BAND, 0)) and _text_under(chip).contains(str(UK.UNIT_REGION_WORST))):
		_fail("the band chip does not say the threshold: '%s'" % _text_under(chip))


func _check_blocs_line() -> void:
	var moves: Dictionary = UnitBuild.blocs(_main._state.player(), _main._loader,
		{"type": _register.selected_type(), "op": UK.OP_BUILD, "rows": _register.rows()})
	var line = _with_meta("blocs", _register)
	if moves.is_empty():
		return
	if line == null:
		_fail("no blocs line for a build that moves %s" % [moves])
		return
	for bloc in moves:
		if not _text_under(line).contains(Labels.bloc(String(bloc))):
			_fail("the blocs line does not name %s: '%s'" % [bloc, _text_under(line)])


func _check_union_line() -> void:
	var ns = _main._state.player()
	if UnitEnvelope.org_of(_main._loader, ns) == "" or not bool(_main._loader.unit_types[_register.selected_type()].get("cofinanced", false)):
		return
	if _with_meta("union", _register) == null:
		_fail("a member's cofinanced build shows no Union line")


## A nation in no organisation: no Union line on either sheet (checked a frame later).
func _check_no_union_line() -> void:
	var ns = _main._state.player()
	ns.orgs = []
	_main._windows.open("register")
	_register.mark_dirty()


func _open_programme() -> void:
	var state = _main._state
	var ns = state.player()
	var type_id := String(_note["type"])
	var row := {"type": type_id, "op": UK.OP_BUILD, "rows": [{"region": String(_note["region"]), "units": 3}]}
	var p: Dictionary = UnitBuild.open(state, ns, _main._loader, row)
	# Its overrun card, posted now (UnitOverrun.tick's shape).
	p["ask"] = {"kind": "overrun", "posted": UnitPrice.now(state), "due": UnitPrice.now(state) + UK.UNIT_OVERRUN_WINDOW_MONTHS,
		"default": UK.OVERRUN_PAY, "eur_m": 0.1 * float(p["contract_eur_m"])}
	# Pass 2 T2: five months built, then a Delay of fifteen (the total is no longer build_months).
	p["paid_month"] = int(p["voted"]) + 4
	p["months_left"] = int(p["build_months"]) + 15 - 5
	# Its Union reservation (UnitEnvelope.reserve's shape), held whatever the start's envelope.
	var org := UnitEnvelope.org_of(_main._loader, ns)
	if org != "":
		var period: Dictionary = UnitEnvelope.period_of(_main._loader, org, UnitEnvelope.year_of(UnitPrice.now(state)))
		p["union"] = {"org": org, "period": String(period["id"]), "pays_until": int(period["pays_until_year"]) + 20,
			"reserved_eur_m": 123.0, "paid_eur_m": 0.0, "months_left": 0}
	_follow.mark_dirty()


func _check_follow_rows() -> void:
	var ns = _main._state.player()
	var rows := _all_with_meta("programme", _follow)
	if rows.size() != ns.unit_programmes.size():
		_fail("C shows %d programmes, the register holds %d" % [rows.size(), ns.unit_programmes.size()])
		return
	var p: Dictionary = ns.unit_programmes[0]
	var built_text := "5 of %d months built" % (5 + int(p["months_left"]))
	if not _text_under(_follow).contains(built_text):
		_fail("after a Delay the row does not say '%s': '%s'" % [built_text, _text_under(_follow)])
	var lanes = _with_meta("lanes", _follow)
	if lanes == null or lanes.data().size() != 1 or int(lanes.data()[0]["opens"]) != UnitPrice.opens_at(p) \
			or int(lanes.data()[0]["start"]) != int(p["voted"]) or not bool(lanes.data()[0]["ask"]):
		_fail("the lanes do not draw the register's months and ask: %s" % [null if lanes == null else lanes.data()])
	var text := _text_under(rows[0])
	if text.contains(".0 "):
		_fail("a count printed as a float: '%s'" % text)
	if p.has("union") and not text.contains(Num.f(float(p["union"]["reserved_eur_m"]) / 1000.0, 2)):
		_fail("the programme row does not say the Union's reservation: '%s'" % text)


func _check_overrun_card() -> void:
	var asks: Array = UnitOverrun.asks(_main._state, _main._state.player(), _main._loader)
	var card = _with_meta("overrun_card", _follow)
	if asks.is_empty() or card == null:
		_fail("no overrun card for a posted ask (%d asks)" % asks.size())
		return
	for a in asks[0]["ask"]["answers"]:
		if _with_meta("overrun_" + String(a["id"]), _follow) == null:
			_fail("the card does not offer the sim's answer %s" % a["id"])
		var squares = _with_meta("units_" + String(a["id"]), _follow)
		if squares == null or squares.kept != int(a["units"]):
			_fail("answer %s: the squares do not keep the sim's %d units" % [a["id"], int(a["units"])])
	var bill = _with_meta("bill_if_paid", _follow)
	if bill == null or bill.years().is_empty():
		_fail("no year's bill under the overrun card")


# --- helpers ---------------------------------------------------------------

func _go():
	for b in _main._hud.inbox.find_children("*", "Button", true, false):
		if ActsOn.acts_on(b, RegisterWarning.SUBJECT + String(_note.get("type", "")) + "|" + String(_note.get("region", ""))) and not _gone(b):
			return b
	return null


func _card(node):
	var up: Node = node
	while up != null and not (up is PanelContainer):
		up = up.get_parent()
	return up


func _region_name(id: String) -> String:
	for r in _main._loader.regions.get(_main._state.player().id, []):
		if String(r.id) == id:
			return String(r.region_name)
	return id


func _press(button) -> void:
	if button == null:
		_fail("button to press not found")
		return
	if button.disabled:
		_fail("button '%s' is disabled" % button.text)
		return
	button.pressed.emit()


func _all_with_meta(key: String, from: Node) -> Array:
	var out: Array = []
	if from.has_meta(key) and from.is_visible_in_tree() and not _gone(from):
		out.append(from)
	for child in from.get_children():
		out.append_array(_all_with_meta(key, child))
	return out


func _with_meta(key: String, from: Node):
	var found := _all_with_meta(key, from)
	return found[0] if not found.is_empty() else null


func _gone(node: Node) -> bool:
	var up: Node = node
	while up != null:
		if up.is_queued_for_deletion():
			return true
		up = up.get_parent()
	return false


func _text_under(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + " "
	elif node is Button:
		out += (node as Button).text + " "
	for label in node.find_children("*", "", true, false):
		if label is Label:
			out += (label as Label).text + " "
		elif label is RichTextLabel:
			out += (label as RichTextLabel).get_parsed_text() + " "
		elif label is Button:
			out += (label as Button).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_register_follow: OK")
		quit(0)
	else:
		for f in _failures:
			push_error("FAIL " + f)
		quit(1)


## Pass 2 T11: a second arrival beside an unanswered card is dropped.
func _check_one_card_a_subject() -> void:
	RegisterWarning.arrive(_main, {"units": [_note]})
	if _gos().size() != 1:
		_fail("a second card beside the unanswered one: %d" % _gos().size())


## Pass 2 T3: an Open that cannot show its tab (a scene holds the screen) keeps the card.
func _check_refused_open_keeps_the_card() -> void:
	var scene = _main._windows.frame("audience")
	if scene == null:
		_fail("premise: no audience scene to hold the screen")
		return
	scene.visible = true
	_press(_go())
	scene.visible = false
	if _go() == null:
		_fail("the card went with an Open the screen refused")


## Pass 2 T4: the inbox is not saved; a warning still waiting comes back on a fresh main.
func _check_restored_after_a_load() -> void:
	RegisterWarning.restore_after_load(_main)
	if _go() == null:
		_fail("an unanswered warning did not come back after a load")


## Pass 2 T5: an overrun ask is a card, its default and the Union's lapse are notes.
func _check_overrun_arrivals() -> void:
	var p: Dictionary = _main._state.player().unit_programmes[0]
	RegisterWarning.arrive(_main, {"units": [{"kind": "overrun_landed", "id": String(p["id"]), "eur_m": 1.0},
		{"kind": "overrun_defaulted", "id": String(p["id"]), "eur_m": 80.0},
		{"kind": "lapse_warning", "eur_m": 120.0, "year": 2027}]})
	var card := false
	for b in _main._hud.inbox.find_children("*", "Button", true, false):
		if ActsOn.acts_on(b, RegisterWarning.OVERRUN + String(p["id"])) and not _gone(b):
			card = true
	if not card:
		_fail("an overrun ask reached no inbox card")
	var text := _text_under(_main._hud.inbox)
	if not text.contains(Num.f(0.08, 2)) or not text.contains(Num.f(0.12, 2)):
		_fail("the default and the lapse are not noted: '%s'" % text.left(300))


func _gos() -> Array:
	var out: Array = []
	for b in _main._hud.inbox.find_children("*", "Button", true, false):
		if ActsOn.acts_on(b, RegisterWarning.SUBJECT + String(_note.get("type", "")) + "|" + String(_note.get("region", ""))) and not _gone(b):
			out.append(b)
	return out


func _other_region() -> String:
	for r in _main._loader.regions.get(_main._state.player().id, []):
		if String(r.id) != String(_note["region"]) and Units.start_capacity(_main._loader, _main._state.player().id, String(_note["type"]), r.id) > 0.0:
			return String(r.id)
	return ""
