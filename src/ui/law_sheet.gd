extends RefCounted

## The selected law's sheet -- the detail beside the catalogue (law_list.gd lays the list out and
## owns the verbs). The Bills second pass (the author's "A : les rayons"): the shelf and the verb,
## the name, the summary whole, a shut law's reason; the size; THE VOTE as the stacked bar by seats
## with the line to pass, its counts and the forecast's verdict; WHAT IT DOES TO THE BLOCS as one
## diverging bar per bloc (chart_kit.gd's diverging()), the signed price printed; then the one
## verb, the channels, the address and -- last -- the polls it can commission. Propose here
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
const LawRow = preload("res://src/ui/law_row.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

## The laws whose polls are open on the sheet.
static var _open := {}


static func build(list, box: VBoxContainer, ns, party_list: Array, law) -> void:
	var panel = list._panel
	# V5.2 b+ R2: a bill before the Assembly is the page's first fact while it waits.
	if not ns.tabled_bill.is_empty():
		PanelKit.line(box, list.tabled_text(ns), PanelKit.Tone.PLAIN)
	# The Bills second pass: the shelf and the verb over the name, as the row has them.
	var kicker := Label.new()
	var verb := Strings.law_verb(panel._loader, law)
	var shelf: String = LawFilters.shelf_of(law, panel._loader)
	kicker.text = (Labels.law_category(shelf) if shelf != LawFilters.DRAFTS else Strings.t("Your drafts")) + (" · " + verb if verb != "" else "")
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
		why.text = LawRow.shut_text(ns, law, flag)
		why.theme_type_variation = UiTheme.WARN_TEXT
		why.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(why)
	LawGrade.build(list, box, ns, law)
	_vote(list, box, ns, party_list, law)
	_blocs(box, law)
	list._verbs(ns, law)
	# The poll buttons redraw the whole panel: a purchase narrows the forecast on every row too.
	var sections := Sections.new(panel._state, panel._loader, law, list.grade(law), {}, String(law.id), panel.mark_dirty, panel.polled.emit)
	# A Callable does not keep a RefCounted alive: the sheet holds the builder its buttons call.
	box.set_meta("sections", sections)
	sections.channels(box)
	LawAddress.build(list, box, ns, law)
	_polls(list, box, sections, String(law.id))


## The vote in full: the stacked bar by seats with the line to pass marked, the counts named under
## it, the forecast's verdict, and what waits after the Assembly (the second chamber, the court).
static func _vote(list, box: VBoxContainer, ns, party_list: Array, law) -> void:
	var panel = list._panel
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = Strings.t("The vote")
	title.theme_type_variation = UiTheme.MICRO
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var c: Dictionary = list.counts_of(ns, party_list, law)
	var seats := int(c["yes"]) + int(c["no"]) + int(c["undecided"])
	var needed := floori(list.majority_share(ns, law) * seats) + 1
	var verdict := verdict_of(c, needed, String(law.majority) == "simple")
	var word := Label.new()
	word.text = verdict[0]
	word.theme_type_variation = verdict[1]
	head.add_child(word)
	box.add_child(list._forecast_bar(ns, party_list, law, 0.0))
	PanelKit.line(box, Strings.t("%d for · %d undecided · %d against · %d to pass") % [c["yes"], c["undecided"], c["no"], needed])
	# A threshold other than more yes than no is said in words (a 3/5, a referendum after).
	if String(law.majority) != "simple" or law.constitutional:
		PanelKit.line(box, panel._majority_phrase(ns, law))
	if int(c["rebels"]) > 0:
		PanelKit.line(box, Strings.t("%d expected to break ranks.") % c["rebels"])
	for part in list.after_parts(ns, party_list, law, panel.FORECAST_UNCERTAIN_BAND):
		PanelKit.line(box, String(part["text"]), PanelKit.Tone.PLAIN)


## The forecast's word and its tone, read off the counts the bar draws: carried only when the
## undecided cannot turn it, lost only when they cannot save it. A simple majority is more yes
## than no; any other is `needed` yes seats.
static func verdict_of(c: Dictionary, needed: int, simple: bool) -> Array:
	var yes := int(c["yes"])
	var no := int(c["no"])
	var open := int(c["undecided"])
	if (simple and yes > no + open) or (not simple and yes >= needed):
		return [Strings.t("passes"), UiTheme.GOOD_SMALL]
	if (simple and no >= yes + open) or (not simple and yes + open < needed):
		return [Strings.t("fails"), UiTheme.BAD_SMALL]
	return [Strings.t("too close to call"), UiTheme.WARN_TEXT]


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
static func _polls(list, box: Control, sections, law_id: String) -> void:
	var open: bool = _open.has(law_id)
	var row := PanelKit.buttons(box)
	var toggle := PanelKit.sized(Button.new())
	toggle.name = "PollIt"  # i18n: ok a node name, found by tests
	toggle.text = Strings.t("Poll it")
	toggle.toggle_mode = true
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
