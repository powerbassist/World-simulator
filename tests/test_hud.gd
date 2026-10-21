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
const Icon = preload("res://src/ui/icon.gd")
const MessageStack = preload("res://src/ui/message_stack.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")

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
	_check_face_is_fixed_and_mood_is_an_icon()
	_check_action_bar_subrow()
	_check_message_stack()
	_check_set_body()
	_check_card_is_an_answer_surface()
	_check_foreign_acts_reach_the_column()
	_check_minimap_slot_reserved()
	_stage_tall_cards()
	return false


func _later_frames() -> bool:
	if _frame < 5:
		return false  # a layout pass or two for the cards to take their height
	_check_cards_do_not_push_the_ui_down()
	_check_windows_open_clear_of_the_column()
	_finish()
	return false


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

	# And the bar is actually using them, not merely able to.
	for cluster_id in _main._hud.action_bar._cluster_buttons.keys():
		if _main._hud.action_bar._cluster_buttons[cluster_id].icon == null:
			_fail("the '%s' cluster has no icon" % cluster_id)


## The point of the whole session: the player is a person, not a country.
func _check_portrait_names_the_player() -> void:
	var nation = _main._loader.nations[_main._state.player_nation_id]
	var text := _collect_text(_main._hud.portrait_card)

	var leader_name: String = _main._loader.person_name(nation.leader_person_id)
	if not text.contains(leader_name):
		_fail("the portrait card does not name the leader '%s': %s" % [leader_name, text])
	if not text.contains(nation.leader_title):
		_fail("the portrait card does not carry the leader's title '%s'" % nation.leader_title)
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


func _check_action_bar_subrow() -> void:
	var bar = _main._hud.action_bar
	if bar.open_cluster() != "":
		_fail("a cluster is already open before anything is clicked")

	bar._toggle_cluster("economy")
	if bar.open_cluster() != "economy":
		_fail("opening the economy cluster did not record it as open")
	var labels := _collect_text(bar._subrow)
	for entry in ["ECONOMY", "BUDGET"]:
		if not labels.contains(entry):
			_fail("the economy sub-row has no '%s' entry: %s" % [entry, labels])

	# One drawer at a time, or the bar grows a row per cluster.
	bar._toggle_cluster("state")
	if bar.open_cluster() != "state":
		_fail("opening a second cluster did not replace the first")
	if _collect_text(bar._subrow).contains("BUDGET"):
		_fail("the previous cluster's entries are still in the sub-row")

	bar._toggle_cluster("state")
	if bar.open_cluster() != "":
		_fail("clicking the open cluster again did not close the drawer")


## Furniture only this session -- nothing calls push(). The API is tested anyway,
## because V1.8 is the session that will call it and the surface it finds should
## be one that already works.
func _check_message_stack() -> void:
	var stack = _main._hud.message_stack
	stack.clear()

	var id: String = stack.push("Missile shortage", "The defence minister wants a word.")
	if stack.card_count() != 1:
		_fail("push() did not add a card")
	if not _collect_text(stack).contains("MISSILE SHORTAGE"):
		_fail("the pushed card does not show its title")

	stack.dismiss(id)
	if stack.card_count() != 0:
		_fail("dismiss() did not remove the card")

	# The column runs into the portrait card past its cap, so the oldest is
	# dropped rather than the newest refused.
	for i in range(MessageStack.MAX_CARDS + 3):
		stack.push("Card %d" % i, "body")
	if stack.card_count() != MessageStack.MAX_CARDS:
		_fail("the stack holds %d cards, expected a cap of %d" % [stack.card_count(), MessageStack.MAX_CARDS])
	if _collect_text(stack).contains("CARD 0"):
		_fail("the stack dropped a newer card instead of the oldest")

	stack.clear()


## B4's machine: a standing card whose content ages must be rewritable in
## place -- and an unknown or evicted id must be a silent no-op, because the
## caller that tracked a card cannot tell eviction from survival.
func _check_set_body() -> void:
	var stack = _main._hud.message_stack
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

	# An id the MAX_CARDS eviction has dropped: no-op, and no resurrection.
	stack.clear()
	var first: String = stack.push("First", "first body")
	for i in range(MessageStack.MAX_CARDS + 1):
		stack.push("Filler %d" % i, "body")
	stack.set_body(first, "resurrected text")
	if _collect_text(stack).contains("resurrected text"):
		_fail("set_body wrote through an evicted card's id")
	if stack.card_count() != MessageStack.MAX_CARDS:
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
	var stack = _main._hud.message_stack
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
			if b.text != "X":
				_fail("a card with no actions rendered an extra button '%s'" % b.text)
	stack.clear()


func _check_foreign_acts_reach_the_column() -> void:
	var stack = _main._hud.message_stack
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
	_main._card_foreign_acts(state.year, state.month)
	if stack.card_count() != 1:
		_fail("an act aimed at the player produced %d cards, not 1" % stack.card_count())
		return

	# And it must NAME the player as the one acted on, or the column says something
	# happened without saying it happened to you.
	# Case-insensitive: message_stack.push() upper-cases the title.
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
	_main._card_foreign_acts(state.year, state.month)
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
	_main._card_foreign_acts(state.year, state.month)
	if stack.card_count() != 1:
		_fail("four same-action visits produced %d cards, not 1" % stack.card_count())
		return
	var grouped := _collect_text(stack)
	var name_a: String = _main._nation_name(visitors[0])
	var name_b: String = _main._nation_name(visitors[1])
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
	_main._card_foreign_acts(state.year, state.month)
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
	_bar_y_before = hud.action_bar.global_position.y
	hud.message_stack.clear()
	var essay := "A long notification body that keeps going. ".repeat(14)
	for n in 6:
		hud.message_stack.push("Tall card %d" % n, essay, [{"label": "Answer"}])


func _check_cards_do_not_push_the_ui_down() -> void:
	var hud = _main._hud
	if hud.message_stack.card_count() != 6:
		_fail("the tall-card fixture holds %d cards, want 6" % hud.message_stack.card_count())
	if absf(hud.portrait_card.global_position.y - _portrait_y_before) > 0.5:
		_fail("six tall cards moved the portrait card from y=%.1f to y=%.1f" % [
			_portrait_y_before, hud.portrait_card.global_position.y])
	if absf(hud.action_bar.global_position.y - _bar_y_before) > 0.5:
		_fail("six tall cards moved the action bar from y=%.1f to y=%.1f" % [
			_bar_y_before, hud.action_bar.global_position.y])
	if hud.message_stack.get_parent() is BoxContainer:
		_fail("the message column is still in a box container -- its height is layout again")
	hud.message_stack.clear()


## Review pass 2. The column is above the windows (the HUD is drawn last), so a
## window that opened under it had its left edge -- the budget's levers -- covered
## until the cards were dismissed. A window now opens to the right of the column.
## A window as wide as the band is the case that matters: it is the one that
## reaches the left edge.
func _check_windows_open_clear_of_the_column() -> void:
	var wm := WindowManager.new()
	root.add_child(wm)
	wm.size = Vector2(1920, 1080)
	var content := Control.new()
	content.custom_minimum_size = Vector2(3000, 300)  # wider than any band: it fills it
	wm.register("wide", "Wide", content)
	wm.open("wide")
	var clear_x: float = float(MessageStack.CARD_WIDTH) + 14.0
	var x: float = wm.frame("wide").position.x
	if x < clear_x:
		_fail("a band-wide window opened at x=%.0f, under the message column (clear of it from x=%.0f)" % [x, clear_x])
	wm.queue_free()


func _check_minimap_slot_reserved() -> void:
	var cluster = _main._hud.clock_cluster
	if cluster._minimap_slot == null:
		_fail("the clock cluster reserves no minimap slot")
		return
	if cluster._minimap_slot.custom_minimum_size != cluster.MINIMAP_SIZE:
		_fail("the minimap slot is not held at its reserved size")


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


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
