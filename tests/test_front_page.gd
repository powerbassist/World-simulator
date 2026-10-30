extends SceneTree

## Headless test: godot --headless --script res://tests/test_front_page.gd
## Non-zero exit on any failure.
##
## V5.2 d, the front pages (docs/design/v5.2-d-spec.md section 4, bands D8 and D9's
## display half). Over a hand-fed `front_page` entry -- the sim's trigger is
## Systems', and the card must not wait for it -- and hand-fed headline tables, as
## Content's file is not on main yet:
##   - two papers: each its masthead, its side in words and its headline, the
##     variables filled; "also on the front page" capped at two;
##   - a missing headline drops that line and never prints a key or a {{variable}};
##     an entry with none written shows no card at all;
##   - D8: one card at a time, the one it replaces kept as a note in the inbox; the
##     card never holds the clock (no pause, no hold reason, not on the screen
##     stack) and puts itself away after LIFE_SECONDS of RUNNING clock only;
##   - Close is a real click, press and release frames apart (tests/click.gd);
##   - the parent's call (2026-10-30): a month with an election result hands the card
##     the count's plate, and the card waits for that plate's `dismissed` -- no paper
##     prints the result while the count declares it; a load drops a held card.

const FrontPage = preload("res://src/ui/front_page.gd")
const Headlines = preload("res://src/ui/headlines.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const Click = preload("res://tests/click.gd")


## The card only reads `paused`: a clock that cannot tick, so the test runs no month.
class StillClock:
	var paused := false


## The election result's plate, as the card sees it: its one signal.
class CountPlate extends Control:
	signal dismissed


var _failures: Array[String] = []
var _main
var _card
var _frame := 0
var _outlets: Array = []
var _president := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_card = _main._hud.front_page
			if _card == null:
				_fail("the HUD has no front page")
				_finish()
				return true
			_main._hud.inbox.clear()
			_setup()
			_check_two_papers()
			_check_missing()
			_check_one_at_a_time()
			_check_never_holds()
			_check_life()
			_check_held_for_count()
			_check_held_through_main()
			_show_full()
		5:
			Click.half(root, _card.find_child("Close", true, false), true)
		8:
			Click.half(root, _card.find_child("Close", true, false), false)
		10:
			if _card.visible:
				_fail("Close (a real click) did not put the card away")
			_finish()
			return true
	return false


func _setup() -> void:
	var nation_id := String(_main._state.player_nation_id)
	_outlets = _main._loader.outlets.get(nation_id, [])
	if _outlets.size() < 2:
		_fail("%s has fewer than two outlets; the test needs two" % nation_id)
	var ns = _main._state.player()
	_president = _main._loader.person_name(String(ns.head_of_state_person_id if ns.has_executive else ns.pm_person_id))
	Headlines.set_table("event", {
		"ev_x": {"ans": {
			"friendly": "{{president}} keeps the lights on",
			"hostile": "{{president}} leaves {{nation}} in the dark",
			"neutral": "{{minister}} quits over the blackout",
		}},
		"ev_y": {"a": {"neutral": "Second story of the month"}},
		"ev_z": {"a": {"hostile": "Third story of the month"}},
		"ev_w": {"a": {"hostile": "Fourth story of the month"}},
		"ev_p": {"a": {"friendly": "{{party}} carries the day"}},
	})
	Headlines.set_table("moment", {})


func _entry(papers: Array, also: Array = []) -> Dictionary:
	return {"kind": "event", "id": "ev_x", "answer": "ans", "severity": 3, "papers": papers, "also": also}


func _paper(i: int, tone: String) -> Dictionary:
	return {"outlet": String(_outlets[i].id), "tone": tone}


func _show(entry: Dictionary, clock = null) -> bool:
	return _card.show_entry(entry, _main._state, _main._loader, clock if clock != null else StillClock.new())


func _show_full(clock = null) -> bool:
	var also := [
		{"kind": "event", "id": "ev_y", "answer": "a", "outlet": String(_outlets[0].id), "tone": "neutral"},
		{"kind": "event", "id": "ev_z", "answer": "a", "outlet": String(_outlets[1].id), "tone": "hostile"},
		{"kind": "event", "id": "ev_w", "answer": "a", "outlet": String(_outlets[1].id), "tone": "hostile"},
	]
	return _show(_entry([_paper(0, "friendly"), _paper(1, "hostile")], also), clock)


func _check_two_papers() -> void:
	if not _show_full() or not _card.visible:
		_fail("a front page with two written headlines did not show")
		return
	var first: String = _texts(_card.find_child("Paper0", true, false))
	var second: String = _texts(_card.find_child("Paper1", true, false))
	if not first.contains(String(_outlets[0].outlet_name).to_upper()) or not first.contains("Close to the government"):
		_fail("the first paper lacks its masthead or its side: '%s'" % first)
	if not first.contains("%s keeps the lights on" % _president):
		_fail("the first paper's headline is not filled: '%s'" % first)
	if not second.contains(String(_outlets[1].outlet_name).to_upper()) or not second.contains("Opposed to the government"):
		_fail("the second paper lacks its masthead or its side: '%s'" % second)
	if not second.contains(String(_main._loader.nation_name(String(_main._state.player_nation_id)))):
		_fail("{{nation}} was not filled: '%s'" % second)
	var all := _texts(_card)
	if not all.contains("Second story") or not all.contains("Third story"):
		_fail("the two runners-up are not on the card: '%s'" % all)
	if all.contains("Fourth story"):
		_fail("a third runner-up was shown; the cap is %d" % FrontPage.ALSO_MAX)


func _check_missing() -> void:
	# The neutral cell names a variable nobody fills; "moderate" is no tone at all.
	_show(_entry([_paper(0, "neutral"), _paper(1, "hostile"), _paper(0, "moderate")]))
	if _card.find_child("Paper1", true, false) != null:
		_fail("a paper whose headline is missing or unfilled was shown")
	var all := _texts(_card)
	for key in ["{{", "ev_x", "moderate", "minister"]:
		if all.contains(key):
			_fail("the card prints '%s', a key or a variable: '%s'" % [key, all])
	_card.dismiss()
	if _show(_entry([_paper(0, "neutral")])) or _card.visible:
		_fail("an entry with no written headline showed a card")
	if _show({}) or _card.visible:
		_fail("an empty entry showed a card")
	# A shape the card does not read (an id where a Dictionary goes) is skipped.
	if _show(_entry([String(_outlets[0].id), _paper(1, "hostile")])) == false:
		_fail("a malformed paper beside a good one stopped the card")
	# An empty month, or one with nothing written, leaves the card being read up:
	# once wired, the month report hands an empty entry most months.
	_show_full()
	if _show({}) or _show(_entry([_paper(0, "neutral")])) or not _card.visible:
		_fail("a month with no front page put away the card still up")
	_card.dismiss()
	# A variable with no value (no incumbent party) drops its headline, not a hole.
	var ns = _main._state.player()
	var party: String = ns.incumbent_party_id
	ns.incumbent_party_id = ""
	var shown: bool = _show({"kind": "event", "id": "ev_p", "answer": "a", "papers": [_paper(0, "friendly")]})
	ns.incumbent_party_id = party
	if shown or _texts(_card).contains(" carries the day"):
		_fail("a headline whose {{party}} has no value was shown with a hole")
	_card.dismiss()


func _check_one_at_a_time() -> void:
	_main._hud.inbox.clear()
	_show_full()
	_show(_entry([_paper(1, "hostile")]))
	if _count_cards(_main) != 1:
		_fail("%d front-page cards are up, not one" % _count_cards(_main))
	if _main._hud.inbox.lane_count(Inbox.NOTES) != 1:
		_fail("the replaced front page was not kept as one note (%d notes)" % _main._hud.inbox.lane_count(Inbox.NOTES))
	_card.dismiss()


func _check_never_holds() -> void:
	var clock = _main._clock
	for paused in [false, true]:
		clock.paused = paused
		var reason := HoldReason.show(_main)
		_show_full(clock)
		if clock.paused != paused:
			_fail("showing a front page moved the clock (paused %s -> %s)" % [paused, clock.paused])
		if HoldReason.show(_main) != reason:
			_fail("showing a front page gave the clock a hold reason")
		_card.dismiss()
	clock.paused = true
	var stack = get_first_node_in_group(ScreenStack.GROUP)
	if stack != null and stack.is_ancestor_of(_card):
		_fail("the front page sits on the screen stack, which ranks what holds the screen")


func _check_life() -> void:
	# The pointer off the card, so only the clock decides.
	root.warp_mouse(Vector2(1, root.get_visible_rect().size.y - 1))
	var clock := StillClock.new()
	clock.paused = true
	_show_full()
	_card._clock = clock
	_card.advance(FrontPage.LIFE_SECONDS * 4.0)
	if not _card.visible:
		_fail("the card aged while the clock was paused")
	clock.paused = false
	_card.advance(FrontPage.LIFE_SECONDS * 0.5)
	if not _card.visible:
		_fail("the card left before LIFE_SECONDS of running clock")
	# An identical note joins the one before it (R13), so count from an empty lane.
	_main._hud.inbox.clear()
	_card.advance(FrontPage.LIFE_SECONDS)
	if _card.visible:
		_fail("the card did not put itself away after LIFE_SECONDS of running clock")
	if _main._hud.inbox.lane_count(Inbox.NOTES) != 1:
		_fail("the card put itself away without leaving its note")


func _check_held_for_count() -> void:
	_card.clear()
	var entry := _entry([_paper(0, "friendly"), _paper(1, "hostile")])
	var plate := CountPlate.new()
	if _card.show_entry(entry, _main._state, _main._loader, StillClock.new(), plate) or _card.visible:
		_fail("a front page showed while the election count's plate was up")
	plate.dismissed.emit()
	if not _card.visible:
		_fail("the held front page did not show once the count's plate was dismissed")
	_card.clear()
	_card.show_entry(entry, _main._state, _main._loader, StillClock.new(), plate)
	_card.clear()
	plate.dismissed.emit()
	if _card.visible:
		_fail("a load's clear() did not drop the front page held for the count")
	plate.free()


## QA's TAKE 1 on #207: through main's own Elections hook, the month's front page
## waits for the REAL result plate, and shows on its dismissal.
func _check_held_through_main() -> void:
	_card.clear()
	var entry := _entry([_paper(0, "friendly"), _paper(1, "hostile")])
	var report := {"election_results": [{"kind": "national"}], "front_page": entry}
	_main._on_month_step("Elections", true, report, int(_main._state.year), int(_main._state.month))
	if _card.visible:
		_fail("main's Elections hook showed the front page over the election count")
	_main._election_panel.dismissed.emit()
	if not _card.visible:
		_fail("main's held front page did not show once the result plate was dismissed")
	_card.clear()
	_main._clock.paused = true


func _count_cards(node: Node) -> int:
	var n := 1 if node.get_script() == FrontPage and node.visible else 0
	for child in node.get_children():
		n += _count_cards(child)
	return n


func _texts(node: Node) -> String:
	if node == null:
		return ""
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		if child is CanvasItem and not child.visible:
			continue
		out += _texts(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tests/test_front_page.gd")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		quit(1)
