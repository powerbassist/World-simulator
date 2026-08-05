extends SceneTree

## Saves a PNG of the running game. Dev-only, never shipped.
##
##   godot --path "<repo>" --script res://tools/screenshot.gd
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --frames 40
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer relations
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer trade --hover DEU
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer coercion --coerce
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --bloc
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --bloc --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --nation LUX
##
## Exists because --headless draws nothing and the whole test suite is headless.
## Two U5a bugs -- the map's opening zoom and a window's maximum height -- were
## wrong on a 1080p screen and invisible to a green suite; both would have been
## obvious in one frame. A UI session that never looks at a frame is a UI session
## that ships whatever the layout engine happened to do.
##
## Runs windowed, not headless, on purpose: root.get_texture() is the window's own
## framebuffer, and with no rendering device there is nothing in it.

const Relations = preload("res://src/core/relations.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const BlocK = preload("res://src/sim/bloc_constants.gd")

const OUT_DEFAULT := "user://screenshot.png"

## Enough frames for the theme to build, the raster to decode, and the first
## resize -- which is what triggers _fit_zoom() -- to have happened and been
## drawn. Below about ten the map is caught at zoom 1.0 mid-fit.
const FRAMES_DEFAULT := 30

var _frames_wanted := FRAMES_DEFAULT
var _out_path := OUT_DEFAULT
var _frame := 0

## U5c. Which map layer to capture, and which nation to hold the cursor over.
## Both exist because the layer system's one falsifiable claim -- that a
## saturated ramp survives being drawn over a satellite photograph -- can only be
## checked by looking, and there are four frames to look at rather than one.
var _layer := ""
var _hover := ""

## V1.3c. Impose a spread of measures before capturing, because a new game has
## none and a frame of an all-zero layer proves nothing about its ramp -- which is
## the one claim a screenshot exists to check. U5c's own falsifier was whether a
## saturated ramp survives being drawn over a satellite photograph; that question
## cannot be asked of a layer where every nation sits at the same end.
var _coerce := false

## V1.3d, and the same argument --coerce makes one session later. A new game has
## an empty council: no rule in force, nothing before the members, no penalty on
## the budget. A frame of that panel would show three "None" captions and prove
## nothing about the layout that matters -- which is the one claim a screenshot
## exists to check. This puts a rule in force, a proposal on the table, and the
## player in breach of the rule, then opens the window.
var _bloc := false

## Which registered window to open before capturing, by the id main.gd registered
## it under. Generic rather than a flag per panel: --bloc exists because it has to
## SET UP state the panel has nothing to show without, which is a different job
## from simply opening a window.
var _open := ""

## V1.3e, and --bloc's argument a third time. The nation panel's refusal line only
## renders for a partner who actually refuses, and which partners refuse is the
## whole thing the interest model decides -- so a frame of the panel opened on
## nobody, or on a partner who signs, shows the absence of the line rather than the
## line. Takes the id so the frame can be aimed at a refuser.
var _nation := ""
var _main


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			_frames_wanted = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]
		elif args[i] == "--layer" and i + 1 < args.size():
			_layer = args[i + 1]
		elif args[i] == "--hover" and i + 1 < args.size():
			_hover = args[i + 1].to_upper()
		elif args[i] == "--coerce":
			_coerce = true
		elif args[i] == "--bloc":
			_bloc = true
		elif args[i] == "--open" and i + 1 < args.size():
			_open = args[i + 1]
		elif args[i] == "--nation" and i + 1 < args.size():
			_nation = args[i + 1].to_upper()

	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	# One frame before the capture, not at _init(): the map has to have been laid
	# out and fitted before a lon/lat can be turned into the screen point the
	# hover needs, and the legend has to have run _ready() to be told anything.
	if _frame == _frames_wanted - 1:
		_apply_view()
	if _frame < _frames_wanted:
		return false

	var image := root.get_texture().get_image()
	if image == null:
		printerr("no framebuffer -- run windowed, not --headless")
		quit(1)
		return true

	var error := image.save_png(_out_path)
	if error != OK:
		printerr("could not write %s: %d" % [_out_path, error])
		quit(1)
		return true

	print("wrote %s (%dx%d)" % [ProjectSettings.globalize_path(_out_path), image.get_width(), image.get_height()])
	quit(0)
	return true


## Drives the map through its public surface rather than synthesising input:
## set_layer() and the hover fields are the same methods the legend and a
## headless test use, so this tool captures the real code path.
func _apply_view() -> void:
	if _main == null or _main._map_view == null:
		return
	if _coerce:
		_impose_a_spread()
	if _bloc:
		_open_the_council()
	if _nation != "":
		# Through main.gd's own click path rather than by poking the panel, so the
		# frame captures what a click produces.
		_main._on_nation_clicked(_nation)
	if _open != "":
		_main._windows.open(_open)
	if _layer != "":
		_main._map_view.set_layer(_layer)
		_main._hud.map_legend.show_layer(_main._map_view.layer())
	if _hover != "":
		_main._map_view._hovered_id = _hover
		_main._map_view.queue_redraw()
		_main._hud.map_legend.show_hover(
			_hover, _main._state, _main._map_view.viewer_id()
		)


## One measure at each legend stop, so the captured frame shows the whole ramp
## rather than one point on it. Written straight into the register, the way
## tools/coercion_probe.gd does -- this is a dev tool looking at pixels, not a
## test of the command path, and going through Diplomacy.execute() would tie the
## severities to whatever the shipped verbs happen to use.
func _impose_a_spread() -> void:
	var state = _main._state
	if state == null:
		return
	var viewer: String = _main._map_view.viewer_id()

	# Deliberately spread across the domain AND across the two directions, so the
	# frame answers both questions at once: does the ramp separate, and does a
	# measure aimed AT the player read the same as one the player aimed.
	var spread := {"DEU": 0.625, "ITA": 1.0, "ESP": 0.3}
	for target in spread.keys():
		if not state.nations.has(target):
			continue
		state.measures[Relations.directed_key(viewer, target)] = _terms(
			state, "tariff", float(spread[target])
		)
	# Mutual: the pair that must read at the top of the ramp rather than as clean,
	# which is the netting bug this layer's design note warns a later session about.
	if state.nations.has("ITA"):
		state.measures[Relations.directed_key("ITA", viewer)] = _terms(state, "tariff", 1.0)

	_main._map_view.queue_redraw()


func _terms(state, kind: String, severity: float) -> Dictionary:
	return {
		"action_id": "screenshot", "action_name": "Screenshot",
		"kind": kind, "severity": severity,
		"since_year": state.year, "since_month": state.month, "retaliated": true,
	}


## One rule in force, one proposal before the council, and the player in breach of
## the rule -- so the captured frame shows every section of the panel with real
## figures in it. Written straight into the register the way _impose_a_spread()
## writes measures, and for the identical reason: this is a dev tool looking at
## pixels, and going through the council's own eighteen-month schedule would mean
## capturing frame 540.
func _open_the_council() -> void:
	var state = _main._state
	if state == null or state.bloc.is_empty():
		return

	var proposal = null
	var pending = null
	for p in _main._loader.bloc_proposals:
		if not p.constraint.is_empty() and proposal == null:
			proposal = p
		elif pending == null:
			pending = p
	if proposal == null:
		return

	state.bloc["rules"][proposal.id] = {
		"name": proposal.proposal_name,
		"field": String(proposal.constraint["field"]),
		"op": String(proposal.constraint["op"]),
		"value": float(proposal.constraint["value"]),
		"tolerance": float(proposal.constraint["tolerance"]),
		"severity": float(proposal.constraint["severity"]),
		"transfer_pct_gdp": 0.0,
		"since_year": state.year, "since_month": state.month,
	}
	if pending != null:
		state.bloc["pending"] = {
			"proposal_id": pending.id, "name": pending.proposal_name,
			"summary": pending.summary, "months_left": 2,
			"player_vote": "against",
			"opened_year": state.year, "opened_month": state.month,
		}
	# V1.3e. A DIVISION THAT HAS ALREADY HAPPENED, not only one pending.
	#
	# The panel's new section says why each member voted as it did, and it reads
	# `last_vote`, which a pending proposal does not populate. Without this the
	# frame shows the section's absence rather than the section -- exactly the
	# three-"None"-captions frame --bloc was added to stop capturing.
	#
	# Built through the real vote path (Bloc.support and Bloc.vote_reason) rather
	# than by inventing a tally, because the one thing this frame has to check is
	# that the reasons the model produces group into camps a player can read.
	# A proposal that actually DIVIDES the council, scanned for rather than taken
	# in agenda order. The first version took the next proposal off the list and
	# got minimum_corporate_rate, which every member backs for the same reason --
	# a frame showing one camp of eight, which proves nothing about a section whose
	# whole job is to show the camps. --coerce's own argument about an all-zero
	# layer, one session later.
	var divided = null
	var fallback = null
	for p in _main._loader.bloc_proposals:
		if p.id == proposal.id or (pending != null and p.id == pending.id):
			continue
		if fallback == null:
			fallback = p
		# Divided ON THE VOTE, not only on the reason. A proposal every member backs
		# for the same reason is a frame of one camp; a proposal they split on shows
		# what the section is for even when the reason is the same word.
		var seen_for := false
		var seen_against := false
		for id in Bloc.members(state, _main._loader):
			if Bloc.support(state, state.nations[id], p) >= BlocK.SUPPORT_THRESHOLD:
				seen_for = true
			else:
				seen_against = true
		if seen_for and seen_against:
			divided = p
			break
	if divided == null:
		divided = fallback
	if divided != null:
		var votes := {}
		var reasons := {}
		var seats_for := 0
		var seats_against := 0
		var seats_total := 0
		for id in Bloc.members(state, _main._loader):
			var seats: int = _main._loader.eu.ep_seats(id)
			seats_total += seats
			var backs: bool = Bloc.support(state, state.nations[id], divided) >= BlocK.SUPPORT_THRESHOLD
			votes[id] = Bloc.VOTE_FOR if backs else Bloc.VOTE_AGAINST
			reasons[id] = Bloc.vote_reason(state, state.nations[id], divided)
			if backs:
				seats_for += seats
			else:
				seats_against += seats
		state.bloc["last_vote"] = {
			"proposal_id": divided.id, "name": divided.proposal_name,
			"passed": float(seats_for) >= BlocK.PASS_SEAT_FRACTION * float(seats_for + seats_against),
			"seats_for": seats_for, "seats_against": seats_against,
			"seats_total": seats_total,
			"player_vote": String(votes.get(state.player_nation_id, "abstain")),
			"votes": votes, "reasons": reasons,
			"year": state.year, "month": state.month,
		}

	# So the burden, the penalty line and the breach caption are all non-zero.
	Bloc.tick_month(state, _main._loader)

	_main._windows.open("bloc")
	if _main._bloc_panel != null:
		_main._bloc_panel.mark_dirty()
