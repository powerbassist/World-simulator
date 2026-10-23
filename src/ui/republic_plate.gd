extends VBoxContainer

## "How this republic works" -- V5.2-0b, the author's call "Une plaque repliée"
## (docs/design/v5.2-legibility.md, call 3). The constitution's rules -- the system,
## the term limit, the dissolution rule and its price, the formation, the amendment
## rule, the referendum route, the electoral system, the second chamber, the court --
## change only when a law changes them, so they fold away under one header and the
## Politics panel keeps the live arithmetic in view. Folded by default; the panel
## remembers it open across its refreshes.
##
## The sentences are the panel's own, moved here unchanged; `labels` carries the
## panel's label tables so this file holds no second copy of them.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")

var _toggle: Button
var _body: VBoxContainer
var _open := false


func _init() -> void:
	name = "Republic"  # i18n: ok
	add_theme_constant_override("separation", 4)
	_toggle = Button.new()
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.flat = true
	_toggle.pressed.connect(func() -> void: set_open(not _open))
	add_child(_toggle)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	add_child(_body)
	set_open(false)


func set_open(open: bool) -> void:
	_open = open
	_body.visible = open
	_toggle.text = (Strings.t("How this republic works  ▾") if open else Strings.t("How this republic works  ▸"))


func is_open() -> bool:
	return _open


func body() -> VBoxContainer:
	return _body


## Rebuilt with the panel. `upper` and `court` are the panel's own phrases.
func fill(ns, loader, labels: Dictionary, upper: String, court: String) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var system = loader.political_systems.get(ns.system_id)
	var chamber: String = loader.nations[ns.id].chamber_name
	PanelKit.line(_body, "%s." % (system.display_name if system != null else ns.system_id), PanelKit.Tone.PLAIN)
	if ns.head_of_state_kind != "executive_president":
		PanelKit.rich(_body, Strings.t("Head of state: %s %s.") % [ns.head_of_state_title, PanelKit.person(ns.head_of_state_person_id, loader.person_name(ns.head_of_state_person_id))], PanelKit.Tone.PLAIN)
	if ns.term_limit > 0:
		PanelKit.line(_body, Strings.t("Term limit: %d of %d served.") % [ns.terms_served, ns.term_limit], PanelKit.Tone.PLAIN)
	if ns.censure_rule != "none":
		PanelKit.line(_body, Strings.t("Censure: %s.") % Strings.t(labels["censure"].get(ns.censure_rule, ns.censure_rule)), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, "%s %s." % [chamber, Strings.t(labels["dissolution"].get(ns.dissolution_rule, ns.dissolution_rule))], PanelKit.Tone.PLAIN)
	if ns.dissolutions_called > 0:
		PanelKit.line(_body, Strings.t("Dissolutions called this run: %d.") % ns.dissolutions_called, PanelKit.Tone.PLAIN)
	PanelKit.line(_body, Strings.t("Formation: %s.") % Strings.t(labels["method"].get(ns.formation_method, ns.formation_method)), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, Strings.t("Agreed position: economic %s, social %s.") % [
		Num.fs(ns.coalition_position["economic"], 2), Num.fs(ns.coalition_position["social"], 2)], PanelKit.Tone.PLAIN)
	PanelKit.line(_body, Strings.t("A constitutional amendment needs %s.") % Strings.t(labels["amendment"].get(ns.amendment_rule, ns.amendment_rule)), PanelKit.Tone.PLAIN)
	if labels["referendum"].has(ns.referendum_mode):
		PanelKit.line(_body, Strings.t(labels["referendum"][ns.referendum_mode]), PanelKit.Tone.PLAIN)
	var method: String = Strings.t(String(labels["election"].get(ns.election_system, ns.election_system)))
	if ns.election_threshold_pct > 0.0:
		PanelKit.line(_body, Strings.t("The assembly is elected by %s, with a %s%% threshold.") % [method, Num.f(ns.election_threshold_pct, 1)], PanelKit.Tone.PLAIN)
	else:
		PanelKit.line(_body, Strings.t("The assembly is elected by %s, with no threshold.") % method, PanelKit.Tone.PLAIN)
	# V1.1e. The second chamber and the court are NEVER SILENT for a nation that has
	# them (docs/referendum-model.md's V1.7c finding): folded, never removed.
	if ns.has_upper_house:
		PanelKit.line(_body, Strings.t("The %s holds %d seats and %s.") % [ns.upper_chamber_name, ns.upper_seats, upper], PanelKit.Tone.PLAIN)
	else:
		PanelKit.line(_body, Strings.t("There is no second chamber."), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, court, PanelKit.Tone.PLAIN)
