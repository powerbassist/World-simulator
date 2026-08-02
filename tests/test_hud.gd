extends SceneTree

## Headless test: godot --headless --script res://tests/test_hud.gd
## Non-zero exit on any failure.
##
## U5a's furniture, where test_shell.gd covers its placement and its wiring.
## The split is by failure mode rather than by file: everything here is
## something that goes wrong **without erroring** -- an icon that silently does
## not load, a flag whose colours never arrive, a message column that grows
## until it runs off the screen. CLAUDE.md's rule that UI which can fail
## silently needs a test is the whole reason this file exists.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const MessageStack = preload("res://src/ui/message_stack.gd")

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

	_check_icons_load()
	_check_portrait_names_the_player()
	_check_flag_data_reaches_the_card()
	_check_mood_reads_the_polled_figure()
	_check_action_bar_subrow()
	_check_message_stack()
	_check_minimap_slot_reserved()
	_finish()
	return false


## The four cluster icons are read straight off disk and rasterised, bypassing
## the import system so a fresh clone works headless -- see icon.gd. If that
## ever breaks, the bar renders four unlabelled-looking buttons and nothing
## reports an error.
func _check_icons_load() -> void:
	const ICONS := "res://addons/at-icons/control/"
	for name in ["institutional_building", "coins", "human", "globe"]:
		var texture := Icon.load_icon(ICONS + name + ".svg", UiTheme.TEXT, 22)
		if texture == null:
			_fail("icon '%s' did not load -- is it committed? see .gitignore's at-icons exception" % name)
			continue
		if texture.get_width() != 22:
			_fail("icon '%s' rasterised at %dpx, expected 22" % [name, texture.get_width()])

	# And the bar is actually using them, not merely able to.
	for cluster_id in _main._hud.action_bar._cluster_buttons.keys():
		if _main._hud.action_bar._cluster_buttons[cluster_id].icon == null:
			_fail("the '%s' cluster has no icon" % cluster_id)


## The point of the whole session: the player is a person, not a country.
func _check_portrait_names_the_player() -> void:
	var nation = _main._loader.nations[_main._state.player_nation_id]
	var text := _collect_text(_main._hud.portrait_card)

	if not text.contains(nation.leader_name):
		_fail("the portrait card does not name the leader '%s': %s" % [nation.leader_name, text])
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
## disagreeing with their own poll.
func _check_mood_reads_the_polled_figure() -> void:
	var card = _main._hud.portrait_card
	var mood = card._mood
	if mood == null:
		_fail("the portrait card has no mood indicator")
		return

	var shown: String = card._approval_label.text
	if not shown.ends_with("%"):
		_fail("the portrait's approval is not a percentage: '%s'" % shown)
	var parsed := float(shown.trim_suffix("%"))
	if absf(parsed - mood._approval) > 0.51:
		_fail("the face reads %.1f while the number reads %s" % [mood._approval, shown])

	# The two thresholds must straddle the neutral point, or a government
	# sitting at 50 flickers between faces on poll noise alone.
	if mood.UNHAPPY_BELOW >= 50.0 or mood.HAPPY_ABOVE <= 50.0:
		_fail("the mood thresholds do not straddle 50")


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


## U5b puts the minimap here. The slot is held open at its final size now so
## that session adds a map and moves nothing else.
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
