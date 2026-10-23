extends SceneTree

## Headless test: godot --headless --script res://tests/test_orgs_panel.gd
## Non-zero exit on any failure.
##
## V4.5b2 T6. The council surface's silent failures: a press that reaches the
## sim but not the signal, a refusal that is written and then erased by the
## very refresh that should show it, a desk mark that keys on the wrong
## register, a figure that claims a Europe the nation is not part of. None of
## these errors anywhere, so a green suite says nothing about them without
## this file.
##
## Each scenario builds its own state and its own panel. The panel is added to
## the tree BEFORE setup() (AGENTS.md: a Control outside the tree is half-dead)
## and refreshed directly -- the body is rebuilt with queue_free(), so the
## text walks below skip nodes queued for deletion, or the OLD body would
## answer for the new one. Focus-like claims are scoped to the panel: a
## non-null check from the scene root passes on the menu's own button.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Council = preload("res://src/sim/council.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const Ratification = preload("res://src/sim/ratification.gd")
const Pending = preload("res://src/ui/pending.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const RK = preload("res://src/core/relations.gd")
const TermText = preload("res://src/ui/term_text.gd")

const PLAYER := "FRA"
const EU_ORG := "eu"
const PANEL_SCRIPT := "res://src/ui/orgs_panel.gd"
const TOP_BAR_SCRIPT := "res://src/ui/top_bar.gd"
const SPONSOR := "DEU"
const PROPOSAL := "recovery_facility"

var _failures: Array[String] = []
var _loader
var _frame := 0
var _live: Array = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the tree settle before any panel is built

	if _frame > 2:
		_run_frame_scenario()
		return false

	_check_sponsor_and_decision_lines()
	_check_a_bargain_reaches_the_sim()
	_check_a_refused_bargain_speaks()
	_check_a_refused_vote_speaks()
	_check_the_ratify_card()
	_check_the_desk_marks_a_treaty()
	_check_the_europe_figure()
	_check_a_waiting_council_lists_first()
	_start_frame_scenario()
	return false


# -- Fixtures -----------------------------------------------------------------

func _fresh():
	return GameState.new_game(_loader, PLAYER)


## A panel in the tree, THEN set up -- the order the gotcha demands.
func _panel_for(state) -> Control:
	var panel: Control = load(PANEL_SCRIPT).new()
	root.add_child(panel)
	panel.setup(state, _loader)
	_live.append(panel)
	return panel


func _drop(node: Node) -> void:
	node.queue_free()
	_live.erase(node)


## Open the proposal with its sponsor recorded, the way test_council's _open does.
func _stage_pending(state, vote := Orgs.VOTE_ABSTAIN) -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, PROPOSAL)
	state.orgs[EU_ORG]["pending"] = {
		"proposal_id": p.id, "name": p.proposal_name, "summary": p.summary,
		"months_left": 2, "player_vote": vote, "sponsor": SPONSOR,
		"opened_year": state.year, "opened_month": state.month,
	}


func _stage_ratifying(state, months_left := 4) -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, PROPOSAL)
	state.orgs[EU_ORG]["ratifying"] = {
		"proposal_id": p.id, "name": p.proposal_name, "sponsor": SPONSOR,
		"months_left": months_left, "nations": {PLAYER: CouncilK.RATIFY_PENDING},
	}


func _refresh(panel) -> void:
	panel.mark_dirty()
	panel._refresh()


## Text of every live Label/Button under `node`. Skips nodes queued for deletion:
## the previous refresh's body is still in the tree until the frame ends.
func _text(node: Node) -> String:
	var out := ""
	if node.is_queued_for_deletion():
		return out
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _buttons(node: Node, out: Array = []) -> Array:
	if node.is_queued_for_deletion():
		return out
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_buttons(child, out)
	return out


func _button_named(panel: Node, label: String) -> Button:
	for b in _buttons(panel):
		if (b as Button).text == label:
			return b
	return null


## The three currency buttons under `nation_name`'s row of the table.
func _member_buttons(panel: Node, nation_name: String) -> Array:
	var labels: Array = []
	_collect_labels(panel, labels)
	for label in labels:
		if (label as Label).text.begins_with(nation_name + " — leans"):
			var siblings: Array = label.get_parent().get_children()
			var next: Node = siblings[siblings.find(label) + 1]
			return _buttons(next)
	return []


func _collect_labels(node: Node, out: Array) -> void:
	if node.is_queued_for_deletion():
		return
	if node is Label:
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)


## The first member the table lists (it shows only MAX_ROWS of the council, nearest
## the threshold first), so the target is one whose buttons actually exist.
func _listed_target(panel: Node, state) -> String:
	var labels: Array = []
	_collect_labels(panel, labels)
	for label in labels:
		var text: String = (label as Label).text
		if not text.contains(" — leans"):
			continue
		for id in Orgs.members(state, EU_ORG):
			if text.begins_with(_loader.nation_name(String(id)) + " — leans"):
				return String(id)
	return ""


func _term_ids(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node.get_script() == TermText:
		out.append_array(TermText.term_ids(node))
	for child in node.get_children():
		out.append_array(_term_ids(child))
	return out


# -- Checks -------------------------------------------------------------------

## The sponsor line and the decision line reach the screen, for BOTH decision
## classes: the proposal's class is overridden in turn and restored, since the
## shipped one only ever shows one of the two sentences.
func _check_sponsor_and_decision_lines() -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, PROPOSAL)
	var kept: String = p.decision
	for rule in [CouncilK.DECISION_UNANIMITY, CouncilK.DECISION_QMR]:
		p.decision = rule
		var state = _fresh()
		_stage_pending(state)
		var panel := _panel_for(state)
		_refresh(panel)
		var text := _text(panel)

		if not text.contains("Sponsored by %s" % _loader.nation_name(SPONSOR)):
			_fail("the pending proposal's sponsor line is missing: %s" % text)
		var treaty_line := text.contains("A treaty: one veto kills it")
		var qmr_line := text.contains("Qualified majority:")
		if rule == CouncilK.DECISION_UNANIMITY and (not treaty_line or qmr_line):
			_fail("a unanimity proposal does not read as a treaty alone")
		if rule == CouncilK.DECISION_QMR and (treaty_line or not qmr_line):
			_fail("a qualified-majority proposal does not read as a majority alone")
		# QA on #99: the trim cut the rule's explanation, so the line must carry the
		# term that explains it -- one hover away.
		var marks := _term_ids(panel)
		for id in (["treaty", "veto", "ratification"] if rule == CouncilK.DECISION_UNANIMITY else ["qualified_majority"]):
			if not marks.has(id):
				_fail("the %s decision line carries no [g=%s] mark: %s" % [rule, id, marks])
		_drop(panel)
	p.decision = kept


## Cast, then press a Favour: the sim is called, `acted` fires exactly once and
## the table re-renders with that member's three buttons spent.
func _check_a_bargain_reaches_the_sim() -> void:
	var state = _fresh()
	_stage_pending(state)
	var panel := _panel_for(state)
	var voted: Array = []
	var acted: Array = []
	panel.voted.connect(func(_b, label): voted.append(label))
	panel.acted.connect(func(_b, label): acted.append(label))
	_refresh(panel)

	var against_button := _button_named(panel, "Against")
	if against_button == null or against_button.disabled:
		_fail("no enabled Against button on a pending proposal")
		return
	against_button.pressed.emit()
	if voted.size() != 1:
		_fail("casting Against emitted voted %d times, expected 1" % voted.size())
	if String(Orgs.pending(state, EU_ORG).get("player_vote", "")) != Orgs.VOTE_AGAINST:
		_fail("pressing Against did not reach Orgs.cast_vote")
	_refresh(panel)

	var target := _listed_target(panel, state)
	if target == "":
		_fail("fixture: the table lists no member")
		return
	# A favour needs standing; the refusal path has its own check below.
	RK.adjust(state, PLAYER, target, 100.0, 0.0, 100.0)
	_refresh(panel)

	var name: String = _loader.nation_name(target)
	var buttons := _member_buttons(panel, name)
	if buttons.size() != 3:
		_fail("%s's row has %d currency buttons, expected 3" % [name, buttons.size()])
		return
	var favour: Button = buttons[0]
	if not favour.text.begins_with("Favour"):
		_fail("the first currency button is '%s', not the favour" % favour.text)
	if favour.disabled:
		_fail("the favour is disabled for a member the player is close to")
		return
	favour.pressed.emit()

	_refresh(panel)
	if not _text(panel).contains("Already bargained this division: %s (favour, asked AGAINST)" % name):
		_fail("the table does not name who was already bargained with: %s" % _text(panel))
	var sponsor_name: String = _loader.nation_name(String(Orgs.pending(state, EU_ORG).get("sponsor", "")))
	if not _text(panel).contains("%s — its own proposal: votes FOR" % sponsor_name) or _text(panel).contains("%s — leans" % sponsor_name):
		_fail("the sponsor's row does not read as settled FOR: %s" % _text(panel))
	var bargains: Dictionary = Orgs.pending(state, EU_ORG).get("bargains", {})
	if not bargains.has(target):
		_fail("pressing Favour did not put %s in pending.bargains" % target)
	if acted.size() != 1:
		_fail("a bargain emitted acted %d times, expected 1" % acted.size())
	if voted.size() != 1:
		_fail("a bargain emitted voted (%d total)" % voted.size())

	_refresh(panel)
	buttons = _member_buttons(panel, name)
	if buttons.size() != 3:
		_fail("%s's row vanished after the bargain" % name)
	for b in buttons:
		if not (b as Button).disabled:
			_fail("'%s' is still pressable after bargaining with %s" % [(b as Button).text, name])
	_drop(panel)


## A bargain the sim refuses must not report a decision, and must say so on the
## NEXT refresh (the message used to be erased by the refresh that scheduled it).
func _check_a_refused_bargain_speaks() -> void:
	var state = _fresh()
	_stage_pending(state)
	Orgs.cast_vote(state, EU_ORG, Orgs.VOTE_FOR)

	var panel := _panel_for(state)
	var acted: Array = []
	panel.acted.connect(func(_b, label): acted.append(label))
	_refresh(panel)
	var target := _listed_target(panel, state)
	if target == "":
		_fail("fixture: the table lists no member")
		return
	RK.adjust(state, PLAYER, target, -100.0, 0.0, 100.0)
	_refresh(panel)

	var buttons := _member_buttons(panel, _loader.nation_name(target))
	if buttons.is_empty() or not (buttons[0] as Button).disabled:
		_fail("the favour is pressable at relations below the minimum")

	# The table disables the button, so reach the handler as a stale press would.
	panel._on_bargain(EU_ORG, target, CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR)
	if not acted.is_empty():
		_fail("a refused bargain emitted acted")
	if Orgs.pending(state, EU_ORG).get("bargains", {}).has(target):
		_fail("the refused bargain was written to the register")
	if _text(panel).contains("Refused:"):
		_fail("the refusal was shown before the next refresh")
	_refresh(panel)
	if not _text(panel).contains("Refused:"):
		_fail("a refused bargain said nothing on the next refresh")
	_refresh(panel)
	if _text(panel).contains("Refused:"):
		_fail("the refusal was not cleared after being spoken once")
	_drop(panel)


## The fold-in from the T1 review: a vote with nothing pending.
func _check_a_refused_vote_speaks() -> void:
	var state = _fresh()
	state.orgs[EU_ORG]["pending"] = {}
	var panel := _panel_for(state)
	var voted: Array = []
	panel.voted.connect(func(_b, label): voted.append(label))
	_refresh(panel)

	panel._on_vote(EU_ORG, Orgs.VOTE_FOR)
	if not voted.is_empty():
		_fail("a vote cast with nothing pending emitted voted")
	_refresh(panel)
	if not _text(panel).contains("Refused:"):
		_fail("a refused vote said nothing on the next refresh")
	_drop(panel)


## The treaty card: present, the panel's primary, blurred, and a real verb.
func _check_the_ratify_card() -> void:
	var state = _fresh()
	state.orgs[EU_ORG]["pending"] = {}
	_stage_ratifying(state)
	var panel := _panel_for(state)
	var acted: Array = []
	panel.acted.connect(func(_b, label): acted.append(label))
	_refresh(panel)
	var text := _text(panel)

	if not text.contains("RATIFY AT HOME"):
		_fail("a treaty waiting on the player's assembly has no card: %s" % text)
	var button := _button_named(panel, "Put it to the assembly")
	if button == null:
		_fail("the ratify card has no button")
		return
	var primary: Control = panel.primary_action()
	if primary != button:
		_fail("the ratify button is not the panel's primary_action (got %s)" % primary)
	if primary != null and not panel.is_ancestor_of(primary):
		_fail("the primary action is not inside the panel")

	# The blurred forecast, in law_panel's own words. The expectation is computed
	# by law_panel, not typed here, so a change to its wording moves both.
	var p = Orgs.proposal_by_id(_loader, EU_ORG, PROPOSAL)
	var bill = Ratification.treaty_bill(p)
	var parties: Array = _loader.parties.get(PLAYER, [])
	var player = state.player()
	var blurred: String = LawPanel.forecast_text(player, parties, bill, LawPanel.forecast_band(player, bill.id))
	if not text.contains(blurred):
		_fail("the ratify card does not carry law_panel's forecast '%s': %s" % [blurred, text])
	if not blurred.contains("undecided"):
		_fail("fixture: law_panel's forecast no longer has an undecided bucket, so the blur check proves nothing")
	# No exact verdict: the card's only "falls" is the fixed warning sentence.
	var stripped := text.replace("If it falls here it falls for all", "")
	for verdict in ["carries", "will pass", "would pass", "will fail", "falls"]:
		if stripped.contains(verdict):
			_fail("the ratify card states a verdict ('%s'): %s" % [verdict, text])

	button.pressed.emit()
	if not (state.orgs[EU_ORG]["ratifying"] as Dictionary).is_empty():
		_fail("pressing the ratify button did not call Ratification.submit")
	if acted.size() != 1:
		_fail("ratifying emitted acted %d times, expected 1" % acted.size())
	_refresh(panel)
	if _text(panel).contains("RATIFY AT HOME"):
		_fail("the ratify card is still up after the treaty was settled")
	_drop(panel)


## The desk's mark: a treaty alone lights the Organisations window.
func _check_the_desk_marks_a_treaty() -> void:
	var state = _fresh()
	state.orgs[EU_ORG]["pending"] = {}
	# Nothing waiting: the mark must not be a constant.
	if Pending.window_ids(state, _loader).has("orgs"):
		_fail("the orgs mark is lit with nothing pending")
	_stage_ratifying(state)
	if not Pending.window_ids(state, _loader).has("orgs"):
		_fail("a treaty waiting on the player's assembly does not mark the orgs window")
	# Already ratified at home: nothing awaits the player any more.
	state.orgs[EU_ORG]["ratifying"]["nations"][PLAYER] = CouncilK.RATIFY_DONE
	if Pending.window_ids(state, _loader).has("orgs"):
		_fail("a treaty the player already ratified still marks the orgs window")


## The top bar's Europe figure in its four states, and the plural fix.
func _check_the_europe_figure() -> void:
	# Hidden for a player in no council org.
	var outside = _fresh()
	outside.player().orgs.clear()
	var bar := _bar_for(outside)
	if bar._figure_values["europe"].get_parent().visible:
		_fail("the Europe figure shows for a player in no council org")
	_drop(bar)

	# Nothing: clear.
	var clear = _fresh()
	bar = _bar_for(clear)
	if not bar._figure_values["europe"].get_parent().visible:
		_fail("the Europe figure is hidden for a council member")
	elif String(bar._figure_values["europe"].text) != "— clear":
		_fail("an untroubled member reads '%s', not '— clear'" % bar._figure_values["europe"].text)
	_drop(bar)

	# One breached rule: the burden, and the singular in the tooltip.
	var breached = _fresh()
	var ns = breached.player()
	breached.orgs[EU_ORG]["rules"]["probe"] = {
		"name": "Probe Rule", "field": "deficit_pct_gdp", "op": "<=",
		"value": ns.deficit_pct_gdp - 6.0, "tolerance": 6.0, "severity": 0.5,
		"transfer_pct_gdp": 0.0, "since_year": 2026, "since_month": 1,
	}
	bar = _bar_for(breached)
	var burden_text := String(bar._figure_values["europe"].text)
	if burden_text != "Burden 0.50":
		_fail("one rule breached by a full tolerance reads '%s', not 'Burden 0.50'" % burden_text)
	var tip: String = bar.tip_of("europe")
	if not tip.contains("1 rule in force binds you, 1 breached"):
		_fail("the tooltip does not read the singular for one rule: %s" % tip)
	if tip.contains("1 rules"):
		_fail("the tooltip says '1 rules': %s" % tip)
	_drop(bar)

	# A treaty beats the burden: it has a deadline.
	_stage_ratifying(breached, 3)
	bar = _bar_for(breached)
	var treaty_text := String(bar._figure_values["europe"].text)
	if treaty_text != "Treaty: 3m":
		_fail("a pending ratification reads '%s', not 'Treaty: 3m'" % treaty_text)
	_drop(bar)


## An org with a division waiting on the player is listed before one with nothing.
func _check_a_waiting_council_lists_first() -> void:
	var state = _fresh()
	_stage_pending(state)
	var panel := _panel_for(state)
	_refresh(panel)
	var text := _text(panel)
	var eu_at := text.find("THE EUROPEAN UNION")
	var climate_at := text.find("THE CLIMATE ACCORD")
	if eu_at < 0 or climate_at < 0 or eu_at > climate_at:
		_fail("a pending eu division does not list before the climate accord (%d vs %d)" % [eu_at, climate_at])
	_drop(panel)


## The dirty -> visible -> _process -> _refresh gate every handler relies on, driven
## by REAL frames: the panel rebuilds itself, nobody calls _refresh(). Stages run
## on consecutive frames; the scene-tree script's _process runs before the
## panel's within a frame, so a press at frame k is rendered by the end of k.
var _fs_panel: Control
var _fs_stage := 0


func _start_frame_scenario() -> void:
	var state = _fresh()
	state.orgs[EU_ORG]["pending"] = {}
	_fs_panel = _panel_for(state)  # visible: its own first _process builds the body
	_fs_stage = 1


func _run_frame_scenario() -> void:
	var panel := _fs_panel
	match _fs_stage:
		1:
			if not _text(panel).contains("THE EUROPEAN UNION"):
				_fail("a visible panel did not build itself on its own frame")
			if _text(panel).contains("Refused:"):
				_fail("fixture: the panel opens already refusing")
			panel._on_vote(EU_ORG, Orgs.VOTE_FOR)
		2:
			if not _text(panel).contains("Refused: that vote"):
				_fail("a refused press on a visible panel was not re-rendered by its own _process")
			# Hidden: the press marks dirty and nothing rebuilds until it is shown.
			panel.hide()
			panel._on_bargain(EU_ORG, SPONSOR, CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR)
		3:
			if _text(panel).contains("that bargain can no longer"):
				_fail("a hidden panel rebuilt itself")
			if not panel._dirty:
				_fail("a press on a hidden panel did not mark it dirty")
			panel.show()
		4:
			if not _text(panel).contains("Refused: that bargain can no longer"):
				_fail("a panel shown again did not rebuild the press it missed")
			_drop(panel)
			_finish()
	_fs_stage += 1


func _bar_for(state) -> Control:
	var bar: Control = load(TOP_BAR_SCRIPT).new()
	root.add_child(bar)
	bar.refresh(state, null, _loader)
	_live.append(bar)
	return bar


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	for node in _live:
		(node as Node).queue_free()
	if _failures.is_empty():
		print("test_orgs_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
