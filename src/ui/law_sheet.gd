extends RefCounted

## The selected law's sheet -- the detail beside the catalogue (law_list.gd lays the list out and
## owns the verbs). Its page is the law in full, never cut: the name, the summary, the size, the
## channels and the landed price per bloc, the forecast and what waits after the division, the
## verbs, the address -- and, last, the polls it can commission. V5.3 screen 4 PR 2b: the price and
## the polls were the briefing popup's (briefing_sections.gd, which the popup keeps for the bills
## the sheet does not carry), so the division no longer waits behind a second page: Propose here
## divides (law_panel.run_proposal).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const LawGrade = preload("res://src/ui/law_grade.gd")
const LawAddress = preload("res://src/ui/law_address.gd")
const Sections = preload("res://src/ui/briefing_sections.gd")

## The laws whose polls are open on the sheet.
static var _open := {}


static func build(list, box: VBoxContainer, ns, party_list: Array, law) -> void:
	var panel = list._panel
	# V5.2 b+ R2: a bill before the Assembly is the page's first fact while it waits.
	if not ns.tabled_bill.is_empty():
		PanelKit.line(box, list.tabled_text(ns), PanelKit.Tone.PLAIN)
	var title := Label.new()
	title.text = Strings.law_name(law)
	title.theme_type_variation = UiTheme.LEAD
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(title)
	PanelKit.line(box, "%s · %s" % [PanelKit.Labels.law_theme(law.theme), panel._majority_phrase(ns, law)])
	# A system transition rewrites the whole constitution, not one field -- named
	# structurally, off the loaded template's display_name (docs/transition-model.md).
	if law.changes_system:
		var target_id: String = law.effects.get("institutional", {}).get("system_id", "")
		var target = panel._loader.political_systems.get(target_id)
		PanelKit.line(box, Strings.t("Rewrites the constitution to a %s.") % (target.display_name if target != null else target_id), PanelKit.Tone.PLAIN)
	PanelKit.rich(box, Strings.law_summary(law), PanelKit.Tone.PLAIN)
	LawGrade.build(list, box, ns, law)
	# The poll buttons redraw the whole panel: a purchase narrows the forecast on every row too.
	var sections := Sections.new(panel._state, panel._loader, law, list.grade(law), {}, String(law.id), panel.mark_dirty, panel.polled.emit)
	# A Callable does not keep a RefCounted alive: the sheet holds the builder its buttons call.
	box.set_meta("sections", sections)
	sections.channels(box)
	sections.price(box, true)
	box.add_child(list._forecast_bar(ns, party_list, law, 0.0))
	PanelKit.line(box, Strings.t("Forecast: %s") % panel._forecast_text(ns, party_list, LawGrade.read(ns, law, list.grade(law))), PanelKit.Tone.PLAIN)
	for part in list.after_parts(ns, party_list, law, panel.FORECAST_UNCERTAIN_BAND):
		PanelKit.line(box, String(part["text"]), PanelKit.Tone.PLAIN)
	list._verbs(ns, law)
	LawAddress.build(list, box, ns, law)
	_polls(list, box, sections, String(law.id))


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
