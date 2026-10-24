extends PanelContainer

## The Agenda -- V4.1's surface: the government's programme, chosen at term
## start and tracked while it runs. Model: docs/programme-model.md; the machine
## is src/sim/programme.gd, the content data/programme/.
##
## READS the register and the loader and writes neither: the choose verb goes
## back as the explicit command this panel EMITS -- programme_chosen(entry_id)
## -- and main.gd performs Programme.choose() through it, the Budget.commit()
## shape. The refusal (a stale button, a gate that shut between the offer and
## the press) is answered in main.gd's handler, which owns the card.
##
## NOTHING HERE IS HAND-WRITTEN: the sections are the five groups from
## programme_constants.GROUPS, and the entries under each are whatever
## Programme.available() offers and ns.programme carries. An entry id named in
## a literal in this file would be a second register -- the rule
## tests/test_programme.gd's scanner enforces over this directory.
##
## The progress read is DERIVED on every refresh (Programme.progress_of) and
## the bar's fraction is PanelKit.progress_fraction()'s arithmetic on the pair.
## The panel stores no progress, so it cannot disagree with the sim it reads.
##
## THE WHOLE BODY SCROLLS FROM THE FIRST LINE, campaign_panel.gd's answer to
## the fold a long offer page would otherwise build under its first rows.

signal programme_chosen(entry_id: String)

const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Trends = preload("res://src/ui/trends.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Num = preload("res://src/ui/num.gd")

## election_panel's bar block size: wide enough to read at a glance, short
## enough to leave the window's right edge to the scroll gutter.
const BAR_SIZE := Vector2(240.0, 12.0)

var _state
var _loader
var _dirty := true
var _title: Label
var _body: VBoxContainer

## The first enabled CHOOSE button while the offer is up, else the first live
## entry's block -- primary_action()'s two halves, campaign_panel's device.
var _primary: Control = null

## The term (terms_served) whose offer this panel last drew; -1 before any. main.gd's
## play guard asks it, so the first press of a term opens the Agenda and a press
## after the Agenda has shown the offer runs the clock.
var _offer_seen_term := -1


## Whether the Agenda has shown this term's offer.
func offer_seen(ns) -> bool:
	return _offer_seen_term == int(ns.terms_served)


func _ready() -> void:
	custom_minimum_size = Vector2(560, 520)

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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	# A right margin rather than flush to the scroll: the bar draws its track
	# OVER the content, and a right-aligned figure would run underneath it --
	# campaign_panel.gd's captured frame found that, inherited not rediscovered.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	gutter.add_child(_body)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	_primary = null
	_title.text = tr("Agenda")

	for child in _body.get_children():
		child.queue_free()

	var offer: Array = Programme.available(_state, ns, _loader)
	if offer.is_empty():
		_build_register(ns)
		if Programme.this_term(ns).is_empty():
			PanelKit.line(_body, _unset_text(ns))
		return

	_offer_seen_term = int(ns.terms_served)
	# The frame contract, in the model's own terms: a choice pays nothing
	# (programme-model §8), the delivery is what the register prices.
	# V5.2-0b: one line; the pricing rule (choosing costs nothing, the delivery is
	# priced, no choice runs the term with none) is the programme term's plate.
	PanelKit.line(_body, tr("Pick the term's [g=programme]programme[/g]. Delivery is judged when it lands or its deadline passes."))
	_build_offer(ns, offer)
	_build_register(ns)


# --- The offer ------------------------------------------------------------------------

## Sections per group, in the constants' own order. A group with nothing
## offered draws nothing: an always-there heading for an empty filing is the
## line that says nothing, and the sweep test guarantees each group is used
## by the book even when this term's offer is not.
func _build_offer(ns, offer: Array) -> void:
	var by_group := {}
	for terms in offer:
		var group := String(terms.get("group", ""))
		if not (by_group as Dictionary).has(group):
			by_group[group] = []
		(by_group[group] as Array).append(terms)

	for group in ProgrammeK.GROUPS:
		if not (by_group as Dictionary).has(group):
			continue
		var entries: Array = by_group[group]
		# The authored weight is the order: tests/test_programme.gd's sweep
		# pins that every entry carries one, which is what makes this a
		# content decision rather than a load-order accident.
		entries.sort_custom(func(a, b): return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0)))
		var body := PanelKit.section(_body, Labels.programme_group(String(group)))
		for terms in entries:
			body.add_child(_offer_block(ns, terms))


func _offer_block(ns, terms: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 2)

	PanelKit.line(block, Strings.row_name("programme", terms), PanelKit.Tone.PLAIN)
	PanelKit.rich(block, Strings.row_summary("programme", terms))
	PanelKit.line(block, "%s · %s" % [
		_read_text(ns, terms), _clock_text(terms, 0, false),
	], PanelKit.Tone.DIM)
	block.add_child(_choose_button(terms))
	return block


func _choose_button(terms: Dictionary) -> Button:
	var button := PanelKit.sized(Button.new())
	button.text = tr("Choose")
	button.tooltip_text = PanelKit.TermText.plain(Strings.row_summary("programme", terms))
	var entry_id := String(terms["id"])
	# The verb is a SIGNAL, not a call: the panel names what was chosen and
	# main.gd performs the command. The panel never writes GameState.
	button.pressed.connect(func(): programme_chosen.emit(entry_id))
	if _primary == null:
		_primary = button
	return button


# --- The register ---------------------------------------------------------------------

## Every entry the register carries, this term's and the record's -- an entry
## that concluded stays on it, which is why the section reads as a ledger once
## the offer is gone.
func _build_register(ns) -> void:
	if (ns.programme as Array).is_empty():
		return
	var body := PanelKit.section(_body, tr("The register"))
	for entry in ns.programme:
		body.add_child(_register_block(ns, entry))


func _register_block(ns, entry: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)

	var terms: Dictionary = Programme.terms_of(_loader, String(entry["entry_id"]))
	# A register entry whose content the loader no longer defines is the
	# sim's own load error class (it concludes invalid on the next tick);
	# until then the id stands in for the name rather than a blank row.
	var name_text := Strings.row_name("programme", terms) if not terms.is_empty() else String(entry["entry_id"])
	PanelKit.line(block, name_text, PanelKit.Tone.PLAIN)

	match String(entry["status"]):
		ProgrammeK.STATUS_ACTIVE:
			# The first live entry is this panel's fold answer once the offer
			# is gone -- what the player opened the Agenda to check on.
			if not (_primary is Button):
				_primary = block
			_build_live_read(ns, terms, entry, block)
		ProgrammeK.STATUS_COMPLETE:
			PanelKit.line(block, tr("Delivered, term %d.") % (int(entry["concluded_term"]) + 1), PanelKit.Tone.GOOD)
		ProgrammeK.STATUS_FAIL:
			PanelKit.line(block, tr("Missed, term %d.") % (int(entry["concluded_term"]) + 1), PanelKit.Tone.BAD)
		_:
			PanelKit.line(block, tr("Overtaken by the world, term %d.") % (int(entry["concluded_term"]) + 1), PanelKit.Tone.DIM)
	return block


func _build_live_read(ns, terms: Dictionary, entry: Dictionary, block: VBoxContainer) -> void:
	if terms.is_empty():
		PanelKit.line(block, tr("No content behind this entry; it concludes on the next tick."), PanelKit.Tone.DIM)
		return

	var read: Dictionary = Programme.progress_of(ns, terms)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.max_value = 1.0
	# Range's default step (0.01) SNAPS every assignment to its multiple -- a
	# derived fraction of 0.59376 ships as 0.59 and the read beside it disagrees
	# by half a point of goal. Zero disables the snap; the bar is a display of
	# the pair, not a dial.
	bar.step = 0.0
	bar.value = PanelKit.progress_fraction(
		float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))
	bar.show_percentage = false
	block.add_child(bar)

	PanelKit.line(block, "%s · %s" % [
		_read_text(ns, terms), _clock_text(terms, int(entry["months_live"]), true),
	], PanelKit.Tone.DIM)


# --- The reads ------------------------------------------------------------------------

## The derived pair, printed beside the bar so the number and the bar cannot
## disagree about where the figure stands.
func _read_text(ns, terms: Dictionary) -> String:
	var read: Dictionary = Programme.progress_of(ns, terms)
	return tr("now %s · goal %s") % [Num.f(float(read["current_value"]), 2), Num.f(float(read["goal_value"]), 2)]


## The deadline, from the authored timeout and the register's own months-live
## counter. 0 means the entry stands until it lands -- the model's own reading
## of a goal without a clock, and a line here for it rather than silence.
func _clock_text(terms: Dictionary, live_months: int, is_live: bool) -> String:
	var timeout := int(terms.get("timeout_months", 0))
	if timeout <= 0:
		# The author's rule (2026-10-23, Systems' #97): a goal without a clock is
		# judged when the term ends, then ends.
		return tr("judged at the end of the term")
	if not is_live:
		return tr_n("%d month on the clock", "%d months on the clock", timeout) % timeout
	var left := timeout - live_months
	if left <= 0:
		return tr("month %d of %d · due now") % [live_months, timeout]
	return tr_n("month %d of %d · %d month left", "month %d of %d · %d months left", left) % [
		live_months, timeout, left,
	]


## V5.1-0c. Mid-term the page used to say only "No programme was set this term."
## -- true, and no help to a player who loaded a save or ran past the offer, who
## could not tell a bug from a rule. It states the rule and the date it next opens:
## a programme is chosen on the first day of a term, and the next term starts at
## the vote.
func _unset_text(ns) -> String:
	if Programme.is_term_start(ns):
		return tr("Nothing is offerable this term -- every gate in the book is shut.")
	var rule := tr("No programme was set this term: one is chosen on a term's first day.")
	var when := Trends.vote_date(ns)
	if when.y < 1 or when.y > DateText.SHORT.size():
		return rule  # no vote scheduled: say the rule, not a date that does not exist
	return rule + " " + tr("The next term starts after the vote in %s %d.") % [
		DateText.month(when.y), when.x,
	]


## The control this panel exists to let the player press -- V2.1a's fold
## contract. The choose verb while the offer is up; the first live entry's
## block afterwards, the thing a player opened this window to check on. Null
## when the panel is only a record with nothing running.
func primary_action() -> Control:
	return _primary
