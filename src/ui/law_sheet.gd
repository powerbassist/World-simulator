extends RefCounted

## The selected law's sheet -- the detail beside the catalogue (law_list.gd lays the list out and
## owns the verbs). G3 S5, the author's pick "C : le chemin de la loi": the shelf and the verb, the
## name, the summary whole, a shut law's reason; the size; ITS PATH, one step per hurdle
## (law_path.gd); THE ASSEMBLY ON THIS LAW as a chamber of for / undecided / against with the line
## to pass, beside WHAT IT DOES TO THE BLOCS (one diverging bar per bloc, the signed price
## printed) and the channels; then why nothing else can be put now, and one row of verbs: Propose
## filled, Force, the address and the polls, whose strips unfold under the row. Propose here
## divides (law_panel.run_proposal).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const LawGrade = preload("res://src/ui/law_grade.gd")
const LawAddress = preload("res://src/ui/law_address.gd")
const Sections = preload("res://src/ui/briefing_sections.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const LawFilters = preload("res://src/ui/law_filters.gd")
const LawShut = preload("res://src/ui/law_shut.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LawPath = preload("res://src/ui/law_path.gd")
const LawSeatsTip = preload("res://src/ui/law_seats_tip.gd")

## The Assembly's chamber on the law's sheet, px at text size 100 % (the picked picture's, about 220).
const CHAMBER_HEIGHT := 220.0

## The laws whose polls are open on the sheet.
static var _open := {}


static func build(list, box: VBoxContainer, ns, party_list: Array, law) -> void:
	var panel = list._panel
	# The Bills second pass: the shelf and the verb over the name, as the row has them.
	var kicker := Label.new()
	var verb := Strings.law_verb(panel._loader, law)
	var shelf: String = LawFilters.shelf_of(law, panel._loader)
	kicker.text = Labels.law_category(shelf) + (" · " + verb if verb != "" else "")
	kicker.theme_type_variation = UiTheme.MICRO
	box.add_child(kicker)
	var title := Label.new()
	title.text = Strings.law_name(law)
	title.theme_type_variation = UiTheme.LEAD
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(title)
	PanelKit.rich(box, Strings.law_summary(law), PanelKit.Tone.PLAIN)
	# A system transition rewrites the whole constitution, not one field -- named
	# structurally, off the loaded template's display_name (docs/transition-model.md).
	if law.changes_system:
		var target_id: String = law.effects.get("institutional", {}).get("system_id", "")
		var target = panel._loader.political_systems.get(target_id)
		PanelKit.line(box, Strings.t("Rewrites the constitution to a %s.") % (target.display_name if target != null else target_id), PanelKit.Tone.PLAIN)
	var flag: String = list.why(law)
	if flag != "":
		var why := Label.new()
		why.text = LawShut.text(ns, law, flag)
		why.theme_type_variation = UiTheme.WARN_TEXT
		why.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(why)
	LawGrade.build(list, box, ns, law)
	var c: Dictionary = list.counts_of(ns, party_list, law)
	# G3 S5 (Bills = C): the hurdles in a row, then the Assembly's vote beside what it does to
	# the blocs. A shut law has no division coming, so it gets no path and no verdict.
	if flag == "":
		LawPath.build(box, ns, party_list, law, c)
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 24)
	box.add_child(middle)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(left)
	_assembly(list, left, ns, law, c)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(right)
	# The price at the size picked: the passage applies the scaled bill, as the vote reads it.
	_blocs(right, LawGrade.read(ns, law, list.grade(law)))
	# The poll buttons redraw the whole panel: a purchase narrows the forecast on every row too.
	var sections := Sections.new(panel._state, panel._loader, law, list.grade(law), {}, String(law.id), panel.mark_dirty, panel.polled.emit)
	# A Callable does not keep a RefCounted alive: the sheet holds the builder its buttons call.
	box.set_meta("sections", sections)
	sections.channels(right)
	# V5.2 b+ R2: a bill before the Assembly says why nothing else can be put now, above the verbs.
	if not ns.tabled_bill.is_empty():
		PanelKit.line(box, list.tabled_text(ns), PanelKit.Tone.PLAIN)
	var row: Control = list._verbs(ns, law)
	# A shut law has no division to address the country about or to poll: neither is offered.
	if flag == "":
		LawAddress.build(list, box, ns, law, row)
		_polls(list, box, row, sections, String(law.id))


## The Assembly on this law: a chamber of three parts (for, undecided, against) in the vote's
## tones with the law's own line across it, never a per-party seat guess; the rule in words under it.
static func _assembly(list, box: VBoxContainer, ns, law, c: Dictionary) -> void:
	var parts := [
		{"label": Strings.t("For"), "value": float(c["yes"])},
		{"label": Strings.t("Undecided"), "value": float(c["undecided"])},
		{"label": Strings.t("Against"), "value": float(c["no"])},
	]
	var chart: Control = ChartKit.hemicycle(box, Strings.t("The Assembly on this law"), parts,
		{"marker": list.majority_share(ns, law), "colors": list.FORECAST_COLORS, "places": 0, "height": CHAMBER_HEIGHT})
	# The seats by party are one hover away, as they were on the bar (law_seats_tip.gd).
	for drawn in chart.find_children("*", "Control", true, false):  # i18n: ok a class name
		if drawn.has_method("seat_count"):
			drawn.hover = LawSeatsTip.build.bind(list._panel, c)
	var seats := int(c["yes"]) + int(c["no"]) + int(c["undecided"])
	# The rule as the division applies it: more for than against, or a number of seats.
	if String(law.majority) == "simple":
		PanelKit.line(box, Strings.t("It carries with more for than against: the line is half the votes cast."))
	else:
		PanelKit.line(box, Strings.t("The line: %d seats to pass.") % LawPath.seats_to_pass(list.majority_share(ns, law), seats))
	# A threshold other than more yes than no is said in words (a 3/5, a referendum after).
	if String(law.majority) != "simple" or law.constitutional:
		PanelKit.line(box, list._panel._majority_phrase(ns, law))
	if int(c["rebels"]) > 0:
		PanelKit.line(box, Strings.t("%d expected to break ranks.") % c["rebels"])


## What the law does to each bloc: its authored price as it lands (clamped as the passage clamps
## it), one diverging bar per bloc, the signed figure printed -- a zero included, so a bloc the
## law leaves alone is read as left alone rather than forgotten.
static func _blocs(box: VBoxContainer, law) -> void:
	var price: Dictionary = law.effects.get("bloc_offset", {})
	var rows: Array = []
	for bloc in OpinionK.BLOC_KEYS:
		var landed := clampf(float(price.get(bloc, 0.0)), LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)
		rows.append({"label": Labels.bloc(bloc), "value": landed, "text": "0" if landed == 0.0 else Num.fs(landed, 2)})
	var chart := ChartKit.diverging(box, Strings.t("What it does to the blocs"), rows, {"span": LK.BLOC_OFFSET_MAX})
	chart.name = "BlocChart"  # i18n: ok a node name, found by tests


## The polls are a page of their own words (the country's read, the tiers, the whip count), so
## they open on "Poll it" and stay open while the player moves between laws: a display pick, as
## PollStrip's tier is. Closed, the sheet stays inside the Bills tab's word ceiling.
static func _polls(list, box: Control, row: Control, sections, law_id: String) -> void:
	var open: bool = _open.has(law_id)
	var toggle := PanelKit.sized(Button.new())
	toggle.name = "PollIt"  # i18n: ok a node name, found by tests
	toggle.text = Strings.t("Poll it")
	PanelKit.toggle(toggle)
	toggle.button_pressed = open
	# Deferred: the toggle redraws the sheet, and a button may not free itself in its own press.
	toggle.pressed.connect(_flip.bind(list, law_id), CONNECT_DEFERRED)
	row.add_child(toggle)
	if open:
		sections.polls(box)


static func _flip(list, law_id: String) -> void:
	if _open.has(law_id):
		_open.erase(law_id)
	else:
		_open[law_id] = true
	list._panel.mark_dirty()
