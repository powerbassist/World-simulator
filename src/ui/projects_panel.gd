extends PanelContainer

## Public works -- V1.6f's one new surface.
##
## Reads simulation state and content, and writes neither: the verb goes back as an
## explicit command through `acted`, which is the shape Budget.commit() set and
## companies_panel.gd follows.
##
## IT IS ITS OWN WINDOW, WHERE V1.6e HUNG ITS WHOLE SURFACE ON companies_panel.gd's
## EXISTING SECTOR HEADINGS. That worked because a sector programme is pointed at
## exactly the heading that panel was already printing. A project is pointed at
## nothing on it: it is a dated national commitment, not a sectoral one, and the
## Industry panel is already 434 lines whose body is guaranteed to overflow --
## V1.6e's own screenshot pass paid for that fold. Registering a window is one
## `_windows.register()` call plus one line in main.gd's `_build_action_bar()`, which
## is what U5a's shell was for.
##
## THE WHOLE BODY SCROLLS FROM THE FIRST LINE, companies_panel.gd's answer to the
## fold nation_panel.gd has paid for three times. Ten actions and up to five live
## projects is more than a fixed column can hold, and both lists grow.
##
## THREE SECTIONS AND NOT ONE, because a project is in one of three states and each
## is a different question. What is being BUILT is what the treasury is paying for
## now; what is FINISHED is what the country has permanently bought; and what is
## AVAILABLE is what is left. Collapsing them into one list would hide the only thing
## a player has to plan around -- that the payoff arrives years after the bill.

signal closed
## (before_snapshot, label) -- the same pair companies_panel.acted, nation_panel.acted
## and law_panel.proposed emit, so beginning a project earns a U4 decision delta on
## the terms a subsidy and a law already do.
signal acted(before, label)

const Projects = preload("res://src/sim/projects.gd")
const ProjectsK = preload("res://src/sim/projects_constants.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
## Kept rather than left local, for companies_panel.gd's reason: this panel's content
## overflows once anything is under way, so the row a screenshot flag has just acted
## on is usually below the fold, and a frame that cannot show it proves nothing about
## the row it exists to check. tools/screenshot.gd drives this; nothing in the game
## does.
var _scroll: ScrollContainer
var _pin_bottom := false
var _close_button: Button

## The first enabled verb this panel built on its last refresh. See primary_action().
var _primary: Control = null


func _ready() -> void:
	custom_minimum_size = Vector2(520, 560)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	# The body sits inside a right margin rather than flush to the scroll, because a
	# ScrollContainer draws its bar OVER the content and the right-aligned figures in
	# _row() would run underneath it. companies_panel.gd's first captured frame is
	# what found that; inherited rather than rediscovered.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	_scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	gutter.add_child(_body)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Pins the scroll to the bottom, for tools/screenshot.gd. A STANDING FLAG rather
## than a one-shot call, because _refresh() rebuilds every child and a scroll set
## before the next rebuild is undone by it. companies_panel.gd's own correction.
func scroll_to_bottom() -> void:
	_pin_bottom = true
	_dirty = true


func _apply_bottom() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	_primary = null

	_title.text = tr("Public Works")

	for child in _body.get_children():
		child.queue_free()

	_build_ledger(ns)
	_build_building(ns)
	_build_completed(ns)
	_build_available(ns)

	if _pin_bottom:
		_apply_bottom()


## The two figures the register produces, and they are the two ENDS of this lever
## rather than a summary of it. The bill is what the treasury pays this month for
## work in progress; the trend is what finished work has permanently bought. Both
## read exactly 0.0 for a player who has begun nothing, which is the honest readout
## and not a bug.
##
## THE SECOND ROW IS THE TARGET AND NOT WHAT HAS ARRIVED, and the caption says so.
## economy_constants.SHIFT_ADJUST is a five-year lag, so a project that completed
## last month has bought its full addend and delivered almost none of it -- printing
## the delivered figure alone would tell a player their motorway did nothing.
func _build_ledger(ns) -> void:
	PanelKit.heading(_body, tr("The public account"))
	PanelKit.row(_body, tr("Construction bill"), tr("%s %% of GDP") % Num.f(ns.project_bill_pct_gdp, 3))
	PanelKit.row(_body, tr("Trend bought"), tr("%s %%/yr") % Num.fs(ns.project_potential_target_pct, 3))
	if ns.project_potential_target_pct > 0.0:
		PanelKit.line(_body, tr("Bought, not yet delivered: completed works raise the trend the economy is heading for, and it takes about five years to arrive."))


func _build_building(ns) -> void:
	var live := Projects.building(ns)
	PanelKit.heading(_body, tr("Under construction"))
	if live.is_empty():
		PanelKit.line(_body, tr("Nothing is being built."))
		return
	for pid in live:
		_build_live(ns, String(pid))


## One project in flight, with the two things a player needs and nothing else: how
## far through it is, and what it will be worth. The progress is shown as months
## REMAINING rather than as a percentage, because months remaining is what the
## register actually holds and what the diary prints -- two surfaces reporting one
## fact in two units is how they come to disagree.
func _build_live(ns, project_id: String) -> void:
	var terms := Projects.terms_of(_loader, project_id)
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, Strings.noun("project-actions", _loader.project_actions, "project", "project_id", project_id, "project_name", Projects.name_of(_loader, project_id)), PanelKit.Tone.PLAIN)

	var left := Projects.months_left(ns, project_id)
	var total := int(terms.get("build_months", 0))
	PanelKit.line(block, tr("%d of %d months remaining · %s %% of GDP a year · will buy %s %%/yr") % [
		left, total, Num.f(float(terms.get("cost_pct_gdp", 0.0)), 3),
		Num.fs(float(terms.get("potential_growth_pct", 0.0)), 3),
	], PanelKit.Tone.GOOD)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for action in Projects.available(_state, ns, _loader.project_actions):
		if String(action.effects.get("project", {}).get("project_id", "")) != project_id:
			continue
		buttons.add_child(_button(ns, action))
	block.add_child(buttons)

	_body.add_child(block)


## What the country has permanently bought. Listed rather than summed into the
## ledger's one figure, because a president who inherits a finished rail spine
## should be able to see whose it was -- and because the accumulator alone cannot
## say what is in it.
func _build_completed(ns) -> void:
	var done := Projects.completed(ns)
	if done.is_empty():
		return
	PanelKit.heading(_body, tr("Finished"))
	for pid in done:
		var terms := Projects.terms_of(_loader, String(pid))
		PanelKit.row(_body,
			Strings.noun("project-actions", _loader.project_actions, "project", "project_id", String(pid), "project_name", Projects.name_of(_loader, String(pid))),
			"%s %%/yr" % Num.fs(float(terms.get("potential_growth_pct", 0.0)), 3),
		)


## Everything the player could begin now. A project already begun or already built
## is not here, because Projects.available() refuses it structurally -- so this list
## shrinks over a game and never offers the same motorway twice.
func _build_available(ns) -> void:
	PanelKit.heading(_body, tr("Available"))
	var offered := 0
	for action in Projects.available(_state, ns, _loader.project_actions):
		var terms: Dictionary = action.effects.get("project", {})
		if String(terms.get("op", "")) != "start":
			continue
		offered += 1
		_build_offer(ns, action, terms)
	if offered == 0:
		# Reachable two ways and they are different states, so the caption names both:
		# every project begun, or the `project_count` gate closed by what is already
		# under way. A player who cannot tell which will think the lever is broken.
		if Projects.building_count(ns) > 0:
			PanelKit.line(_body,
				tr("Nothing can begin while %d are under construction. Finish or abandon one.")
				% Projects.building_count(ns)
			)
		else:
			PanelKit.line(_body, tr("Every project has been built."))


func _build_offer(ns, action, terms: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, tr("%d months · %s %% of GDP a year · %s %%/yr when it opens") % [
		int(terms.get("build_months", 0)), Num.f(float(terms.get("cost_pct_gdp", 0.0)), 3),
		Num.fs(float(terms.get("potential_growth_pct", 0.0)), 3),
	])
	block.add_child(_button(ns, action))

	_body.add_child(block)


func _button(ns, action) -> Button:
	var button := Button.new()
	button.text = Strings.row_name("project-actions", action)
	button.tooltip_text = Strings.row_summary("project-actions", action)
	button.pressed.connect(func(): _on_act(ns, action))
	if _primary == null and not button.disabled:
		_primary = button
	return button


## U4's contract, companies_panel._on_invest()'s shape exactly: the baseline is
## captured BEFORE the command, so the delta measures the month the work began
## against the month before it.
func _on_act(ns, action) -> void:
	var before := Budget.snapshot(_state)
	var result := Projects.execute(_state, ns, _loader.project_actions, action)
	if not result.get("applied", false):
		return
	_dirty = true
	acted.emit(before, Strings.row_name("project-actions", action))


## The control this panel exists to let the player press -- V2.1a's fold contract.
##
## Duck-typed: window_frame.gd asks through has_method(), so a panel with nothing
## to press simply does not implement this and never draws the fold mark. The
## FIRST enabled action is the answer rather than the last, because a panel whose
## first verb has scrolled off is already a panel whose verbs are hidden.
func primary_action() -> Control:
	return _primary if is_instance_valid(_primary) else null
