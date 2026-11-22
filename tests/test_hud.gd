extends SceneTree

## Headless test: godot --headless --script res://tests/test_hud.gd
## Non-zero exit on any failure.
##
## U5a's furniture, where test_shell.gd covers its placement and its wiring.
## The split is by failure mode rather than by file: everything here is
## something that goes wrong **without erroring** -- an icon that silently does
## not load, a flag whose colours never arrive, a message column that grows
## until it runs off the screen. AGENTS.md's rule that UI which can fail
## silently needs a test is the whole reason this file exists.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const AccentRule = preload("res://src/ui/accent_rule.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Icon = preload("res://src/ui/icon.gd")
const MoodIcon = preload("res://src/ui/mood_icon.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const President = preload("res://src/sim/president.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if _frame > 2:
		return _later_frames()

	_check_icons_load()
	_check_portrait_names_the_player()
	_check_flag_data_reaches_the_card()
	_check_mood_reads_the_polled_figure()
	_check_the_bar_after_the_rebuild()
	_check_face_is_fixed_and_mood_is_an_icon()
	_check_inbox()
	_check_lanes_by_kind()
	_check_decisions_are_never_evicted()
	_check_choice_row_wraps()
	_check_requests_lane_empty_state()
	_check_set_body()
	_check_card_is_an_answer_surface()
	_check_foreign_acts_reach_the_column()
	_stage_tall_cards()
	return false


func _later_frames() -> bool:
	if _frame < 5:
		return false  # a layout pass or two for the cards to take their height
	if _frame == 5:
		_check_cards_do_not_push_the_ui_down()
		# V5.1-c2.2: the floating windows' "clear of the column" and "a grown window
		# stays on screen" checks went with the windows. A docked page is the dock's
		# size whatever its content, and the dock's place is tests/test_workspace.gd's.
		# #439 QA T1: at the reference size, the inbox put away gives the workspace back.
		root.size = Vector2i(1920, 1080)
		_main._windows.open("finances")
		_main._hud.inbox.slide_out()
		return false
	if _frame == 7:
		_check_the_workspace_is_full_with_the_inbox_away()
		_main._windows.open("calendar")
		return false
	if _frame == 10:
		_check_own_sheets_on_the_header_grid("calendar")
		# Design's T14 on #441: the Sectors pages bring their own sheets too.
		_main._windows.open("companies")
		return false
	if _frame == 13:
		_check_own_sheets_on_the_header_grid("companies")
		_main._windows.open("sector_industry")
		return false
	if _frame < 16:
		return false
	_check_own_sheets_on_the_header_grid("sector_industry")
	_finish()
	return false


## The workspace is always full (G3 decision 9): with the inbox put away it reaches GAP_PANE short of
## the screen's right edge, and the gap beside it is the map's -- a pointer there reaches the map,
## not a holder behind the workspace (the old test_shell strip claim, re-aimed at the gap).
func _check_the_workspace_is_full_with_the_inbox_away() -> void:
	var gap := float(UiTheme.GAP_PANE)
	if _main._hud.inbox.visible:
		_fail("premise: the inbox did not slide away")
	var dock: Rect2 = _main._windows.dock().get_global_rect()
	if not is_equal_approx(dock.end.x, 1920.0 - gap):
		_fail("with the inbox away the workspace ends at %.0f, not a gap short of 1920 (%.0f)" % [dock.end.x, 1920.0 - gap])
	var viewport: Viewport = _main.get_viewport()
	var point := Vector2(1920.0 - gap / 2.0, 540.0)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	var hit: Control = viewport.gui_get_hovered_control()
	if hit != null and hit != _main._map_view and not _main._map_view.is_ancestor_of(hit):
		_fail("the gap right of the workspace lands on %s (%s), not the map" % [hit.name, hit.get_class()])


## Design's gate T1 on #439: a panel that brings its own sheets sets them on the header sheet's
## grid -- its first sheet a gap under the header, its outer edges on the header's -- with no
## margin left over from the page sheet that went away.
func _check_own_sheets_on_the_header_grid(id: String) -> void:
	var header: Rect2 = (_main._windows.dock().get_child(0) as Control).get_global_rect()
	if not _main._windows._pages[id].own_sheets():
		_fail("%s's page draws a sheet behind its own (window_manager OWN_SHEETS)" % id)
	var sheets: Array = _main._windows.content(id).find_children("*", "PanelContainer", true, false).filter(
		func(n): return n.theme_type_variation == UiTheme.PLATE and n.is_visible_in_tree())
	if sheets.is_empty():
		_fail("premise: %s shows no sheet" % id)
		return
	var left := INF
	var right := -INF
	var top := INF
	var bottom := -INF
	for sheet in sheets:
		var r: Rect2 = sheet.get_global_rect()
		left = minf(left, r.position.x)
		right = maxf(right, r.end.x)
		top = minf(top, r.position.y)
		bottom = maxf(bottom, r.end.y)
	if bottom > _main._windows.dock().get_global_rect().end.y + 0.5:
		_fail("%s's sheets end at %.0f, past the workspace's foot" % [id, bottom])
	var gap := float(UiTheme.GAP_PANE)
	if absf(left - header.position.x) > 0.5 or absf(right - header.end.x) > 0.5:
		_fail("%s's sheets run %.0f to %.0f, off the header sheet's %.0f to %.0f" % [id, left, right, header.position.x, header.end.x])
	if absf(top - (header.end.y + gap)) > 0.5:
		_fail("%s's first sheet starts %.0f px under the header, not a gap (%.0f)" % [id, top - header.end.y, gap])


## The four cluster icons are read straight off disk and rasterised, bypassing
## the import system so a fresh clone works headless -- see icon.gd. If that
## ever breaks, the bar renders four unlabelled-looking buttons and nothing
## reports an error.
func _check_icons_load() -> void:
	const ICONS := "res://assets/icons/material/"
	for name in ["account_balance", "payments", "diversity_3", "public"]:
		var texture := Icon.load_icon(ICONS + name + ".svg", UiTheme.TEXT, 22)
		if texture == null:
			_fail("icon '%s' did not load -- is assets/icons/material committed?" % name)
			continue
		if texture.get_width() != 22:
			_fail("icon '%s' rasterised at %dpx, expected 22" % [name, texture.get_width()])
		# The tint is a fill written into the SVG, not a modulate: the glyph's
		# opaque pixels must come out the tint, not the SVG's default black.
		var tint := Color("#C0FFEE")
		var image := Icon.load_icon(ICONS + name + ".svg", tint, 22).get_image()
		var opaque := 0
		var off_tint := 0
		for y in image.get_height():
			for x in image.get_width():
				var px := image.get_pixel(x, y)
				if px.a > 0.95:
					opaque += 1
					if absf(px.r - tint.r) > 0.06 or absf(px.g - tint.g) > 0.06 or absf(px.b - tint.b) > 0.06:
						off_tint += 1
		if opaque == 0:
			_fail("icon '%s' rasterised with no opaque pixel at all" % name)
		elif off_tint > 0:
			_fail("icon '%s' has %d opaque pixels that are not the tint" % [name, off_tint])

	# The pending count is a STATUS tone (something waits on you), the attention
	# colour, and does NOT follow the played nation's accent: a nation whose accent
	# were gold would otherwise mark "pending" in its own identity. V5.1-c2.3: the
	# sidebar's count, where the action bar's glyph was.
	var host := Control.new()
	UiTheme.apply(host, Color("#2596FF"))
	var sidebar = _main._hud.sidebar
	sidebar.show_pending(["finances"])
	_check_three_floating_panes()
	var pill: Label = sidebar._pills["finances"]
	if not pill.visible:
		_fail("a pending budget did not show a count on Finances")
	# G3 S1 (the author's "Ambre pleine"): a solid amber pill, the figure in the sheet's dark,
	# at AA on it.
	var ground := pill.get_theme_stylebox("normal") as StyleBoxFlat
	if ground == null or ground.bg_color != UiTheme.WARN:
		_fail("the pending count does not sit on a solid amber pill")
	elif AccentRule.contrast(pill.get_theme_color("font_color"), ground.bg_color) < AccentRule.MIN_CONTRAST:
		_fail("the pending count's figure %s does not hold AA on the amber" % pill.get_theme_color("font_color").to_html(false))
	elif pill.get_theme_color("font_color") != UiTheme.SHEET:
		_fail("the pending count's figure is %s, not the sheet's dark" % pill.get_theme_color("font_color").to_html(false))
	sidebar.show_pending([])

	# The mood icon's WORRIED band sits between GOOD and BAD: a status tone, not the
	# nation's accent (which could be any hue), and the accent is still the odd one
	# out while this check runs.
	if MoodIcon._colour_for(Portrait.Emotion.WORRIED) != UiTheme.WARN:
		_fail("the WORRIED mood is not drawn in the attention tone")
	# Put the static accent back and free the stand-in: it must not outlive the check.
	UiTheme.apply(host)
	host.free()

	# And the sidebar is actually using them, not merely able to.
	for id in _main._hud.sidebar.entry_ids():
		if _main._hud.sidebar._entries[id].icon == null:
			_fail("the '%s' sidebar entry has no icon" % id)


## The point of the whole session: the player is a person, not a country.
func _check_portrait_names_the_player() -> void:
	var nation = _main._loader.nations[_main._state.player_nation_id]
	var text := _collect_text(_main._hud.portrait_card)

	var ns = _main._state.player()
	var leader_name: String = _main._loader.person_name(President.leader_id(ns))
	if not text.contains(leader_name):
		_fail("the portrait card does not name the leader '%s': %s" % [leader_name, text])
	if not text.contains(President.leader_title(ns)):
		_fail("the portrait card does not carry the leader's title '%s'" % President.leader_title(ns))
	if not text.contains(nation.nation_name):
		_fail("the portrait card does not name the nation '%s'" % nation.nation_name)


## The flag is data (data/nations/*.json's `flag` block) drawn by a layout
## string, never a colour table keyed by nation id -- docs/engine-decision.md
## Rule 1. Checked for every nation, not only the player's, because nine of them
## are only ever seen through the map and would otherwise go unverified until
## someone picked one.
func _check_flag_data_reaches_the_card() -> void:
	for id in _main._loader.nations.keys():
		var nation = _main._loader.nations[id]
		if nation.flag_bands.size() < 2:
			_fail("%s has fewer than two flag bands" % id)
		if not nation.flag_layout in ["vertical", "horizontal", "union", "cross"]:
			_fail("%s has an undrawable flag layout '%s'" % [id, nation.flag_layout])

	var flag = _main._hud.portrait_card._flag
	if flag == null:
		_fail("the portrait card has no flag")
		return
	var expected = _main._loader.nations[_main._state.player_nation_id]
	if flag._bands != expected.flag_bands:
		_fail("the portrait card's flag is not the player nation's")


## V5.3 (bar C): the clock is the horizon's, the strip draws the standing figures and
## only the chips that wait, approval and the vote are drawn elsewhere and keep their
## tips. What can fail silently: a reading drawn twice, a "- clear" taking a slot again,
## the approval's reason lost when it left the strip, the date without its weekday.
func _check_the_bar_after_the_rebuild() -> void:
	var hud = _main._hud
	if not hud.ribbon.is_ancestor_of(hud.clock_cluster):
		_fail("the clock cluster is not in the horizon (ribbon), where the bar rebuild put it")
	if hud.title_bar.is_ancestor_of(hud.clock_cluster):
		_fail("the clock cluster is still in the title bar")
	var bar = _main._top_bar
	for id in StripReadings.OFF_STRIP:
		if bar.figure_box(id).visible:
			_fail("'%s' is drawn on the strip; it lives on the portrait card / the horizon now" % id)
	for id in StripReadings.ON_STRIP:
		if not bar.figure_box(id).visible:
			_fail("the standing figure '%s' is not drawn on the strip" % id)
	for id in StripReadings.CHIPS:
		var r: Dictionary = StripReadings.read(id, _main._state, _main._loader)
		if bar.figure_box(id).visible == StripReadings.is_resting(r):
			_fail("the '%s' chip is %s while its reading says %s" % [id, "shown" if bar.figure_box(id).visible else "hidden",
				"resting" if StripReadings.is_resting(r) else "waiting"])
	# A clear desk takes no slot (gate H6): stated outright, not through the code's own predicate.
	if _main._state.player().event_queue.is_empty() and bar.figure_box("desk").visible:
		_fail("an empty desk still shows its '— clear' chip on the strip")
	# The date carries its weekday, in G3's full form (decision 4: "Tue 3 March 2026", no
	# capitals, no slashes); the hold line is the cluster's own.
	var date: String = hud.clock_cluster._date_label.text
	if not RegEx.create_from_string("^[A-Z][a-z]{2} \\d{1,2} [A-Z][a-z]+ \\d{4}$").search(date):
		_fail("the clock's date '%s' is not 'Tue 3 March 2026'" % date)
	# Approval's reason went with it: the portrait card's number answers a hover.
	var label: Label = hud.portrait_card._approval_label
	label.mouse_entered.emit()
	if not String(label.tooltip_text).contains(StripReadings.read("approval", _main._state, _main._loader)["lines"][0]["text"]):
		_fail("the portrait card's approval has no tip (it lost its reason when it left the strip): '%s'" % label.tooltip_text)
	if label.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_fail("the approval figure ignores the mouse; its tip can never show")


## Three surfaces show approval -- the portrait, the polling panel and the
## election screen -- and they must agree. A face reading the raw model while
## the polls read the noised figure would have the player's own expression
## disagreeing with their own poll. V3.7: the emoji face is gone and the
## portrait's own expression is the mood read, so the property survives with a
## new mechanism -- the card's emotion band must be derived from the same
## polled figure the label prints.
func _check_mood_reads_the_polled_figure() -> void:
	var card = _main._hud.portrait_card
	var shown: String = card._approval_label.text
	if not shown.ends_with("%"):
		_fail("the portrait's approval is not a percentage: '%s'" % shown)
		return
	var parsed := float(shown.trim_suffix("%"))
	if card._emotion != card._emotion_for(parsed):
		_fail("the face reads band %d while the number %s implies %d"
			% [card._emotion, shown, card._emotion_for(parsed)])

	# The neutral band must contain 50, or a government sitting at the neutral
	# point re-stages the bust every month on poll noise alone -- the emoji's
	# threshold property, carried over to the bands that replaced it.
	var neutral: int = card._emotion_for(50.0)
	if card._emotion_for(49.5) != neutral or card._emotion_for(50.5) != neutral:
		_fail("the neutral emotion band does not straddle 50")

	# And the bands must be four distinct faces, or the emotion axis is
	# decorative -- an axis that cannot express the range it names.
	var bands := {}
	for value in [58.0, 50.0, 40.0, 30.0]:
		bands[card._emotion_for(value)] = true
	if bands.size() != 4:
		_fail("approval bands collapse to %d distinct faces, expected 4" % bands.size())


## V5.1-0c. The author: "sometimes the president portrait changes" -- the face
## swapped with approval and nothing said it was a mood read. Now the face is one
## fixed portrait, and the mood is a small icon beside the number with a tooltip.
func _check_face_is_fixed_and_mood_is_an_icon() -> void:
	var card = _main._hud.portrait_card
	var ns = _main._state.player()
	var original: float = ns.overall_approval_pct
	var bust = card._bust
	if card._mood_icon == null:
		_fail("the portrait card has no mood icon")
		return
	var seen := {}
	for approval in [95.0, 5.0, 50.0]:
		ns.overall_approval_pct = approval
		card.refresh()
		if card._bust != bust:
			_fail("the portrait's face was swapped at approval %.0f -- the face must stay fixed" % approval)
		if card._mood_icon.emotion != card._emotion:
			_fail("the mood icon shows band %d while the card reads %d" % [card._mood_icon.emotion, card._emotion])
		if String(card._mood_icon.tooltip_text).is_empty():
			_fail("the mood icon says nothing at approval %.0f" % approval)
		seen[card._mood_icon.emotion] = true
	if seen.size() != 3:
		_fail("three approvals drew %d distinct moods, want 3" % seen.size())
	ns.overall_approval_pct = original
	card.refresh()


## The inbox's own API, and its lanes -- V5.1-c3.1, U5a's card column docked
## right behind the same calls.
func _check_inbox() -> void:
	var stack = _main._hud.inbox
	stack.clear()

	var id: String = stack.push("Missile shortage", "The defence minister wants a word.")
	if stack.card_count() != 1:
		_fail("push() did not add a card")
	if not _collect_text(stack).contains("MISSILE SHORTAGE"):
		_fail("the pushed card does not show its title")
	stack.dismiss(id)
	if stack.card_count() != 0:
		_fail("dismiss() did not remove the card")
	stack.clear()


## A row's lane is what it asks of the player: answers, or a protected plain row,
## are DECISIONS; a named lane is honoured; the rest are NOTES.
func _check_lanes_by_kind() -> void:
	var stack = _main._hud.inbox
	stack.clear()
	var answer: String = stack.push("A choice", "body", [{"label": "Yes"}])
	var kept: String = stack.push("The programme", "body", [], null, true)
	var asked: String = stack.push("An audience", "body", [], null, false, Inbox.REQUESTS)
	var note: String = stack.push("A note", "body")
	if stack.lane_of(answer) != Inbox.DECISIONS or stack.lane_of(kept) != Inbox.DECISIONS:
		_fail("an answerable or protected row is not a decision (%s, %s)" % [stack.lane_of(answer), stack.lane_of(kept)])
	if stack.lane_of(asked) != Inbox.REQUESTS:
		_fail("a row pushed to REQUESTS sits in '%s'" % stack.lane_of(asked))
	if stack.lane_of(note) != Inbox.NOTES:
		_fail("a plain row sits in '%s', not NOTES" % stack.lane_of(note))
	stack.clear()


## The cap is the NOTES lane's alone: five decisions and sixty notes leave five
## decisions and the forty newest notes. An evicted question would read as
## dismissed and restart a held clock (Pass 16).
func _check_decisions_are_never_evicted() -> void:
	var stack = _main._hud.inbox
	stack.clear()
	var dismissed: Array = []
	var watch := func(id: String): dismissed.append(id)
	stack.card_dismissed.connect(watch)
	var decisions: Array = []
	for i in 5:
		decisions.append(stack.push("Decision %d" % i, "body", [{"label": "Yes"}]))
	var first_note: String = stack.push("Note 0", "body")
	for i in range(1, 60):
		stack.push("Note %d" % i, "body")
	stack.card_dismissed.disconnect(watch)
	if stack.lane_count(Inbox.DECISIONS) != 5:
		_fail("%d decisions survive five decisions and sixty notes, want 5" % stack.lane_count(Inbox.DECISIONS))
	if stack.lane_count(Inbox.NOTES) != Inbox.NOTES_MAX:
		_fail("%d notes survive sixty, want %d" % [stack.lane_count(Inbox.NOTES), Inbox.NOTES_MAX])
	for d in decisions:
		if dismissed.has(d):
			_fail("the notes' cap evicted decision %s" % d)
	if not dismissed.has(first_note):
		_fail("the oldest note was not the first to go")
	stack.clear()


## QA #45's fit take: a long answer wraps inside the inbox's width instead of
## widening it (U5a's unwrapped row reached ~705 px in English, ~1075 in French).
func _check_choice_row_wraps() -> void:
	var stack = _main._hud.inbox
	stack.clear()
	var long := "Answer with a sentence long enough to need a second line in the dock"
	stack.push("A choice", "body", [{"label": long}, {"label": long}, {"label": long}])
	if stack.get_combined_minimum_size().x > Inbox.WIDTH + 0.5:
		_fail("three %d-character answers widen the inbox to %.0f px of %d" % [long.length(), stack.get_combined_minimum_size().x, Inbox.WIDTH])
	stack.clear()


## V5.2's lane (C9) is in place before its rows: empty, it says so.
func _check_requests_lane_empty_state() -> void:
	var stack = _main._hud.inbox
	stack.clear()
	var empty: Label = stack._empty[Inbox.REQUESTS]
	if not empty.visible or empty.text.is_empty():
		_fail("an empty REQUESTS lane shows no empty state")
	var id: String = stack.push("An audience", "body", [], null, false, Inbox.REQUESTS)
	if empty.visible:
		_fail("the REQUESTS lane kept its empty state with a row in it")
	stack.dismiss(id)
	if not empty.visible:
		_fail("the REQUESTS lane emptied and did not say so")


## B4's machine: a standing card whose content ages must be rewritable in
## place -- and an unknown or evicted id must be a silent no-op, because the
## caller that tracked a card cannot tell eviction from survival.
func _check_set_body() -> void:
	var stack = _main._hud.inbox
	stack.clear()

	var id: String = stack.push("Your term", "You hold France until some month -- 16 months. Win the vote.")
	stack.set_body(id, "You hold France until some month -- 15 months. Win the vote.")
	var text := _collect_text(stack)
	if not text.contains("15 months"):
		_fail("set_body did not rewrite the card's body: '%s'" % text)
	if not text.contains("YOUR TERM"):
		_fail("set_body disturbed the card's title: '%s'" % text)
	if stack.card_count() != 1:
		_fail("set_body changed the card count to %d" % stack.card_count())

	# An id nothing pushed: no crash, no card, no residue.
	stack.set_body("card_99999", "ghost text")
	if stack.card_count() != 1:
		_fail("set_body on an unknown id changed the card count")
	if _collect_text(stack).contains("ghost text"):
		_fail("set_body on an unknown id materialised a card")

	# An id the notes' cap has dropped: no-op, and no resurrection.
	stack.clear()
	var first: String = stack.push("First", "first body")
	for i in range(Inbox.NOTES_MAX):
		stack.push("Filler %d" % i, "body")
	stack.set_body(first, "resurrected text")
	if _collect_text(stack).contains("resurrected text"):
		_fail("set_body wrote through an evicted card's id")
	if stack.card_count() != Inbox.NOTES_MAX:
		_fail("set_body on an evicted id changed the card count to %d" % stack.card_count())

	stack.clear()


## U5b puts the minimap here. The slot is held open at its final size now so
## that session adds a map and moves nothing else.
## V1.3f. The nine act, and the player has to be able to SEE it.
##
## Exactly the silent failure this file exists for: `_card_foreign_acts()` filters
## by the player's stake in the actor, and a filter that is one constant away from
## rejecting everything leaves a column that is empty forever with nothing erroring
## anywhere. The headless suite cannot see an empty column and neither can a green
## test that only checks push() works.
##
## Three things, and the middle one is the whole point of the filter:
##   - an act AIMED AT the player always cards, whatever the stake
##   - an act between two other nations cards only if the player has a stake
##   - the player's own acts never card, because they issued them
## V2.9: the decision card carries the choices as buttons, so answering is one
## click where the news is instead of a route through Dispatches. A card pushed
## with no actions renders none -- every existing caller is unchanged.
func _check_card_is_an_answer_surface() -> void:
	var stack = _main._hud.inbox
	stack.clear()

	var seen: Array = []
	stack.card_action.connect(func(id: String, index: int): seen.append([id, index]))

	var id: String = stack.push("Procurement files", "Two bids. Answer now.", [
		{"label": "Defence to command"},
		{"label": "Civilian oversight"},
	])
	# The card's own dismiss X is a button too; count only the action row.
	var buttons: Array = []
	for card in stack.get_children():
		for b in card.find_children("*", "Button", true, false):
			if b.text in ["Defence to command", "Civilian oversight"]:
				buttons.append(b)
	if buttons.size() != 2:
		_fail("a card with two choices rendered %d action buttons" % buttons.size())
		return
	buttons[0].pressed.emit()
	if seen.is_empty() or seen[0][0] != id or seen[0][1] != 0:
		_fail("pressing a card button did not emit card_action(id, 0): %s" % [seen])
		return

	stack.clear()
	stack.push("No actions here", "Plain card.")
	for card in stack.get_children():
		for b in card.find_children("*", "Button", true, false):
			# The NOTES lane's own Clear all (G9) and News line (rework 2 S2) are the lane's, not a card's.
			if b.text != "X" and b.name != "ClearNotes" and b.name != "NewsLine":
				_fail("a card with no actions rendered an extra button '%s'" % b.text)
	stack.clear()


func _check_foreign_acts_reach_the_column() -> void:
	var stack = _main._hud.inbox
	var state = _main._state
	if stack == null or state == null:
		_fail("no message stack or no state to card foreign acts into")
		return

	var player_id: String = state.player_nation_id
	var other := ""
	var third := ""
	for id in state.nations.keys():
		if String(id) == player_id:
			continue
		if other == "":
			other = String(id)
		elif third == "":
			third = String(id)

	stack.clear()
	state.foreign_acts.clear()
	state.foreign_acts.push_front({
		"year": state.year, "month": state.month,
		"actor_id": other, "target_id": player_id,
		"action_id": "state_visit", "action_name": "State Visit", "reason": "interest",
	})
	_main._world_news.card_foreign_acts(state.year, state.month)
	if stack.card_count() != 1:
		_fail("an act aimed at the player produced %d cards, not 1" % stack.card_count())
		return

	# And it must NAME the player as the one acted on, or the column says something
	# happened without saying it happened to you.
	# Case-insensitive: inbox.push() upper-cases the title.
	var text := _collect_text(stack).to_lower()
	if not text.contains("you"):
		_fail("a card for an act aimed at the player does not say so: '%s'" % text)

	# The model computes a reason for every act and this card is its ONLY reader.
	# An unread reason key is V1.3b's `refused_by_partner`, which shipped and was
	# silent for two whole sessions before V1.3e found it.
	if not text.contains("interests"):
		_fail("the act's reason key never reached the card: '%s'" % text)

	# The player's own act is not news to the player.
	stack.clear()
	state.foreign_acts.clear()
	state.foreign_acts.push_front({
		"year": state.year, "month": state.month,
		"actor_id": player_id, "target_id": other,
		"action_id": "state_visit", "action_name": "State Visit", "reason": "interest",
	})
	_main._world_news.card_foreign_acts(state.year, state.month)
	if stack.card_count() != 0:
		_fail("the player's own act was carded back at them (%d cards)" % stack.card_count())

	# V2.9 (from the playtest): four allies state-visiting in one month is ONE
	# piece of news -- five near-identical cards pushed decisions off a six-slot
	# column. One card per action per month, naming the actors.
	stack.clear()
	state.foreign_acts.clear()
	var visitors: Array[String] = []
	for id in state.nations.keys():
		if String(id) != player_id and visitors.size() < 4:
			visitors.append(String(id))
	for actor in visitors:
		state.foreign_acts.push_front({
			"year": state.year, "month": state.month,
			"actor_id": actor, "target_id": player_id,
			"action_id": "state_visit", "action_name": "State Visit", "reason": "interest",
		})
	_main._world_news.card_foreign_acts(state.year, state.month)
	if stack.card_count() != 1:
		_fail("four same-action visits produced %d cards, not 1" % stack.card_count())
		return
	var grouped := _collect_text(stack)
	var name_a: String = _main._loader.nation_name(visitors[0])
	var name_b: String = _main._loader.nation_name(visitors[1])
	if not grouped.contains(name_a) or not grouped.contains(name_b):
		_fail("the grouped visit card does not name its actors (%s, %s): '%s'" % [name_a, name_b, grouped])

	# A stale act -- one from a month already gone -- must not re-card on a later
	# tick, or every month replays the whole record.
	stack.clear()
	state.foreign_acts.clear()
	state.foreign_acts.push_front({
		"year": state.year - 1, "month": state.month,
		"actor_id": other, "target_id": third,
		"action_id": "state_visit", "action_name": "State Visit", "reason": "interest",
	})
	_main._world_news.card_foreign_acts(state.year, state.month)
	if stack.card_count() != 0:
		_fail("an act from a previous month was carded again (%d cards)" % stack.card_count())

	stack.clear()
	state.foreign_acts.clear()


## V5.1-0c. The author: "notification push the UI down". The message column sat in
## the HUD's own layout, so a column of tall cards raised the whole HUD's minimum
## height and the lower band (portrait, action bar, clock) was shoved off the
## bottom. The column is an overlay now: whatever it holds, the furniture stays
## where it was.
var _portrait_y_before := 0.0
var _bar_y_before := 0.0


func _stage_tall_cards() -> void:
	var hud = _main._hud
	_portrait_y_before = hud.portrait_card.global_position.y
	_bar_y_before = hud.ribbon.global_position.y
	hud.inbox.clear()
	var essay := "A long notification body that keeps going. ".repeat(14)
	for n in 6:
		hud.inbox.push("Tall card %d" % n, essay, [{"label": "Answer"}])


func _check_cards_do_not_push_the_ui_down() -> void:
	var hud = _main._hud
	if hud.inbox.card_count() != 6:
		_fail("the tall-card fixture holds %d cards, want 6" % hud.inbox.card_count())
	if absf(hud.portrait_card.global_position.y - _portrait_y_before) > 0.5:
		_fail("six tall cards moved the portrait card from y=%.1f to y=%.1f" % [
			_portrait_y_before, hud.portrait_card.global_position.y])
	if absf(hud.ribbon.global_position.y - _bar_y_before) > 0.5:
		_fail("six tall cards moved the day ribbon from y=%.1f to y=%.1f" % [
			_bar_y_before, hud.ribbon.global_position.y])
	if hud.inbox.get_parent() is BoxContainer:
		_fail("the message column is still in a box container -- its height is layout again")
	hud.inbox.clear()


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:  # V5.1-c: the inbox body is a rich line
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


## G3 S1: the chrome is THREE floating glass panes -- the sidebar, ONE top strip (the figures and the
## title bar's tools in one row) and the time bar -- each GAP_PANE from the screen's edges and from each
## other. A pane that went back to flush, or a fourth pane, is the BUREAU board again.
func _check_three_floating_panes() -> void:
	var hud = _main._hud
	var view: Vector2 = _main.get_viewport().get_visible_rect().size
	var gap := float(UiTheme.GAP_PANE)
	for chrome in [hud.sidebar, hud.top_bar, hud.ribbon]:
		if (chrome as Control).theme_type_variation != UiTheme.PANE:
			_fail("%s wears '%s', not the floating glass pane" % [(chrome as Node).name, (chrome as Control).theme_type_variation])
	if not hud.top_bar.is_ancestor_of(hud.title_bar):
		_fail("the title bar's tools are not in the top strip's pane")
	if hud.title_bar is PanelContainer:
		_fail("the title bar is still a pane of its own")
	var side: Rect2 = hud.sidebar.get_global_rect()
	var strip: Rect2 = hud.top_bar.get_global_rect()
	var bar: Rect2 = hud.ribbon.get_global_rect()
	if not side.position.is_equal_approx(Vector2(gap, gap)):
		_fail("the sidebar's pane is at %s, not a gap from the corner" % str(side.position))
	if not is_equal_approx(strip.position.x, side.end.x + gap) or not is_equal_approx(strip.position.y, gap):
		_fail("the top strip is at %s, not a gap right of the sidebar and under the top edge" % str(strip.position))
	if not is_equal_approx(strip.end.x, view.x - gap):
		_fail("the top strip ends at %.0f, not a gap short of %.0f" % [strip.end.x, view.x])
	if not is_equal_approx(bar.position.x, gap) or not is_equal_approx(bar.end.x, view.x - gap) or not is_equal_approx(bar.end.y, view.y - gap):
		_fail("the time bar is %s, not the screen's width less two gaps, a gap off the bottom" % str(bar))
	if not is_equal_approx(bar.position.y, side.end.y + gap):
		_fail("the sidebar ends at %.0f and the time bar starts at %.0f: not a gap apart" % [side.end.y, bar.position.y])
	# The open domain's row: a control's ground and the accent bar left of it, in the pane's
	# padding -- the accent's one mark in the sidebar (G3 spec section 2).
	hud.sidebar.select("finances")
	var accent_bar: ColorRect = hud.sidebar.open_bar()
	if accent_bar == null or accent_bar.get_parent() != hud.sidebar._entries["finances"] or accent_bar.color != UiTheme.accent():
		_fail("the open Finances row carries no accent bar")
	elif accent_bar.offset_right > 0.0 or accent_bar.offset_right - accent_bar.offset_left < 4.0:
		_fail("the open row's accent bar is not a 4 px bar left of the row")
	if hud.sidebar._entries["finances"].theme_type_variation != UiTheme.SIDEBAR_ROW:
		_fail("a sidebar entry is not a SIDEBAR_ROW")
	# The bar moves with the open domain: one bar, on the new row, none left on the old one.
	hud.sidebar.select("economy")
	for id in ["finances", "economy"]:
		var bars: int = (hud.sidebar._entries[id] as Node).get_children().filter(func(c): return c is ColorRect and not c.is_queued_for_deletion()).size()
		if bars != (1 if id == "economy" else 0):
			_fail("after opening Economy the %s row carries %d accent bars" % [id, bars])
	hud.sidebar.select("")
	if hud.sidebar.open_bar() != null:
		_fail("the accent bar stayed with nothing open")
	# Design's gate E1 on #439: one sheet per page, no tile-coloured slab inside it; the Diary,
	# which lays out its own sheets, has no page sheet behind them.
	if _main._windows.content("finances").theme_type_variation != UiTheme.BARE:
		_fail("the Finances panel's root draws its own ground on its page: '%s'" % _main._windows.content("finances").theme_type_variation)
	# G3 S4: Books lays out its own two sheets (the sentence, the table), so its page draws none; Public works,
	# not re-laid yet, is still one sheet.
	if not _main._windows.frame("finances").own_sheets() or _main._windows.frame("finances").theme_type_variation != UiTheme.BARE:
		_fail("the Books page draws a sheet behind its own sheets")
	if _main._windows.frame("projects").theme_type_variation != UiTheme.PLATE:
		_fail("the Public works page is not one sheet")
	if not _main._windows.frame("calendar").own_sheets() or _main._windows.frame("calendar").theme_type_variation != UiTheme.BARE:
		_fail("the Diary's page draws a sheet behind its own sheets")
	# A scene's header has no tabs, so no segmented ground either (#439 pass 2 T5: an empty 6x6
	# tile square beside the title).
	_main._windows._show_domain_of("audience")
	for node in _main._windows._tab_slot.find_children("*", "PanelContainer", true, false):
		if not node.is_queued_for_deletion():
			_fail("a scene's header draws a tab ground with no tab on it")
	_main._windows._show_domain_of("finances")
	if _main._windows.tab_buttons().is_empty():
		_fail("premise: Finances has no tabs in its header")
	# While the inbox shows over a tab, the workspace ends a gap short of it: nothing under it.
	if hud.inbox.visible:
		_main._windows.open("finances")
		var dock: Rect2 = _main._windows.dock().get_global_rect()
		if dock.end.x > hud.inbox.get_global_rect().position.x - gap + 0.5:
			_fail("with the inbox up the workspace ends at %.0f, under the inbox at %.0f" % [dock.end.x, hud.inbox.get_global_rect().position.x])
		_main._windows.close_all()
	else:
		_fail("premise: the inbox is not shown on the map")
	var inbox: Rect2 = hud.inbox.get_global_rect()
	if hud.inbox.visible and not is_equal_approx(inbox.end.x, view.x - gap):
		_fail("the inbox ends at %.0f, not a gap short of the screen's edge" % inbox.end.x)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_hud: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
