extends SceneTree

## Saves a PNG of the running game. Dev-only, never shipped.
##
##   godot --path "<repo>" --script res://tools/screenshot.gd
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --frames 40
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer relations
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer trade --hover DEU
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --layer coercion --coerce
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --orgs
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --orgs --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --council-sponsored
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --council-treaty
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --council-ratify
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --council-chair
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --event --domain presidency
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --climate --open events
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --nation LUX
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --lang fr --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --text 130 --domain finances
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --play DEU --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --hover-outline RUS
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --book --open calendar
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --build --open projects
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --build --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --build --hover-project high_speed_rail
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --campaign --open campaign
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --campaign --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --tip approval:1
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --outliner --open outliner
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --tip deficit:1
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --settings
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --bid --open companies
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --failing --open companies
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --tax
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --compose
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --pmb
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --pledge --open campaign
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --referendum --open legislature
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --electoral --open politics
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --senate --open legislature
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --court --open legislature
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --senate --open politics
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --region
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --city
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --diverge
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --move
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --zoom 8
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --zoom 8 --paused
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --flows --zoom 1.6
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --flows --zoom 6 --paused
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --zoom 6 --center 12.85 55.66
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --open budget --forecast-computing
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --month-closing
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --console
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --console-errors
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --perf --frames 120
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --cards 6 --open budget
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --mood 35
##   godot --path "<repo>" --script res://tools/screenshot.gd -- --mid-term --open agenda
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
const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const BlocK = preload("res://src/sim/bloc_constants.gd")
const Council = preload("res://src/sim/council.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
## V2.6b1, for --site: the flag has to ASK where the demonstration is rather than
## assume, because a nation whose register cannot single a region out has no site and
## the flag must say so instead of photographing an unringed city.
const Unrest = preload("res://src/sim/unrest.gd")
const Regions = preload("res://src/sim/regions.gd")
const Energy = preload("res://src/sim/energy.gd")
const Migration = preload("res://src/sim/migration.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Programme = preload("res://src/sim/programme.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const Events = preload("res://src/sim/events.gd")
const ReferendumK = preload("res://src/sim/referendum_constants.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const IndustryK = preload("res://src/sim/industry_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Statute = preload("res://src/sim/statute.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Elections = preload("res://src/sim/elections.gd")

const OUT_DEFAULT := "user://screenshot.png"

## Enough frames for the theme to build, the raster to decode, and the first
## resize -- which is what triggers _fit_zoom() -- to have happened and been
## drawn. Below about ten the map is caught at zoom 1.0 mid-fit.
const FRAMES_DEFAULT := 30

## How far before the capture _apply_view() runs. Four rather than one: see the
## note at the call site -- a window opened by --open needs a frame to become
## visible and another for its panel to rebuild.
const APPLY_LEAD_FRAMES := 4

var _frames_wanted := FRAMES_DEFAULT
var _out_path := OUT_DEFAULT
var _frame := 0

## U5c. Which map layer to capture, and which nation to hold the cursor over.
## Both exist because the layer system's one falsifiable claim -- that a
## saturated ramp survives being drawn over a satellite photograph -- can only be
## checked by looking, and there are four frames to look at rather than one.
var _layer := ""
var _hover := ""
var _site := false
var _hover_project := ""  ## U6c, a project marker rather than a nation
## V4.11c, an outline (a country drawn but not simulated). Its own flag for
## --hover-project's reason: a nation hover and an outline hover are different
## states on the map, and one flag meaning both would hide which one failed.
var _hover_outline := ""
## V4.8b. "<reading>" or "<reading>:<line>" -- opens that strip figure's tooltip
## popup through the bar's own hover handler, and the level-2 breakdown of the
## named level-1 line. A hover state no flag can reach is a popup nobody looks at.
var _tip := ""
## V4.8b. Stage one thing pinned in each outliner section (a running pinned
## programme entry, a failing major, a good short of demand, people with a
## grudge), so --open outliner photographs the window with every section drawn.
var _outliner := false

## V4.8c. The settings screen up over the game, so the MESSAGES grid (thirty-six
## band pickers under the display rows) is judged at 1080 rather than argued.
var _settings := false

## V3.1. A zoom the capture is taken at, framed on Paris like frame_probe.gd's
## samples, so a deep-zoom frame is over polygons rather than open sea. Exists
## because the cull pass's acceptance is pixel identity at fixed zooms: the
## same flag must be able to reproduce a frame exactly.
var _zoom := -1.0

## V3.1. Stops the clock for the capture. Exists because the identity frames
## caught the V1.4c date/state race class live: a capture whose frame budget
## straddles a day flip reads 02 JAN against 01 JAN and 456 pixels move for a
## reason that has nothing to do with the code under test. A capture that
## compares states must stage a frozen state.
var _paused := false
var _clock_frozen := false

## V3.4. The trade layer is the arcs' and the convoys' gate, so one flag sets it
## rather than asking the operator to remember two flags for one picture.
var _flows := false

## V3.4. Somewhere other than Paris to point --zoom at. Exists because the
## register's shortest sea crossing is DK01-SE22 (Copenhagen-Malmo, 28.4 km) and
## the dash constants were sized against a crossing twelve times longer; the look
## question cannot be asked of a frame that does not contain the edge.
var _center_lon := 0.0
var _center_lat := 0.0
var _has_center := false

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
var _orgs := false

## V4.5b2 T7. One of "sponsored" | "treaty" | "ratify" | "chair": which contested-
## council state _stage_contested_council() puts the EU in before the orgs window
## opens. A string, not four bools, because the frames are mutually exclusive.
var _council_frame := ""

## V1.3f. A new game's message column is empty and a frame of nothing proves
## nothing about it -- the same argument --coerce and --orgs were each added on.
var _agenda := false

## V4.1. Choose a programme (by entry id) through the real command path before
## capturing, so the chosen-state surfaces -- the agenda's progress bars, the
## top-bar strip, the Overview's PROGRAMME rows -- have something to draw.
## --agenda alone ticks 48 months with nothing chosen, which photographs the
## empty state and none of the rows the block exists to fill.
var _programme := ""

## Which registered window to open before capturing, by the id main.gd registered
## it under. Generic rather than a flag per panel: --orgs exists because it has to
## SET UP state the panel has nothing to show without, which is a different job
## from simply opening a window.
## V1.7a, and --coerce's argument for the fifteenth time. A campaign register is EMPTY
## outside the run-up and for every game that has not campaigned, so a frame of the
## Campaign panel on a new game shows six turnout rows at their authored constants, an
## em dash on the budget's campaign line and nothing in the field -- which is the
## absence of the feature rather than the feature. This ticks into the run-up, puts two
## efforts into the field through Campaign.execute(), and ticks again so the
## mobilisation has accrued and the bill has been billed.
var _campaign := false
## V1.7b, and --campaign's argument in its harder form. A pledge register is empty for
## every game that has not promised anything, AND a promise that has been made but not
## yet broken renders identically to no promise at all on the row that matters. So the
## flag has to cross an election and then break something, or the frame proves nothing
## about the one thing the panel exists to show.
var _pledge := false

## V1.7c. Two flags and not one, because the session ships two verbs at two different
## bars and a frame of either proves nothing about the other. --referendum photographs
## a vote in flight on the law panel; --electoral photographs an assembly elected under
## a system the player changed, which is only visible after the NEXT legislative
## election and is therefore the slower of the two.
var _referendum := false
var _electoral := false
## V1.1e. Two flags rather than one, because the two gates are two machines and a
## single frame showing both would prove neither.
var _senate := false
var _court := false
var _event := false
var _event_answered := false
## V3.5. A SITED event -- the place suffix on the card and on the panel question is
## this block's contribution to the surface, and no earlier flag waits for one:
## `--event` stops at whatever draws first and only NOTES a missing subject.
var _climate := false

var _open := ""
## V5.1-0a. The budget forecast computes off the frame, so a frame of the budget
## window drains it first -- unless --forecast-computing asks for the frame
## before it lands. --month-closing photographs a month mid-close, the clock
## held across frames (src/ui/month_runner.gd).
var _forecast_computing := false
var _month_closing := false
## V5.1-0b. The dev console (src/ui/dev_console.gd): --console opens it after a few
## commands, --console-errors opens its Errors tab after a logged error and a
## warning, --perf shows the overlay after one real-time month (needs --frames
## ~120: the month closes across frames and the overlay refreshes on a timer).
var _console := ""
var _perf_overlay := false
## V5.1-0c. --cards N fills the notification column with N cards (the column's
## layout and its overlap with windows are the point); --mood A sets the player's
## approval to A so the portrait card's mood icon can be read at each band.
var _cards := 0
var _mood := -1.0
## --mid-term: seven months into the term with nothing chosen, the page a loaded
## game shows (the Agenda's "when can I choose" line).
var _mid_term := false
## V5.1-c2.3: open a domain through its sidebar entry (its first tab), so a frame
## shows the entry marked and the tab open -- V2.1c's --cluster, for the sidebar.
var _domain := ""

## V1.3e, and --orgs's argument a third time. The nation panel's refusal line only
## renders for a partner who actually refuses, and which partners refuse is the
## whole thing the interest model decides -- so a frame of the panel opened on
## nobody, or on a partner who signs, shows the absence of the line rather than the
## line. Takes the id so the frame can be aimed at a refuser.
var _nation := ""
var _lang := ""  ## --lang CODE: the interface language of the staged game (default English)
var _text := 100  ## --text PCT: the text size (V5.1-c2.4), 90 / 100 / 115 / 130
var _play := ""  ## --play ID: the played nation of the staged game (default France)
var _defence := false

## U6a, and --coerce's argument a sixth time. A new game's diary is EMPTY inside
## its own horizon -- France's nearest dated event is sixteen months out and
## cooldowns do not exist until the player has acted -- so a frame of it shows a
## page of em dashes and a `later` footer, and proves nothing about the one thing
## the strip exists to draw. Books three acts and acts once, so the frame carries
## a booking, a kept appointment and a cooldown expiry the player never entered.
var _book := false
var _summit := false
var _interrupt := false

## V1.4a. A new game's firm register is every firm at its authored share with no
## subsidy standing, so a frame of the companies panel shows three zeroes on the
## ledger and "no support" against every firm -- which proves nothing about the row
## the panel exists to draw. Same argument --coerce, --orgs, --agenda and --defence
## each made; this is the fifth time.
var _subsidy := false

## V1.4b. Same argument once more, and this is the sixth time: a new game carries no
## `business` law, so every sector heading on the companies panel reads its plain
## caption and the law panel's `business` rows have never been proposed. A frame of
## an unregulated economy proves nothing about the row the burden draws.
var _regulate := false

## V1.4c, and the seventh time. A new game's register has nothing in public hands,
## so the companies panel reads "private" against every firm, the budget panel's
## dividend line reads an em dash, and the ledger's fourth row reads 0.000.
##
## IT APPLIES A BURDEN TOO, and that is not the --regulate flag repeated. The one
## thing ownership CONTROLS is the jobs shield, and a shield with nothing to shield
## against is a row of zeroes -- which is V1.4b's own --regulate bug, whose whole
## lesson was that a capture flag must move every figure the frame is there to
## prove. So this nationalises a firm in a sector it then regulates, and the frame
## carries the holding, the dividend, the burden and the jobs figure at once.
var _nationalise := false

## V4.7b B4. A new game's register carries no bid and no failing firm -- the
## autonomy machine draws both at hazards of 0.01/yr and 0.0003/month, so an
## unflagged capture proves only that the panel's autonomy sections stay
## silent. Both stages write the register EXACTLY as the machine writes it --
## the bid's three scalars, the failure's flag + zeroed share + window -- the
## same discipline test_industry's forced mechanics use, so the frame shows
## the rows the panel builds for the machine's own state, not a hand-shaped
## variant of it.
var _bid := false

## V4.7b B4. See _bid: stages a failing major mid-window, whose rescue row and
## the brass cluster mark are what the frame is there to prove.
var _failing := false

## V4.2 close-out. The tax panel reads live state -- the authored five plus the
## brackets lever are on a new game's register -- so unlike every staging flag
## on this list it stages NOTHING and only opens the window; the frame's claim
## is the rate-as-number rows, which is the panel's whole reason for existing.
var _tax := false

## V4.2 close-out. A draft the machine has parked renders NOWHERE on the law
## panel -- ns.draft_bills reaches the UI only through the briefing popup ("In
## drafting: N months" is the one place a draft's months_left is on screen) --
## so this drafts through Statute.draft() itself, opens the legislature window,
## and shows the briefing over the parked draft through main.gd's own handler
## body. NOT ticked afterwards: the countdown is the frame's claim, and a
## ticked draft is a composed one.
var _compose := false

## V4.2 close-out. The assembly's in-tray is empty on a new game -- the lobby
## draw is 0.02/month AND needs a burdened sector, the backbench draw 0.08 --
## so an unflagged capture photographs the empty early-return this panel's
## _endorse_refusal comment calls the reachable-refusal frame. Stages ONE lobby
## bill the machine's own way, on the --bid discipline: the burden through the
## ONE applier (never ticked), then the lobby body's own selectors into the
## very _table_bill() call _lobby() makes -- only the Cycle hazard draw is
## skipped, which is staging state rather than luck. NOT ticked: with
## PMB_MONTHS_TO_VOTE at 1, a ticked bill is a divided one and the row is gone.
var _pmb := false

## V1.5a, and the eighth time. A new game's quality stock sits EXACTLY on its own
## reference for all ten nations -- that is the property the whole session rests on --
## so the overview's two service lines are deliberately silent on frame 1 and a capture
## with no flag proves only that they stay quiet. This is the flag that makes them speak.
##
## It passes the corruption law rather than poking `ns.corruption`, so the frame proves
## the sixth effect channel dispatches as well as that the readout draws. And it ticks
## far enough for the STOCK to have moved off its reference: at QUALITY_CONVERGENCE the
## first month's move is ~2 % of the gap, which rounds to the same two decimals the
## panel prints -- a frame captured at month 1 would show a live corruption level
## against an unchanged quality figure and look like the readout was broken.
var _corrupt := false

## V1.5b, and the ninth flag. The economy panel's dependency line is never silent -- a
## country has an age structure on frame 1 -- but the figure it leads with is a
## DEVIATION, and on frame 1 that deviation is exactly 0.0 for all ten nations. So an
## unflagged capture proves the caption renders and proves nothing about whether the
## drift reaches it, which is the same argument --corrupt made one session ago and
## --coerce three blocks before that.
##
## Passes the migration law rather than poking `ns.migration_stance`, so the frame is
## evidence that the widened effects.society channel dispatches and not only that the
## label draws. Ticks far enough for the SHARES to have travelled: the drift is a
## fraction of a point a year, so a frame at month 1 would show a live stance against
## an unchanged ratio and look like the readout was broken.
var _migrate := false

## V1.5c: run a budget bad enough that the unions walk out, and hold the clock until
## they have. Both halves of the session need it -- the economy panel's unrest caption
## is SILENT below a grievance of 0.05, so an unflagged capture proves the caption
## compiles and nothing else, and the message card only exists in a month an act fires.
var _unrest := false
var _press := false
var _cycle := false
var _inflate := false
var _downgrade := false
var _redistribute := false
var _invest := false
var _build := false

## V2.2b, and a pair of flags that photograph a VIEW rather than a mutation: the
## register is static content, so there is no state to stage and the frame is the
## whole point. --region proves the Region panel builds and its five-column
## ledger fits. --city drives the map's own route end to end -- centred and
## zoomed past CITY_MIN_ZOOM on Paris, the cross hovered so the frame carries the
## hover label, and the City panel opened through show_city() exactly as main.gd's
## click lambda does it.
var _region := false
var _city := false

## V2.5. A frame of a register at month 1 shows the import and nothing this session
## built -- the whole quantity is a DIVERGENCE, and at month 1 it is exactly what
## data/regions/ says. Ten years is what makes the moved column readable.
var _diverge := false
var _election := false

## V3.6, the thirty-first flag: the front door. Boots menu.tscn instead of
## main.tscn and photographs the plate -- the real MapView over its month-0
## viewer state under the scrim. No clock exists in the menu, so --paused is
## accepted but a no-op there, and every main-scene staging flag is ignored.
var _menu := false

## V3.6, the thirty-second flag: the tally's two states (election night's
## count since V4.9b). Stages the June 2029
## double election (41 months -- the May 2027 presidential plate has no seats,
## so no bars), captures the plate mid-count, then finishes the tally the way a
## click does and captures it settled. The election pauses the clock itself, so
## the second frame cannot cross a day flip.
var _tally := false
var _tally_shot := 0

## V2.7, the twenty-sixth flag: ten years so the network term has moved the
## shares the accessibility column reads, the Region panel open on the league
## table where the new column lives.
var _network := false

## V2.8, the twenty-seventh flag: two plants of different branches ordered
## through Energy.execute(), ticked past the shorter build so the frame shows a
## running station AND one under construction, then the Energy panel -- which
## opens at the TOP of its scroll, because this flag is about the mix and the
## fleet (V1.6e's per-flag direction).
var _energy := false

## V2.8, the twenty-eighth flag: plants ON the map and the placement reticle
## armed, so the frame shows both halves of the click. France fit rather than the
## Europe fit, because two 5px glyphs at the whole-planet zoom prove nothing.
var _place := false

## V2.6a. `--migrate` is taken (V1.5b's migration LAW) and `--diverge` is taken
## (V2.5's region divergence), so this is `--move`. Ten years of a live
## MIGRATION_RATE moves the same quantity `--diverge` measures at a level below
## it -- the City panel's ranked list is the frame this flag exists to
## photograph, so it opens the LIST view rather than any one city's detail.
var _move := false

## V1.6 playability audit, and the first two flags that photograph a DEFECT rather
## than a feature. Both are cited from docs/playability-audit.md, because a claim
## about what the player sees needs a frame behind it and neither of these is
## reachable from any existing flag.
##
## --defeated forces the executive verdict the player loses on. The whole point is
## the FOOTER: election_panel builds Continue only in the not-defeated branch, so
## the frame should show a plate with nothing to press. Forced rather than played
## into, because losing honestly takes eleven years and the bug is in the branch,
## not in the road to it.
var _defeated := false

## --blank <window id> opens a window, presses the panel's OWN Close, and opens it
## again. Three of the eleven panels hide their content on that button while
## window_manager.open() only ever shows the FRAME, so the second open is the
## capture that matters: an empty frame the player cannot get back.
var _blank := ""

## V1.6 audit, V1. Stands the player on the last month of their last permitted
## term and lets Elections.tick_month() produce the notice itself, rather than
## building the plate by hand -- the whole finding was that this path rendered
## nothing, so a frame is only evidence if the sim is what produced it.
var _termlimit := false
var _main


## V4.11c. Hover an outline the way a cursor would: the first point of a coarse
## grid over the VISIBLE map that the outline test answers with this id, so the
## readout lands on screen at any zoom (a centroid of Russia sits off it).
## V4.8b, for --outliner. Writes the registers the outliner reads, the way
## tests/test_outliner.gd stages them, so the frame is the window with every
## section populated.
func _stage_the_outliner() -> void:
	var loader = _main._loader
	var ns = _main._state.player()
	for entry in loader.programme:
		if bool(entry.get("pinned", false)):
			ns.programme.append({
				"entry_id": String(entry["id"]), "chosen_term": 0, "months_live": 0,
				"status": "active", "concluded_term": -1, "concluded_term_month": -1,
			})
			break
	var major = Companies.majors_of(loader, ns.id)[0]
	var live: Dictionary = ns.companies.get(major.id, {})
	live["failed"] = true
	live["rescue_months_left"] = 3
	ns.companies[major.id] = live
	var good_id := String(loader.commodity_goods.keys()[0])
	ns.commodity_state = {"demand": {good_id: 100.0}, "output": {good_id: 12.0}, "trade": {good_id: 0.0}}
	var ids: Array = loader.person_by_id.keys()
	ids.sort()
	for i in 3:
		ns.person_grudges[String(ids[i])] = 0.5 - 0.1 * i
	ns.person_loyalty[String(ids[3])] = -0.4


## V4.8b, for --tip. The bar is refreshed first (a tip exists only after a
## refresh), then the hover goes through the same handler the label's mouse
## signal calls, so the frame is the popup a player's pointer produces.
func _stage_tip() -> void:
	var parts := _tip.split(":")
	var bar = _main._hud.top_bar
	bar.refresh(_main._state, _main._clock, _main._loader)
	if not bar._figure_values.has(parts[0]):
		push_error("screenshot: --tip '%s' is not a strip reading" % parts[0])
		return
	bar._on_figure_entered(parts[0], bar._figure_values[parts[0]])
	bar._popup.tick(bar._popup.OPEN_DELAY_S + 0.01)
	if parts.size() > 1:
		bar._popup.line_entered(int(parts[1]))


func _stage_outline_hover() -> void:
	var map = _main._map_view
	var view: Rect2 = map.visible_lonlat_rect()
	var steps := 60
	for ix in range(1, steps):
		for iy in range(1, steps):
			var pt := view.position + Vector2(view.size.x * ix / steps, view.size.y * iy / steps)
			if map._nation_at_lonlat(pt) == "" and map._outline_at_lonlat(pt) == _hover_outline:
				map._hovered_outline = _hover_outline
				map._hover_screen = map._lonlat_to_screen(pt.x, pt.y)
				map.queue_redraw()
				return
	printerr("--hover-outline: %s is not under any visible point" % _hover_outline)


func _init() -> void:
	# V4.9a. Every staged state is captured SETTLED: a window opened a frame
	# before the capture would otherwise be caught mid-fade. Motion itself is
	# judged from tools/motion_frames.gd's sequence captures, not from here.
	Motion.override = 0
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
		elif args[i] == "--hover-project" and i + 1 < args.size():
			# Its own flag rather than a second meaning for --hover, which
			# uppercases its argument for nation ids while a project id is
			# lowercase -- one flag with two case rules is a flag that fails
			# silently on whichever half you did not think of.
			_hover_project = args[i + 1]
		elif args[i] == "--hover-outline" and i + 1 < args.size():
			_hover_outline = args[i + 1].to_upper()
		elif args[i] == "--tip" and i + 1 < args.size():
			_tip = args[i + 1]
		elif args[i] == "--outliner":
			_outliner = true
		elif args[i] == "--settings":
			_settings = true
		elif args[i] == "--zoom" and i + 1 < args.size():
			_zoom = float(args[i + 1])
		elif args[i] == "--center" and i + 2 < args.size():
			_center_lon = float(args[i + 1])
			_center_lat = float(args[i + 2])
			_has_center = true
		elif args[i] == "--flows":
			_flows = true
		elif args[i] == "--paused":
			_paused = true
		elif args[i] == "--coerce":
			_coerce = true
		elif args[i] == "--orgs":
			_orgs = true
		elif args[i] in ["--council-sponsored", "--council-treaty", "--council-ratify", "--council-chair"]:
			_council_frame = String(args[i]).trim_prefix("--council-")
		elif args[i] == "--agenda":
			_agenda = true
		elif args[i] == "--programme" and i + 1 < args.size():
			_programme = args[i + 1]
		elif args[i] == "--defence":
			_defence = true
		elif args[i] == "--book":
			_book = true
		elif args[i] == "--summit":
			_summit = true
		elif args[i] == "--interrupt":
			_interrupt = true
		elif args[i] == "--subsidy":
			_subsidy = true
		elif args[i] == "--regulate":
			_regulate = true
		elif args[i] == "--nationalise":
			_nationalise = true
		elif args[i] == "--bid":
			_bid = true
		elif args[i] == "--failing":
			_failing = true
		elif args[i] == "--tax":
			_tax = true
		elif args[i] == "--compose":
			_compose = true
		elif args[i] == "--pmb":
			_pmb = true
		elif args[i] == "--corrupt":
			_corrupt = true
		elif args[i] == "--migrate":
			_migrate = true
		elif args[i] == "--unrest":
			_unrest = true
		elif args[i] == "--press":
			_press = true
		elif args[i] == "--cycle":
			_cycle = true
		elif args[i] == "--inflate":
			_inflate = true
		elif args[i] == "--downgrade":
			_downgrade = true
		elif args[i] == "--redistribute":
			_redistribute = true
		elif args[i] == "--invest":
			_invest = true
		elif args[i] == "--build":
			_build = true
		elif args[i] == "--campaign":
			_campaign = true
		elif args[i] == "--pledge":
			_pledge = true
		elif args[i] == "--referendum":
			_referendum = true
		elif args[i] == "--electoral":
			_electoral = true
		elif args[i] == "--senate":
			_senate = true
		elif args[i] == "--court":
			_court = true
		elif args[i] == "--event":
			_event = true
		elif args[i] == "--climate":
			_climate = true
		elif args[i] == "--event-answered":
			_event_answered = true
		elif args[i] == "--region":
			_region = true
		elif args[i] == "--city":
			_city = true
		elif args[i] == "--diverge":
			_diverge = true
		elif args[i] == "--network":
			_network = true
		elif args[i] == "--energy":
			_energy = true
		elif args[i] == "--place":
			_place = true
		elif args[i] == "--site":
			_site = true
		elif args[i] == "--move":
			_move = true
		elif args[i] == "--election":
			_election = true
		elif args[i] == "--menu":
			_menu = true
		elif args[i] == "--tally":
			_tally = true
			# V4.9b: the count is motion, so this flag alone turns it back on --
			# the mid-count frame is the point of the capture.
			Motion.override = 1
		elif args[i] == "--open" and i + 1 < args.size():
			_open = args[i + 1]
		elif args[i] == "--forecast-computing":
			_forecast_computing = true
		elif args[i] == "--month-closing":
			_month_closing = true
		elif args[i] == "--console":
			_console = "console"
		elif args[i] == "--console-errors":
			_console = "errors"
		elif args[i] == "--mid-term":
			_mid_term = true
		elif args[i] == "--cards" and i + 1 < args.size():
			_cards = int(args[i + 1])
		elif args[i] == "--mood" and i + 1 < args.size():
			_mood = float(args[i + 1])
		elif args[i] == "--perf":
			_perf_overlay = true
		elif args[i] == "--domain" and i + 1 < args.size():
			_domain = args[i + 1]
		elif args[i] == "--defeated":
			_defeated = true
		elif args[i] == "--termlimit":
			_termlimit = true
		elif args[i] == "--blank" and i + 1 < args.size():
			_blank = args[i + 1]
		elif args[i] == "--nation" and i + 1 < args.size():
			_nation = args[i + 1].to_upper()
		elif args[i] == "--lang" and i + 1 < args.size():
			_lang = args[i + 1]
		elif args[i] == "--text" and i + 1 < args.size():
			_text = int(args[i + 1])
		elif args[i] == "--play" and i + 1 < args.size():
			_play = args[i + 1].to_upper()

	# Before anything is built: tr() text is the language it was built in.
	if _lang != "" and not Strings.set_language(_lang):
		push_error("screenshot: language '%s' is not offered" % _lang)
	# Before the first theme is built, as the settings file sets it at boot.
	UiTheme.set_text_scale(_text / 100.0)
	if _menu:
		_main = load("res://src/ui/menu.tscn").instantiate()
	else:
		_main = load("res://src/ui/main.tscn").instantiate()
		if _play != "":
			_main.pending_player_id = _play
	root.add_child(_main)


## V5.1-0b. The dev console's states, staged through its own run_command() the way
## an agent drives it. --perf starts a real-time month at frame 3 so the runner has
## a cost table by the time the capture is taken.
func _stage_console() -> void:
	var console: Control = _main.get_node("DevConsole")
	if _perf_overlay and _frame == 3:
		console.run_command("perf on")
		var clock: Node = _main._clock
		while clock.day < clock._days_in_month(clock.month, clock.year):
			clock.advance_one_day()
		clock.paused = false
		clock._process(1.0 / clock.SPEED_DAYS_PER_SECOND[clock.speed - 1])
	if _frame != _frames_wanted - 2:
		return
	match _console:
		"console":
			for line in ["help", "get me.deficit_pct_gdp", "set me.assembly_seats 600", "skip 1", "get me.assembly_seats", "event nonsense"]:
				console.run_command(line)
			console.toggle()
		"errors":
			push_error("staged for the screenshot: an error")
			push_warning("staged for the screenshot: a warning")
			console.show_errors()


func _process(_delta: float) -> bool:
	# Frame 1, and NOT in _init(): main's @onready vars do not exist while
	# _init runs -- the first version froze the clock there, read a Nil, and
	# the game silently ran on (three of eight identity captures crossed a day
	# flip before the flag ever bit). Frame 1 is still inside the first
	# accumulated second, so no day can have flipped ahead of the freeze.
	# The menu has no clock to freeze and no _clock property to read.
	if _paused and not _menu and not _clock_frozen:
		_clock_frozen = true
		_main._clock.paused = true
	_frame += 1
	# Several frames before the capture, not one, and V1.3g is why. A panel refreshes
	# in its own _process and returns early while it is not visible, so a window
	# OPENED by --open has not rebuilt itself when the very next frame is captured:
	# --defence --open budget showed an em dash on a live 0.498 bill, and the state
	# was provably correct at the time. One frame was enough for a window that was
	# already open, which is why every flag before this one got away with it.
	#
	# Not at _init() either, for the original reason: the map has to have been laid
	# out and fitted before a lon/lat can be turned into the screen point the hover
	# needs, and the legend has to have run _ready() to be told anything.
	# The menu stages nothing -- its plate is built in _ready() and static.
	if _frame == _frames_wanted - APPLY_LEAD_FRAMES and not _menu:
		_apply_view()
	# Two frames ahead: the panel states what it proposes, the projections run to
	# the end, and the settled panel redraws in time for the capture.
	if _frame == _frames_wanted - 2 and not _menu and not _forecast_computing 			and _main._windows.is_open("budget"):
		_main._budget_panel._process(0.0)
		_main._budget_panel._forecast.drain()
	# One frame ahead: real time reaches the 1st, and the capture lands while the
	# month is still closing (it takes ten frames or more).
	if _month_closing and _frame == _frames_wanted - 1 and not _menu:
		var clock: Node = _main._clock
		while clock.day < clock._days_in_month(clock.month, clock.year):
			clock.advance_one_day()
		clock.paused = false
		clock._process(1.0 / clock.SPEED_DAYS_PER_SECOND[clock.speed - 1])
	if (_console != "" or _perf_overlay) and not _menu:
		_stage_console()
	if _frame == 3 and not _menu:
		for n in _cards:
			_main._hud.message_stack.push("Card %d" % (n + 1), "A notification body long enough to wrap onto a second line in the column.")
		if _mid_term:
			_main._state.player().months_in_term = 7
			_main._enforce_term_start_programme()
			_main._agenda_panel.mark_dirty()
		if _mood >= 0.0:
			_main._state.player().overall_approval_pct = _mood
			_main._hud.portrait_card.refresh()
	if _frame < _frames_wanted:
		return false

	# V3.6: the tally's two frames. First the plate mid-fill, then the skip --
	# through _gui_input, the same entry a real click takes -- and two frames
	# on, the settled plate. Writing both costs one run instead of two.
	# Gated on not _menu: the menu has no _election_panel, and a --menu --tally
	# combination would otherwise dereference it every frame after the first
	# shot and never quit (the V3.6 review's minor).
	if _tally and not _menu:
		if _tally_shot == 0:
			if not _write_frame(_out_path, "mid-tally"):
				return true
			_tally_shot = 1
			var ev := InputEventMouseButton.new()
			ev.pressed = true
			ev.button_index = MOUSE_BUTTON_LEFT
			_main._election_panel._gui_input(ev)
			return false
		if _frame < _frames_wanted + 2:
			return false
		if not _write_frame(_final_path(), "tally settled"):
			return true
		quit(0)
		return true

	if not _write_frame(_out_path, ""):
		return true
	quit(0)
	return true


## Grabs the framebuffer and saves it. Returns false (having quit) when the
## grab failed -- run windowed, not --headless.
func _write_frame(path: String, note: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null:
		printerr("no framebuffer -- run windowed, not --headless")
		quit(1)
		return false
	var error := image.save_png(path)
	if error != OK:
		printerr("could not write %s: %d" % [path, error])
		quit(1)
		return false
	var suffix := " (%s)" % note if note != "" else ""
	print("wrote %s (%dx%d)%s" % [ProjectSettings.globalize_path(path), image.get_width(), image.get_height(), suffix])
	return true


## The settled tally's own file, beside the mid-fill one.
func _final_path() -> String:
	return _out_path.get_basename() + "_final.png"


## Drives the map through its public surface rather than synthesising input:
## set_layer() and the hover fields are the same methods the legend and a
## headless test use, so this tool captures the real code path.
func _apply_view() -> void:
	if _main == null or _main._map_view == null:
		return
	if _zoom > 0.0:
		# The camera surface the minimap and the headless tests drive, via the
		# tool's usual reach into _main; zoom_by() would need an anchor in
		# screen space, and a capture wants an absolute zoom anyway.
		_main._map_view._zoom = clampf(_zoom, _main._map_view.min_zoom(), _main._map_view.MAX_ZOOM)
		if _has_center:
			_main._map_view.center_on_lonlat(_center_lon, _center_lat)
		else:
			_main._map_view.center_on_lonlat(2.35, 48.86)
	if _flows and _layer == "":
		# Routed through --layer's own variable rather than calling set_layer()
		# here, so the flag also gets that path's legend sync: the legend's
		# road/ferry key is one of the things a flows frame exists to judge, and
		# a legend left on POLITICAL over a TRADE map would be the frame lying.
		_layer = "trade"
	if _coerce:
		_impose_a_spread()
	if _orgs:
		_open_the_council()
	if _council_frame != "":
		_stage_contested_council()
	if _agenda:
		_run_the_agenda()
	if _programme != "":
		_choose_a_programme()
	if _defence:
		_stand_up_an_alliance()
	if _book:
		_fill_the_diary()
	if _summit:
		_stage_a_summit()
	if _interrupt:
		_stage_an_interrupt()
	if _subsidy:
		_subsidise_a_firm()
	if _regulate:
		_regulate_a_sector()
	if _nationalise:
		_nationalise_a_firm()
	if _outliner:
		_stage_the_outliner()
	if _settings:
		_main._settings_panel.show()
	if _bid:
		_open_a_bid()
	if _failing:
		_fail_a_major()
	if _tax:
		_open_the_tax_code()
	if _compose:
		_draft_a_bill()
	if _pmb:
		_lobby_a_bill()
	if _corrupt:
		_corrupt_the_state()
	if _migrate:
		_tighten_migration()
	if _unrest:
		_provoke_the_unions()
	if _press:
		_muzzle_the_press()
	if _cycle:
		_run_into_a_recession()
	if _inflate:
		_overheat_the_economy()
	if _downgrade:
		_lose_the_markets()
	if _redistribute:
		_soak_the_rich()
	if _invest:
		_back_the_biggest_sector()
	if _build:
		_break_ground()
	if _region:
		_open_the_partition()
	if _election:
		_stage_the_election()
	if _tally:
		_stage_the_tally()
	if _diverge:
		_let_the_regions_diverge()
	if _network:
		_show_the_network()
	if _energy:
		_show_the_energy()
	if _place:
		_place_the_plants()
	if _move:
		_let_the_people_move()
	# V2.6b2: the campaign stages BEFORE --site zooms, so --campaign --site photographs
	# the ring that is actually on the map -- the meeting city of an effort in the
	# field -- rather than ticking past the staged run-up to find a demonstration.
	if _campaign:
		_open_the_campaign()
	if _site:
		_site_the_demonstration()
	if _city:
		_point_at_the_capital()

	if _pledge:
		_make_and_break_a_promise()
	if _referendum:
		_call_a_referendum()
	if _electoral:
		_reform_the_ballot()
	if _senate:
		_lose_the_senate()
	if _court:
		_lose_the_court()
	if _event:
		_put_a_crisis_on_the_desk()
	if _climate:
		_put_a_sited_crisis_on_the_desk()
	if _event_answered:
		_answer_a_crisis()
	if _nation != "":
		# Through main.gd's own click path rather than by poking the panel, so the
		# frame captures what a click produces.
		_main._on_nation_clicked(_nation)
	if _open != "":
		_main._windows.open(_open)
		# B14: open() silently no-ops on an id that was never registered, so a
		# stale help-text id photographed the plain map while the operator
		# believed they had captured a surface. The frame is still written --
		# evidence is evidence -- but the empty capture is made unmissable.
		if not _main._windows.is_open(_open):
			push_error("screenshot: --open '%s' matched no registered window; valid ids: %s" % [
				_open, ", ".join(PackedStringArray(_main._windows.panel_ids())),
			])
	# After --open: the domain's first tab replaces whatever --open opened.
	if _domain != "":
		_main._hud.sidebar.navigate.emit(_domain)
	if _layer != "":
		_main._map_view.set_layer(_layer)
		# WITH the state and the viewer, exactly as main.gd:733 calls it. Without
		# them the trade branch of show_layer() falls back to MapLayers.stops(),
		# whose TRADE entry is a deliberately empty literal because that layer's
		# stops are DERIVED from the viewer's partner count -- so every --layer
		# trade frame this tool ever took photographed a ramp legend with no ramp
		# rows in it, which is not the legend a player sees. Inherited from V1.3f.
		_main._hud.map_legend.show_layer(
			_main._map_view.layer(), _main._state, _main._map_view.viewer_id()
		)
	# EVERY setup flag above writes sim state behind panels that have already
	# refreshed, and a panel refreshes once per dirty flag. Hiding a window frame
	# does NOT clear the child panel's own `visible`, so every panel consumes its
	# one refresh on frame 1 and never rebuilds -- --defence --open budget showed an
	# em dash against a live 0.498 bill for exactly that reason, and --coerce and
	# --orgs have been getting away with it only because they open a panel whose
	# figures they happen not to change. Marked here, in main.gd's own idiom.
	_mark_panels_dirty()
	if _hover != "":
		_main._map_view._hovered_id = _hover
		_main._map_view.queue_redraw()
		_main._hud.map_legend.show_hover(
			_hover, _main._state, _main._map_view.viewer_id()
		)
	if _hover_project != "":
		# Set on the control the way --hover does, because a marker layer is the
		# one thing a headless suite structurally cannot check and a hover state
		# no flag can reach is a frame nobody ever looks at.
		_main._map_view._hovered_project = _hover_project
		_main._map_view.queue_redraw()
	if _hover_outline != "":
		_stage_outline_hover()
	if _tip != "":
		_stage_tip()
	if _blank != "":
		_blank_a_window()
	if _termlimit:
		_serve_out_the_last_term()
	if _defeated:
		_lose_the_office()


## Tick the world forward until the nine have acted enough to fill the message
## column, then card what they did. V1.3f.
##
## Through main.gd's own monthly path rather than by pushing cards directly: the
## thing being looked at is whether the filter in _card_foreign_acts() lets
## anything through and whether the column overflows its slot, and a tool that
## called push() itself would capture a frame the game cannot produce.
##
## Runs the clock's callback rather than the clock, because the clock advances on
## real time and a screenshot tool has a handful of frames.
func _run_the_agenda() -> void:
	var state = _main._state
	if state == null:
		return
	_tick_months(48)


## V4.1. Through Programme.choose() itself -- the command path the panel's CHOOSE
## button drives -- rather than by poking the register, so the frame is evidence
## of what a choice produces (the strip lights, the bars fill, the Overview rows
## appear). A handful of months first so the register has live progress to read.
## The id is the tool's argument, so no surface hand-writes it.
func _choose_a_programme() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	var result: Dictionary = Programme.choose(state, ns, _programme, _main._loader)
	if not result.get("applied", false):
		printerr("--programme: choose('%s') refused: %s" % [_programme, result])
		return
	_tick_months(3)


## One measure at each legend stop, so the captured frame shows the whole ramp
## rather than one point on it. Written straight into the register, the way
## tools/coercion_probe.gd does -- this is a dev tool looking at pixels, not a
## test of the command path, and going through Diplomacy.execute() would tie the
## severities to whatever the shipped verbs happen to use.
## V1.3g. A new game has no pact and no deployment, so a frame of the nation panel
## shows one "Alliance: none" caption and an em dash on the budget panel, and proves
## nothing about the rows that matter. Same argument --coerce, --orgs and --agenda
## each made; this is the fourth time.
##
## Stands up BOTH kinds of commitment, because they are the two things the panel has
## to be able to tell apart: a chosen deployment the player may end, and an obliged
## one they may not. The obliged half is produced the way the game produces it --
## somebody else's measure lands on an ally and the reconciler opens it -- rather
## than by writing the register, so the frame captures a state the game can reach.
func _stand_up_an_alliance() -> void:
	var state = _main._state
	if state == null:
		return
	var viewer: String = _main._map_view.viewer_id()

	var chosen := "DEU" if viewer != "DEU" else "ITA"
	var obliged := "ITA" if viewer != "ITA" and chosen != "ITA" else "ESP"
	var aggressor := "GBR" if viewer != "GBR" else "CHE"

	for ally in [chosen, obliged]:
		if state.nations.has(ally):
			Defence.sign_pact(state, viewer, String(ally), _PactStub.new())

	if state.nations.has(chosen):
		Defence.open_deployment(state, viewer, chosen, DefenceK.DEPLOYMENT_CHOSEN, null)
	if state.nations.has(obliged) and state.nations.has(aggressor):
		state.measures[Relations.directed_key(aggressor, obliged)] = _terms(state, "tariff", 0.6)

	# The real reconciler, so the obliged entry and both prices are the ones the
	# monthly tick would have produced.
	Defence.tick_month(state)
	Budget.recompute(state, state.player())
	_main._map_view.queue_redraw()


class _PactStub:
	var id: String = "screenshot_pact"
	var action_name: String = "Defensive Pact"


## V1.4a. Subsidises the player's largest firm through the panel's OWN command path
## -- Companies.execute() with a shipped verb -- rather than by writing the register,
## because the thing being looked at is a row the panel draws from a real result.
##
## Then runs two years of months so the share has actually moved: at the measured
## rate the firm is 90 % of the way to its endpoint at 25 months, and a frame taken
## the instant the button is pressed shows a subsidy standing against figures that
## have not answered it yet.
func _subsidise_a_firm() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	var action = null
	for a in loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "subsidise":
			continue
		if action == null or float(a.effects["company"]["intensity"]) > float(action.effects["company"]["intensity"]):
			action = a
	if action == null:
		return

	var best := ""
	var best_output := -1.0
	for company in Companies.firms_of(loader, ns.id):
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_output:
			best_output = out
			best = String(company.id)
	if best == "":
		return

	Companies.execute(state, ns, loader.company_actions, action, best, loader)
	# V1.4a's own note lived here: twenty-four ticked months were being captured under
	# a top bar still showing the starting GDP, because a hand-rolled month loop moves
	# the simulation and not the clock. _tick_months() now drives the real clock, so
	# the top bar AND the date agree with the figures -- see its header for the half
	# V1.4a's fix did not reach.
	_tick_months(24)


## V1.4b. Two rules in opposite directions on two different sectors, so the frame
## carries both captions the sector heading can draw -- a regulated industry and a
## deregulated services -- rather than one of them twice.
##
## Through Legislature.apply() rather than propose(), for the reason the balance
## harness gives: whether the chamber agrees is a different question from whether
## the panel draws the burden, and a capture flag that silently produced nothing on
## the months it did not is exactly the class of bug this tool exists to find.
## V1.5a. Passes the corruption-raising law twice, so the level is well clear of the
## rounding the panel prints, then ticks two years for the stock to travel. Through
## Legislature.apply() rather than by writing ns.corruption, so the frame is evidence
## about the channel and not only about the label.
func _corrupt_the_state() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	for law in loader.laws:
		if float(law.effects.get("society", {}).get("corruption", 0.0)) > 0.0:
			Legislature.apply(state, ns, law, loader)
			Legislature.apply(state, ns, law, loader)

	_tick_months(24)


## V1.5b. Passes every migration-tightening law twice, then ticks four years -- longer
## than --corrupt's two, and for a reason worth stating: corruption moves the delivery
## factor the month it passes, where a migration stance moves a SHARE that then has to
## move the ratio that then has to move the stock. Three lags in series need a horizon,
## and a flag that captured a frame before the last of them had moved would be the
## measuring-the-wrong-state error this tool has now found twice.
func _tighten_migration() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	for law in loader.laws:
		if float(law.effects.get("society", {}).get("migration", 0.0)) < 0.0:
			Legislature.apply(state, ns, law, loader)
			Legislature.apply(state, ns, law, loader)

	_tick_months(48)


## V1.5c. Cut every service the mobilised blocs care about, then run the clock until the
## unions have actually walked out.
##
## The horizon is the longest of any flag here and it has to be, for --migrate's reason
## one step further along: a grievance is a STOCK converging at UNREST_CONVERGENCE on a
## target that is itself built out of satisfactions that have to move first, so the
## chain is budget -> issue -> hardship -> stock -> threshold -> act -> card. The probe
## measures the first act under this budget at around month 36, so a flag that captured
## a frame at 24 would show a live grievance and an empty message column and prove
## nothing about the half of this session that is an agent.
func _provoke_the_unions() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	# balance_probe.gd's `austerity` deltas, which is the regime the probe's own bands
	# are measured against -- so the frame shows a state the measurement describes
	# rather than one invented for the screenshot.
	var lines := {}
	for pair in [["health", -2.5], ["education", -2.0], ["defence", -1.0], ["pensions", -3.5], ["infrastructure", -2.0]]:
		lines[pair[0]] = maxf(float(ns.start_spending_pct_gdp.get(pair[0], 0.0)) + float(pair[1]), 0.0)
	Budget.commit(state, {
		"spending_pct_gdp": lines,
		"tax_rates_pct": {
			"income": float(ns.start_tax_rates_pct["income"]) + 6.0,
			"corporate": float(ns.start_tax_rates_pct["corporate"]) + 5.0,
			"vat": float(ns.start_tax_rates_pct["vat"]) + 4.0,
		},
	})

	_tick_months(48)


## V1.6a. Ticks forward to the month France is deepest in a SLUMP, so a frame of the
## economy panel or the budget panel shows the cycle doing something.
##
## Exists for --coerce's reason: a frame of a channel sitting at its epoch zero proves
## nothing about it. And unlike every other setup flag on this list it commits NO BUDGET
## AT ALL -- the row it captures is *recessions arriving whether or not deserved*, so a
## flag that provoked one with a budget would be photographing the wrong mechanic.
##
## The trough is FOUND rather than guessed: src/sim/cycle.gd is a pure function of the
## clock, so the worst month can be read off it before the run starts. That is the same
## property the forecast band on src/ui/budget_panel.gd rests on, exercised from the
## other end.
## Run the economy hot until the price level has moved, and capture THAT. V1.6b.
##
## The flag exists for the reason --orgs and --unrest do: the readout is a DEVIATION
## against the nation's own start, so it reads exactly +0.0 on a new game and a frame
## of that proves nothing about the line, the sign or the thirteenth issue's place on
## the polling agenda.
##
## Through Budget.commit() rather than by writing ns.inflation_pct, because that field
## has exactly ONE writer and tests/test_inflation.gd fails if a second appears -- a
## tool that poked it directly would capture a state the model cannot reach. Which also
## means the frame is honest about how SMALL the reachable movement is: the probe
## measures 0.145 points, so the caption moves by a tenth and the panel has to be
## legible at that size or the line is not doing its job.
## V1.6c. Run the debt up until the bond market notices, so the economy panel's new
## caption is photographed saying something.
##
## THE MONTH COUNT IS THE WHOLE FLAG, and both directions of getting it wrong are already
## on this project's record. V1.4c's flags ticked without advancing the real clock, so
## the date read 01 JAN 2026 beside figures that had moved; V1.6b's --inflate ticked 48
## months and ran PAST the thing it exists to photograph, because the demand impulse was
## spent. Here the failure would be a frame in which the rating still reads the letter
## every game opens on, which proves the caption compiles and nothing else.
##
## 40 months is measured rather than guessed: tools/credit_probe.gd table (i) puts
## `hands_off` into BB+ at month 64 and a spendthrift budget gets there sooner, so this
## clears the opening band with room and stops well short of the spiral that would put
## the panel on a figure no player reaches.
func _lose_the_markets() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	Budget.commit(state, {
		"spending_pct_gdp": {
			"health": float(ns.start_spending_pct_gdp["health"]) + 3.0,
			"pensions": float(ns.start_spending_pct_gdp["pensions"]) + 3.5,
			"infrastructure": float(ns.start_spending_pct_gdp["infrastructure"]) + 2.5,
		},
		"tax_rates_pct": {
			"income": maxf(0.0, float(ns.start_tax_rates_pct["income"]) - 6.0),
			"corporate": maxf(0.0, float(ns.start_tax_rates_pct["corporate"]) - 7.0),
		},
	})
	_tick_months(40)


## V1.6d. Both new taxes and a steeper income schedule, then eighteen months.
##
## THE MONTH COUNT IS THE THING TO GET RIGHT AND BOTH FAILURE DIRECTIONS ARE ON THIS
## PROJECT'S RECORD. V1.4c found every flag ticking without advancing the clock, so the
## date read 01 JAN 2026 beside figures that had moved; V1.6b found `--inflate` ticking
## PAST the thing it exists to photograph. Here the readout is the budget panel's
## inequality row, which responds to the commit IMMEDIATELY through the policy offset --
## the offset is a pure read, not a stock -- so a long run is not needed and would only
## let Demography's own drift muddy the figure the flag exists to show. Eighteen months
## is enough for the clock to be visibly elsewhere and short of the 2028 election.
func _soak_the_rich() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	Budget.commit(state, {
		"tax_rates_pct": {
			"capital_gains": float(ns.start_tax_rates_pct["capital_gains"]) + 12.0,
			"wealth": float(ns.start_tax_rates_pct["wealth"]) + 0.8,
		},
		"tax_progressivity": TaxK.PROGRESSIVITY_BASE + 0.6,
	})
	_tick_months(18)
	# *** AND THE PANEL HAS TO BE RE-SYNCED, WHICH IS THE THIRTEENTH SCREENSHOT PASS'S
	# FIND. *** budget_panel.gd captures `_pending` in setup() and refreshes FROM it, so a
	# budget committed by anything other than its own sliders leaves the panel showing the
	# pre-commit position in the lever column AND offering it back as the "proposed"
	# column -- the first frame of this flag showed capital gains at 30.0 against a live
	# 42.0, and a proposal that would have UNDONE the budget the flag had just committed.
	#
	# This is a live bug and not only a tool one: Legislature.apply() commits tax changes
	# the same way, so a law passing while the budget window is open does exactly this.
	# Fixing it properly is a design call this session is not the place for -- what
	# happens to a player's half-finished edits when a law lands underneath them? -- so
	# the tool re-syncs and the bug is written down. See docs/tax-model.md section 11.
	if _main._budget_panel != null:
		_main._budget_panel.setup(_main._state, _main._loader)


func _overheat_the_economy() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	Budget.commit(state, {
		"spending_pct_gdp": {
			"health": float(ns.start_spending_pct_gdp["health"]) + 2.0,
			"infrastructure": float(ns.start_spending_pct_gdp["infrastructure"]) + 1.5,
			"education": float(ns.start_spending_pct_gdp["education"]) + 1.0,
		},
		"tax_rates_pct": {
			"income": maxf(0.0, float(ns.start_tax_rates_pct["income"]) - 3.0),
			"vat": maxf(0.0, float(ns.start_tax_rates_pct["vat"]) - 2.0),
		},
	})
	# 18 months, not 48, and that is the second half of the same finding. The demand
	# impulse has a 6.6-month half-life and is spent after three years, so by month 48
	# unemployment is back at its structural rate, inflation has converged back to the
	# anchor and the frame captures a deviation of zero -- a flag that ticks PAST the
	# thing it exists to photograph. The peak is around a year and a half in.
	_tick_months(18)


func _run_into_a_recession() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	var worst_month := 24
	var worst := 0.0
	for m in range(6, 120):
		var v: float = Cycle.impulse_pct(ns, state.year + int(m / 12), (m % 12) + 1)
		if v < worst:
			worst = v
			worst_month = m
	_tick_months(worst_month)


## Put the press under state oversight and run the clock far enough for the framing to
## reach a bloc row. V1.5d.
##
## Through Legislature.apply() rather than by writing ns.press_freedom, because that
## field has exactly ONE writer and a tool that poked it directly would capture a state
## the game cannot produce -- the same reason _corrupt_the_state() passes a law.
##
## Provokes first and only then censors, which is what makes the frame worth looking at:
## `emergency_broadcasting_powers` is gated on unrest_pct >= 35, so a calm France cannot
## reach it at all, and a screenshot of a law nobody can pass proves nothing about the
## panel. The regime is balance_probe.gd's `managed_then_austerity`, the one V1.5c
## established is REACHABLE -- govern well, win, then provoke.
func _muzzle_the_press() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	Budget.commit(state, {
		"spending_pct_gdp": {"defence": maxf(float(ns.start_spending_pct_gdp.get("defence", 0.0)) - 1.4, 0.0)},
		"tax_rates_pct": {"vat": float(ns.start_tax_rates_pct["vat"]) + 3.0},
	})
	_tick_months(20)

	var lines := {}
	for pair in [["health", -2.5], ["education", -2.0], ["defence", -1.0], ["pensions", -3.5], ["infrastructure", -2.0]]:
		lines[pair[0]] = maxf(float(ns.start_spending_pct_gdp.get(pair[0], 0.0)) + float(pair[1]), 0.0)
	Budget.commit(state, {
		"spending_pct_gdp": lines,
		"tax_rates_pct": {
			"income": float(ns.start_tax_rates_pct["income"]) + 6.0,
			"corporate": float(ns.start_tax_rates_pct["corporate"]) + 5.0,
			"vat": float(ns.start_tax_rates_pct["vat"]) + 4.0,
		},
	})
	_tick_months(40)

	for law in _main._loader.laws:
		if law.id == "broadcasting_oversight_act":
			Legislature.apply(_main._state, ns, law, _main._loader)
			break
	_tick_months(12)


func _regulate_a_sector() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	# Industry twice and services once, and the counts are not arbitrary. One rule
	# each way came out at "-0.000 pts unemployment" on the ledger: industry's 186k
	# named jobs at a 0.40 burden and services' 213k at a -0.35 one shed and hire
	# within fifteen people of each other, so the frame drew both sector CAPTIONS and
	# an empty jobs ROW -- a capture that proves one of the two things it exists to
	# prove. The sixth session running in which running the tool found something.
	for law_id in ["workplace_safety_act", "workplace_safety_act", "financial_deregulation"]:
		for law in loader.laws:
			if law.id == law_id:
				Legislature.apply(state, ns, law, loader)

	_tick_months(24)


## V1.4c. Nationalises the largest firm outright, takes a minority stake in a
## second one so the frame carries both a whole holding and a partial one, and then
## regulates the sector the big one sits in -- because the jobs shield is what
## ownership buys and a shield with nothing to shield against draws a zero. That is
## V1.4b's own --regulate bug applied in advance rather than found afterwards.
##
## Through Companies.execute() with shipped verbs rather than by writing the
## register, for the reason --subsidy gives: the precondition path is part of what
## the frame is meant to prove.
func _nationalise_a_firm() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	var full = null
	var minority = null
	for a in loader.company_actions:
		if String(a.effects.get("company", {}).get("op", "")) != "nationalise":
			continue
		var stake := float(a.effects["company"]["stake"])
		if full == null or stake > float(full.effects["company"]["stake"]):
			full = a
		if minority == null or stake < float(minority.effects["company"]["stake"]):
			minority = a
	if full == null:
		return

	var ranked: Array = []
	for company in Companies.firms_of(loader, ns.id):
		ranked.append([Companies.output_eur_bn(ns, company), String(company.id), String(company.sector)])
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	if ranked.is_empty():
		return

	# The whole holding goes on the LARGEST firm, which is the row the model's claims
	# are about -- and the minority stake goes on the largest firm of the panel's
	# FIRST sector, which is the row the frame can actually show. The first draft put
	# both on the two largest, and both are services: every visible firm read
	# "private", every visible sector heading read its plain caption, and the capture
	# proved nothing about either row it exists to draw while the live figures sat in
	# the ledger above them. The register is sorted by sector on that panel and the
	# largest firms are not in the first one -- which no amount of correct state fixes.
	var head := String(ranked[0][1])
	var head_sector := String(ranked[0][2])
	var first_sector := String(EK.SECTOR_TREND.keys()[0])
	var visible := ""
	for row in ranked:
		if String(row[2]) == first_sector:
			visible = String(row[1])
			break

	Companies.execute(state, ns, loader.company_actions, full, head, loader)
	if minority != null and minority != full and visible != "":
		Companies.execute(state, ns, loader.company_actions, minority, visible, loader)

	# The burden the shield is there to absorb, on BOTH sectors: the wholly-owned
	# firm's, because that is where the shield is total, and the visible one's,
	# because a sector caption the frame cannot reach proves nothing.
	for law in loader.laws:
		if law.theme != "business":
			continue
		var sector := String(law.effects.get("company", {}).get("sector", ""))
		if sector != head_sector and sector != first_sector:
			continue
		if float(law.effects["company"].get("burden", 0.0)) <= 0.0:
			continue
		Legislature.apply(state, ns, law, loader)

	_tick_months(24)


## V4.7b B4, for --bid. Writes the bid's three scalars exactly as
## industry.gd::_bids writes them, on the largest major an eligible foreign
## bidder would actually target (same sector, larger live share -- the machine's
## own eligibility, so the frame shows a bid the machine could have opened).
## NOT followed by _tick_months: the bid window is 3 months and the machine
## ticks it down -- a capture staged and then ticked lapses the very row it
## exists to show. The panel's block/allow row and the brass cluster mark read
## the register directly, so nothing else is needed to make them speak.
func _open_a_bid() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	var ranked: Array = []
	for company in Companies.majors_of(loader, ns.id):
		ranked.append([Companies.share_of_company(ns, company), String(company.id), String(company.sector)])
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	if ranked.is_empty():
		return

	for row in ranked:
		var target_id := String(row[1])
		var target_sector := String(row[2])
		var live: float = float(row[0])
		var eligible: Array = []
		for other_id: String in state.nations.keys():
			if other_id == ns.id or other_id == state.player_nation_id:
				continue
			for other in Companies.majors_of(loader, other_id):
				if other.sector != target_sector:
					continue
				if bool(state.nations[other_id].companies.get(other.id, {}).get("failed", false)):
					continue
				if Companies.share_of_company(state.nations[other_id], other) > live:
					eligible.append(other_id + "|" + other.id)
		if eligible.is_empty():
			continue
		eligible.sort()
		var entry: Dictionary = ns.companies[target_id]
		entry["bid_bidder"] = eligible[0]
		entry["bid_price_eur_bn"] = Companies.value_eur_bn(ns, _firm_by_id(loader, ns.id, target_id))
		entry["bid_months_left"] = IndustryK.BID_WINDOW_MONTHS
		return


## V4.7b B4, for --failing. Writes the failure exactly as industry.gd::_failures
## commits it -- all nine writes: `failed`, `share` 0.0 to the unnamed
## residual, the support stopped, the foreign interest dead (bid scalars AND
## the courtship), the seat vacated, and the rescue window (the pass-2 zombie fix and the pass-4 ghost-bid fix are part of the
## commit; --subsidy --failing composition stages on the same largest firm,
## so the subsidy clear is what keeps the frame a state the machine could
## produce) -- on the largest major, which is the payroll the failing-majors
## section prices most loudly. NOT followed by _tick_months for the reason
## _open_a_bid states: the window lapses, and a lapsed failure is a committed
## one whose row the panel does not draw.
func _fail_a_major() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	var ranked: Array = []
	for company in Companies.majors_of(loader, ns.id):
		ranked.append([Companies.output_eur_bn(ns, company), String(company.id)])
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	if ranked.is_empty():
		return
	var head := String(ranked[0][1])
	var entry: Dictionary = ns.companies.get(head, {})
	if entry.is_empty():
		return
	entry["failed"] = true
	entry["share"] = 0.0
	entry["subsidy"] = 0.0
	entry["bid_bidder"] = ""
	entry["bid_price_eur_bn"] = 0.0
	entry["bid_months_left"] = 0
	entry["courted"] = 0.0
	entry["board_chair"] = ""
	entry["rescue_months_left"] = IndustryK.RESCUE_WINDOW_MONTHS


## V4.2 close-out, for --tax. No state to stage -- _open_the_partition()'s
## shape: the register is the content and the frame is the check that the
## panel builds its rows off it.
func _open_the_tax_code() -> void:
	_main._windows.open("tax")
	# open() silently no-ops on an unregistered id -- B14's own guard, which the
	# generic --open path carries and a direct open() call must carry too.
	if not _main._windows.is_open("tax"):
		push_error("screenshot: --tax could not open the tax window")
	else:
		print("--tax: the tax window is open (%d rate rows)" % _main._tax_panel._sliders.size())


## V4.2 close-out, for --compose. The draft goes through Statute.draft()
## itself -- the machine validates, prices and parks it, so a refusal here is
## a spec bug and is made unmissable rather than photographed over -- and the
## briefing opens over the parked draft through main.gd's own handler body,
## the exact two lines the tax panel's compose flow runs (the briefing is
## main-owned; this is its one open_for_draft caller in the game). The
## legislature window is open behind it because the briefing is the only
## surface a parked draft renders on and the frame should carry the chamber
## the bill is parked FOR. NOT ticked: months_left positive is the claim.
func _draft_a_bill() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	# A moderate two-channel bill: an income rise buys a health rise. Sized
	# well under the drafting ceiling (0.675 of 6.0, so 3 months parked) and
	# priced across four blocs, which is what the briefing's price section
	# exists to show; the position is a centrist one so the bill itself makes
	# no statement the channels have not already made.
	var spec := {
		"name": "The Health and Work Act",
		"position": {"economic": 0.2, "social": 0.0},
		"channels": {
			"tax_rates_pct": {"income": 3.0},
			"spending_pct_gdp": {"health": 0.3},
		},
	}
	var result: Dictionary = Statute.draft(state, ns, loader, spec)
	if not bool(result.get("ok", false)):
		printerr("--compose: the draft was refused: %s" % String(result.get("refusal", "")))
		return

	_main._windows.open("legislature")
	_main._briefing.open_for_draft(
		ns.draft_bills[String(result["draft_id"])], String(result["draft_id"]), state, loader)
	_main._briefing.show()
	print("--compose: %s parked, size %.3f, %d months left, briefing visible: %s" % [
		String(result["draft_id"]), float(result["size"]), int(result["months"]),
		_main._briefing.visible])


## V4.2 close-out, for --pmb. The chiefs' lobby bill, every write a write the
## machine makes -- the same discipline test_industry's forced mechanics use:
##
## The lobby only fires above the burden floor, so the burden stands first --
## through the ONE applier, --regulate's own move, and the clock never moves,
## so the staged month is the frame's month and the pair (burden 0.4, easing
## law in the pool) is a state the machine reaches on an ordinary Tuesday.
func _lobby_a_bill() -> void:
	var state = _main._state
	var loader = _main._loader
	if state == null or loader == null:
		return
	var ns = state.player()

	var burden = null
	for law in loader.laws:
		if String(law.id) == "workplace_safety_act":
			burden = law
	if burden == null:
		printerr("--pmb: workplace_safety_act did not load")
		return
	Legislature.apply(state, ns, burden, loader)

	# _lobby()'s own body, minus only the hazard draw: the sector, then that
	# sector's biggest major, then the easing law the candidate pool holds,
	# into the same _table_bill() call _lobby() makes with the chief signed
	# on. The month is the machine's own absolute-month index, so the sponsor
	# draw inside the easing-law pick keys the same Cycle hash a real table
	# would.
	var sector: String = Statute._burdened_sector(ns)
	if sector == "":
		printerr("--pmb: no sector stands above the lobby floor after the burden")
		return
	var firm = Statute._biggest_major(ns, loader, sector)
	if firm == null:
		printerr("--pmb: %s has no %s major with a chief to sign the ask" % [ns.id, sector])
		return
	var month: int = Statute._abs_month(state)
	var law = Statute._burden_easing_law(ns, loader, sector, month)
	if law == null:
		# The machine's own fall-through: a fired lobby with no easing law to
		# name tables a plain backbench bill -- the same row the panel draws,
		# minus the backer line.
		Statute._table_bill(ns, loader, month)
	else:
		Statute._table_bill(ns, loader, month, String(firm.id), String(firm.chief_id), law)
	# Both staging paths converge here, and the WINDOW opens after the stage
	# (the compose stage's order): the panel's ASSEMBLY BILLS section is the
	# frame's subject, and a window opened before its state existed would
	# refresh empty and only the next dirty-mark would fill it.
	_main._windows.open("legislature")
	# The row's own three reads, printed the way the panel will resolve them:
	# a chief the loader cannot name would fall back to "the chief" on the
	# frame, and that is a console fact before it is a pixel one.
	var entry: Dictionary = ns.assembly_bills.values()[ns.assembly_bills.size() - 1]
	print("--pmb: %s tabled, %d months left, backer %s (%s), chief %s" % [
		String(entry["law_id"]), int(entry["months_left"]),
		loader.firm_name(ns.id, String(entry["backer_firm"])),
		String(entry["backer_firm"]),
		loader.person_name(String(entry["backer_chief"]))])


## The one firm lookup the two stages above need, and deliberately not a
## general helper: a capture flag that reaches firms by id is one flag, not
## an API.
func _firm_by_id(loader, nation_id: String, firm_id: String):
	for company in Companies.firms_of(loader, nation_id):
		if company.id == firm_id:
			return company
	return null


## Runs the world forward N months through the REAL clock, and the fifth flag to
## need this is the one that found why that matters.
##
## Every flag before this one hand-rolled the loop and called main.gd's
## `_on_month_elapsed()` directly, which advances the simulation and leaves the
## Clock node where it was -- so `clock_cluster.refresh(_clock)` had nothing new to
## draw and every frame with a tick loop behind it was captured under a date reading
## 01 JAN 2026. V1.4a found the same disagreement one row up, on the top bar, and
## fixed it with `_update_top_bar()`; the date underneath it stayed wrong, and
## `--agenda`, `--book`, `--subsidy` and `--regulate` have all been shipping frames
## that disagree with themselves since.
##
## Driving `advance_one_day()` fixes it at the source rather than by refreshing a
## second widget: main.gd connects both clock signals in `_ready()`, so this is the
## path a played game takes, day resolution and all. U6a's dispatch runs here too,
## which no hand-rolled month loop ever exercised.
func _tick_months(months: int) -> void:
	if _main == null or _main._clock == null:
		return
	# Absolute month index rather than a (year, month) pair, so the loop cannot walk
	# past its target on a December rollover and run for a further eleven months.
	var target: int = _main._clock.year * 12 + _main._clock.month + months
	while _main._clock.year * 12 + _main._clock.month < target:
		_main._clock.advance_one_day()

	# Two years of the real clock cross a real election, and main.gd answers one by
	# opening the result screen over everything and pausing -- so the first frame
	# captured through this helper was a modal on top of the panel the flag had just
	# set up. The hand-rolled loops never saw it. Dismissed the way the Continue
	# button does, because a capture aimed at a window wants that window.
	if _main._election_panel != null and _main._election_panel.visible:
		_main._election_panel.hide()
		_main._clock.paused = false
	_main._update_top_bar()


## main.gd marks these on every month elapsed; a screenshot moves state without a
## month elapsing, so it has to say so itself.
##
## V2.1a deleted the fourteen-name list that used to be here. It was a copy of
## main.gd's, made by copying it, and it drifted exactly as a copy does: V1.8
## found `_projects_panel` and `_campaign_panel` absent since V1.6f and V1.7a, so
## `--build` and `--campaign` had each been photographing a panel that refreshed
## once on frame 1 -- the same bug V1.3g had already found in this tool and fixed
## only for the panels that existed then. The registry knew all fourteen the
## whole time.
func _mark_panels_dirty() -> void:
	_main._windows.mark_all_dirty()


## V2.9, the twenty-ninth flag: the election result is the one modal moment and
## this is the only way to photograph it -- ticked to May 2027 with the modal
## LEFT OPEN (the _tick_months helper dismisses it, by design, for every other
## flag). The dim backdrop and the verdict-first ordering are the frame's claims.
func _stage_the_election() -> void:
	if _main == null or _main._clock == null:
		return
	var target: int = _main._clock.year * 12 + _main._clock.month + 16
	while _main._clock.year * 12 + _main._clock.month < target:
		_main._clock.advance_one_day()
	_main._update_top_bar()


## V3.6: 41 months, the June 2029 double election -- the first plate with seat
## bars, so the one the tally exists on. The May 2027 presidential result fires
## on the way (the advance is manual, it does not stop for the pause) and its
## plate is replaced, which is the same read a player gets.
func _stage_the_tally() -> void:
	if _main == null or _main._clock == null:
		return
	var target: int = _main._clock.year * 12 + _main._clock.month + 41
	while _main._clock.year * 12 + _main._clock.month < target:
		_main._clock.advance_one_day()
	_main._update_top_bar()


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
## pixels, and going through the council's own schedule (an opening every
## PROPOSAL_INTERVAL_MONTHS, then VOTE_DELAY_MONTHS to a division) would mean
## capturing months into the run.
func _open_the_council() -> void:
	var state = _main._state
	if state == null or state.orgs.is_empty():
		return

	# V3.2: the first council org, sorted -- the tool stages ONE council view and
	# does not care which, so it takes the register's own order rather than
	# naming an id (an id here would be the cardinal sin in a dev tool, where it
	# would at least be honest about being one).
	var org_id: String = Orgs.council_ids(state)[0]
	var agenda: Array = _main._loader.org_proposals.get(org_id, [])
	if agenda.is_empty():
		return

	var proposal = null
	var pending = null
	for p in agenda:
		if not p.constraint.is_empty() and proposal == null:
			proposal = p
		elif pending == null:
			pending = p
	if proposal == null:
		return

	state.orgs[org_id]["rules"][proposal.id] = {
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
		state.orgs[org_id]["pending"] = {
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
	# three-"None"-captions frame --orgs was added to stop capturing.
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
	for p in agenda:
		if p.id == proposal.id or (pending != null and p.id == pending.id):
			continue
		if fallback == null:
			fallback = p
		# Divided ON THE VOTE, not only on the reason. A proposal every member backs
		# for the same reason is a frame of one camp; a proposal they split on shows
		# what the section is for even when the reason is the same word.
		var seen_for := false
		var seen_against := false
		for id in Orgs.members(state, org_id):
			if Orgs.support(state, state.nations[id], p) >= BlocK.SUPPORT_THRESHOLD:
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
		for id in Orgs.members(state, org_id):
			var seats: int = Orgs.live_seats(state, org_id, id)
			seats_total += seats
			var backs: bool = Orgs.support(state, state.nations[id], divided) >= BlocK.SUPPORT_THRESHOLD
			votes[id] = Orgs.VOTE_FOR if backs else Orgs.VOTE_AGAINST
			reasons[id] = Orgs.vote_reason(state, state.nations[id], divided)
			if backs:
				seats_for += seats
			else:
				seats_against += seats
		state.orgs[org_id]["last_vote"] = {
			"proposal_id": divided.id, "name": divided.proposal_name,
			"org_id": org_id,
			"passed": float(seats_for) >= BlocK.PASS_SEAT_FRACTION * float(seats_for + seats_against),
			"seats_for": seats_for, "seats_against": seats_against,
			"seats_total": seats_total,
			"player_vote": String(votes.get(state.player_nation_id, "abstain")),
			"votes": votes, "reasons": reasons,
			"year": state.year, "month": state.month,
		}

	# So the burden, the penalty line and the breach caption are all non-zero.
	Orgs.tick_month(state, _main._loader)

	_main._windows.open("orgs")
	if _main._orgs_panel != null:
		_main._orgs_panel.mark_dirty()


## V4.5b2 T7. The contested council's four states, staged through the real sim
## commands (cast_vote, Council.bargain, set_agenda); the register is written
## directly only where no command creates the thing (a pending division, a
## ratifying treaty, a last_vote, an IOU awaiting a treaty) -- the way
## tests/test_orgs_panel.gd stages them. Proposals are named by id: this is a
## dev tool looking at one authored state, and the ids are the content it frames.
func _stage_contested_council() -> void:
	var state = _main._state
	var loader = _main._loader
	var org := "eu"
	if state == null or not state.orgs.has(org):
		return
	var player: String = state.player_nation_id
	var register: Dictionary = state.orgs[org]
	var others: Array = []
	for id in Orgs.members(state, org):
		if String(id) != player:
			others.append(String(id))
	others.sort()

	match _council_frame:
		"sponsored":
			var p = Orgs.proposal_by_id(loader, org, "investment_floor")
			if p == null:
				return
			var sponsor: String = p.sponsor
			register["pending"] = {
				"proposal_id": p.id, "name": p.proposal_name, "summary": p.summary,
				"org_id": org, "org_name": loader.orgs_by_id[org].name,
				"months_left": 2, "player_vote": Orgs.VOTE_ABSTAIN,
				"opened_year": state.year, "opened_month": state.month,
				"sponsor": sponsor,
			}
			# The sponsor's lobbying through its real path, as the opening runs it.
			var supports := {}
			for id in Orgs.members(state, org):
				if not state.nations[id].has_budget:
					supports[id] = Orgs.support(state, state.nations[id], p)
			var lobbied: Dictionary = Council.lobby(state, loader, sponsor, supports)
			if lobbied.is_empty():
				# A drive too low to turn anyone: write one so the frame still shows
				# the lobbied mark -- the layout is what this frame judges.
				for id in others:
					if id != sponsor:
						lobbied[id] = 0.1
						break
			register["pending"]["lobbied"] = lobbied
			Orgs.cast_vote(state, org, Orgs.VOTE_FOR)
			for id in others:
				if id != sponsor and not lobbied.has(id):
					Relations.adjust(state, player, id, 100.0, 0.0, 100.0)
					Council.bargain(state, org, id, CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR)
					break
		"treaty":
			var p = Orgs.proposal_by_id(loader, org, "cohesion_fund")
			if p == null:
				return
			register["pending"] = {
				"proposal_id": p.id, "name": p.proposal_name, "summary": p.summary,
				"org_id": org, "org_name": loader.orgs_by_id[org].name,
				"months_left": 2, "player_vote": Orgs.VOTE_ABSTAIN,
				"opened_year": state.year, "opened_month": state.month,
				"sponsor": p.sponsor,
			}
			# A previous division of another treaty that a veto killed.
			var q = Orgs.proposal_by_id(loader, org, "enlargement_preaccession_fund")
			var vetoers: Array = []
			for id in others:
				if id != "POL" and vetoers.size() < 2:
					vetoers.append(id)
			var votes := {}
			var reasons := {}
			for id in Orgs.members(state, org):
				var vetoes: bool = vetoers.has(id)
				votes[id] = Orgs.VOTE_AGAINST if vetoes else Orgs.VOTE_FOR
				if id != player:
					reasons[id] = Orgs.vote_reason(state, state.nations[id], q)
			register["last_vote"] = {
				"proposal_id": q.id, "name": q.proposal_name, "org_id": org,
				"passed": false, "decision": CouncilK.DECISION_UNANIMITY,
				"vetoed_by": vetoers, "sponsor": q.sponsor,
				"seats_for": 0, "seats_against": 0, "seats_total": 0,
				"player_vote": Orgs.VOTE_FOR, "votes": votes, "reasons": reasons,
				"year": state.year, "month": state.month,
			}
		"ratify":
			var p = Orgs.proposal_by_id(loader, org, "recovery_facility")
			if p == null:
				return
			register["ratifying"] = {
				"proposal_id": p.id, "name": p.proposal_name, "sponsor": p.sponsor,
				"months_left": 4, "nations": {player: CouncilK.RATIFY_PENDING},
			}
			# An IOU the player owes the sponsor, repaid only if the treaty clears.
			register["debts"] = [{
				"debtor": player, "creditor": p.sponsor,
				"made_on": state.year * 12 + state.month - 3,
				"months_left": CouncilK.IOU_EXPIRY_MONTHS, "awaiting": p.id,
			}]
		"chair":
			# Walk the calendar to a semester the player chairs rather than doing the
			# rotation's arithmetic here: presiding_nation() is the one authority.
			for i in 400:
				if Council.presiding_nation(state, loader, org) == player:
					break
				state.month += 1
				if state.month > 12:
					state.month = 1
					state.year += 1
			# The HUD clock reads the clock, not the state: move both.
			_main._clock.year = state.year
			_main._clock.month = state.month
			register["pending"] = {}
			for p in loader.org_proposals.get(org, []):
				if Orgs.set_agenda(state, loader, org, p.id):
					break
			_main._orgs_panel.set_section_open("agenda:" + org, true)

	_main._windows.open("orgs")
	if _main._orgs_panel != null:
		if _council_frame == "sponsored":
			_main._orgs_panel.set_section_open("room:" + org, true)
		_main._orgs_panel.mark_dirty()
		var scroller = _main._orgs_panel._body.get_parent()
		if scroller is ScrollContainer:
			scroller.scroll_vertical = 0
	# The top bar's Europe figure, refreshed the way main.gd does after an action.
	_main._update_top_bar()


## Fill the diary so a frame of it shows something. U6a.
##
## Three bookings and one act, because the strip draws three different things and
## a frame that only proves one of them is the class of frame --coerce exists to
## avoid: a booking in a future month, a KEPT appointment in the past (so the
## resolved styling is visible), and a cooldown expiry the player never entered,
## which is the headline -- dated state the game already carried and never showed.
##
## Through Calendar.book() and main.gd's own dispatch rather than by appending to
## the register, so the frame captures what the game produces rather than what a
## tool arranged.
func _fill_the_diary() -> void:
	var state = _main._state
	if state == null:
		return
	var loader = _main._loader
	var ns = state.player()

	# The act. Fires now, so its own cooldown becomes a future date on the strip.
	var partners: Array = state.nations.keys()
	partners.sort()
	for target_id in partners:
		if String(target_id) == ns.id:
			continue
		var acts := Diplomacy.available(state, loader.diplomatic_actions, ns.id, String(target_id))
		if acts.is_empty():
			continue
		Diplomacy.execute(state, loader.diplomatic_actions, acts[0], ns.id, String(target_id))
		break

	# A booking two months out, and a law next month.
	for spec in [
		{"months": 2, "day": 12, "kind": CalendarK.KIND_DIPLOMATIC},
		{"months": 1, "day": 19, "kind": CalendarK.KIND_LAW},
	]:
		var total: int = state.year * 12 + (state.month - 1) + int(spec["months"])
		var year: int = total / 12
		var month: int = total % 12 + 1
		if String(spec["kind"]) == CalendarK.KIND_LAW:
			var laws := Legislature.available(ns, loader.laws)
			if not laws.is_empty():
				Calendar.book(state, Calendar.make_entry(
					CalendarK.KIND_LAW, year, month, int(spec["day"]),
					"", "", String(laws[0].id)
				))
			continue
		for target_id in partners:
			if String(target_id) == ns.id:
				continue
			var acts := Diplomacy.available(state, loader.diplomatic_actions, ns.id, String(target_id))
			if acts.is_empty():
				continue
			# U6b: the person the visit actually meets, resolved the way
			# calendar_panel.gd resolves it at booking time. Without this the frame
			# proves nothing about the new label -- a capture of a field nobody
			# filled in is the pre-mutation frame V1.3g found in this same tool.
			# V2.4a: the booking carries its travel days, priced the way the panel
			# prices them, so the ribbon shows a hatched block and the diary shows
			# the span -- a frame of the meeting day alone proves nothing about
			# either.
			Calendar.book(state, Calendar.make_entry(
				CalendarK.KIND_DIPLOMATIC, year, month, int(spec["day"]),
				String(acts[0].id), String(target_id), "", "", "",
				String(loader.nations[String(target_id)].leader_person_id),
				Diplomacy.travel_days(loader, ns.id, String(target_id))
			))
			break

	# One already kept, dated a fortnight ago, so the resolved styling is in the
	# frame too. Appended directly and resolved: a past date cannot be booked
	# through book(), which is the refusal the panel test asserts.
	var kept := Calendar.make_entry(
		CalendarK.KIND_RESHUFFLE, state.year, state.month, maxi(int(state.day) - 14, 1),
		"", "", "", "health", String(ns.coalition_party_ids[0]) if not ns.coalition_party_ids.is_empty() else ""
	)
	state.appointments.append(kept)
	Calendar.resolve(state, Calendar.verb_key(kept), true)


## V2.4b. A state visit lands, the scene opens over it: the window the player
## sees at arrival, with the leader's portrait and the first line on it. The
## arrival runs the REAL dispatch path (execute, resolve, open) so the frame
## proves the chain, not a panel fed by hand.
func _stage_a_summit() -> void:
	var state = _main._state
	var loader = _main._loader
	var ns = state.player()
	var visit = null
	for action in loader.diplomatic_actions:
		if String(action.id) == "state_visit":
			visit = action
	if visit == null:
		push_error("--summit: no state_visit content")
		return
	# A meeting two months out, kept by the same path the day tick uses --
	# execute() applies its effects and stamps the meeting register.
	Diplomacy.execute(state, loader.diplomatic_actions, visit, ns.id, "DEU")
	_main._open_summit("DEU", Budget.snapshot(state))
	_main._windows.mark_all_dirty()


## V2.4b. The one crisis that stops the clock: announced through the real
## register, then the same enforce call the load path and the month tick use,
## so the frame shows the Dispatches window OPEN and the clock PAUSED -- a
## capture of a pending event with the clock still running would prove the
## opposite of the flag's name.
func _stage_an_interrupt() -> void:
	var state = _main._state
	var loader = _main._loader
	var ns = state.player()
	var crisis = null
	for e in loader.events:
		if String(e.id) == "blackout_night":
			crisis = e
	if crisis == null:
		push_error("--interrupt: blackout_night did not load")
		return
	# The announce signature grew the month and the name map at V3.5; blackout_night
	# is non-sited, so both are inert -- filled exactly as tick_month fills them.
	Events.announce(ns, crisis, Events._absolute_month(int(state.year), int(state.month)),
		Events.region_names(ns, loader))
	_main._enforce_interrupt()
	_main._windows.mark_all_dirty()


## Force the executive verdict the player loses on, and show the result screen the
## way main.gd shows it. V1.6 playability audit, finding V2.
##
## resolve_executive() is called for real and only `incumbent_largest` is flipped:
## the panel's `defeated` test reads that field and `ns.in_government`, so forcing
## those two is the whole of the difference between winning and losing. Every other
## figure on the plate is the one the real election produced.
##
## The clock is paused here rather than left running because main.gd pauses on any
## result -- and the frame is evidence about a screen the player cannot dismiss, so
## capturing it beside a running clock would misrepresent the state they are in.
func _lose_the_office() -> void:
	if _main == null or _main._election_panel == null:
		return
	var state = _main._state
	var ns = state.player()
	var party_list: Array = _main._loader.parties.get(ns.id, [])

	var result := Elections.resolve_executive(ns, party_list, state.year, state.month)
	result["incumbent_largest"] = false
	ns.in_government = false

	_main._clock.paused = true
	_main._election_panel.show_results([result])
	_main._election_panel.show()


## Press a panel's own Close button, then reopen its window. V1.6 playability
## audit, finding V3.
##
## Drives the real Button rather than calling hide() directly, because the claim
## being photographed is about what a click does -- calling hide() would prove only
## that a hidden Control is hidden. The second open() is the capture: it is the
## action a player takes to undo the mistake, and it does not work.
func _blank_a_window() -> void:
	if _main == null or _main._windows == null:
		return
	# V2.1a deleted the id -> member table that used to sit at the top of this
	# file. Its own comment said it existed because "there is no lookup from one to
	# the other", and window_manager.gd grew one this session -- so a fifth
	# hand-written list of panel names went with it.
	var frame = _main._windows.frame(_blank)
	if frame == null or frame._content == null:
		printerr("--blank: no panel for window id %s" % _blank)
		return
	var panel = frame._content

	_main._windows.open(_blank)
	for node in _descendants(panel):
		if node is Button and node.text == "Close" and node.visible:
			node.pressed.emit()
			break
	_main._windows.open(_blank)


func _descendants(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


## Reach the term limit and let the simulation report it. V1.6 audit, V1.
##
## The dates are moved rather than the fourteen years played, because the bug was
## never about the road there: tick_month() appended nothing on this branch, so
## the plate this captures is the difference between a screen and no screen at all.
func _serve_out_the_last_term() -> void:
	if _main == null or _main._state == null:
		return
	var state = _main._state
	var ns = state.player()
	if ns.term_limit <= 0:
		printerr("--termlimit: %s has no term limit" % ns.id)
		return

	ns.terms_served = ns.term_limit
	ns.next_executive_year = state.year
	ns.next_executive_month = state.month
	# Out of the way, so only the executive branch fires and the frame shows one
	# thing rather than a legislative result stacked above it.
	ns.next_election_year = state.year + 50

	var results := Elections.tick_month(state, _main._loader)
	if results.is_empty():
		printerr("--termlimit: the term limit reported nothing -- that IS finding V1")
		return
	_main._clock.paused = true
	_main._election_panel.show_results(results)
	_main._election_panel.show()


## V1.6e. Backs the largest sector at full intensity and runs sixty months -- the
## capital's own t90 -- so the frame shows a programme that has ARRIVED rather than one
## that has just been signed.
##
## Sixty and not twenty-four, which is this flag's whole argument: every figure this
## session adds is a lag, and V1.6b's screenshot pass already found the opposite error
## (a flag that ticked 48 months and ran PAST the thing it existed to photograph). Here
## the risk is the other way round, so the horizon is the model's own time constant
## rather than a round number.
##
## No panel re-sync, unlike --redistribute, and the difference is worth stating: this
## verb does not go through Budget.commit() at all. It writes its own register and the
## cost arrives as a computed line, so budget_panel.gd's stale `_pending` -- the live bug
## docs/tax-model.md section 11 records -- cannot be reached from here.
func _back_the_biggest_sector() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	var best := ""
	var best_output := -1.0
	for sector in ns.sector_investment.keys():
		var out: float = float(ns.sector_output.get(sector, 0.0))
		if out > best_output:
			best_output = out
			best = String(sector)

	var action = null
	for a in _main._loader.investment_actions:
		var terms: Dictionary = a.effects.get("investment", {})
		if String(terms.get("op", "")) != "invest" or String(terms.get("sector", "")) != best:
			continue
		if action == null or float(terms["intensity"]) > float(action.effects["investment"]["intensity"]):
			action = a
	if action != null:
		Investment.execute(state, ns, _main._loader.investment_actions, action)
	_tick_months(60)

	# *** AND THE PANEL HAS TO BE SCROLLED, WHICH IS THE FOURTEENTH SCREENSHOT PASS'S
	# FIND. *** The first frame of this flag showed the ledger reading a live 0.654 % of
	# GDP and +0.513 %/yr -- and every visible sector row saying "No state programme",
	# because the sector the flag had just backed is the LAST of the three and sits below
	# the fold of a panel whose whole body scrolls. The figures were right and the frame
	# was still evidence for the wrong claim. Scrolled to the bottom, the services row and
	# its withdrawal button are on screen.
	#
	# This is the tool's own bug rather than the panel's: companies_panel.gd scrolls by
	# design, which is its stated answer to the fold nation_panel.gd has paid for three
	# times, and a player reaches the row by dragging.
	if _main._companies_panel != null:
		_main._companies_panel.scroll_to_bottom()


## V1.6f. Begins the two projects the content gate permits, then runs far enough for
## the SHORTER of them to open and the longer to be visibly still building -- so one
## frame carries both halves of this lever: a bill being paid for work in progress, and
## a payoff that has arrived and is still being delivered.
##
## THE HORIZON IS READ OFF THE CONTENT RATHER THAN WRITTEN HERE, and that is this
## flag's whole argument. V1.6b's pass found a flag that ticked 48 months and ran PAST
## what it existed to photograph; V1.6e's found the opposite, a flag that could have
## stopped short of the model's own time constant. A project's build length is authored,
## so a number typed here would be a third copy of it and would go stale the first time
## the ladder moved. It ticks the shortest build plus a year -- long enough for the
## payoff to be visible through economy_constants.SHIFT_ADJUST, short enough that the
## longest project is still under construction.
##
## No panel re-sync, for --invest's reason exactly: this verb does not go through
## Budget.commit() either, so budget_panel.gd's stale `_pending` cannot be reached.
## V1.7a. Ticks to the month the run-up opens, puts the two cheapest efforts into the
## field, then ticks four more months so there is an accrual to read and a bill to
## print. Through Campaign.execute() rather than by writing the register, so the frame
## shows what a click produces -- including the bloc offsets the price is made of.
##
## STOPS FOUR MONTHS SHORT OF THE VOTE, and that is deliberate. Campaign.tick_month()
## CLEARS the whole register the month the window shuts, so a flag that ticked past the
## election would photograph an empty panel and a zero bill -- V1.6b's flag ticking 48
## months and running past the thing it existed to capture, in a new place. The one
## surface where the register is visible is inside the run-up.
## The nation's regions, freshest first. tour_probe.gd's T2 measured the capital as
## the arg-max fresh factor in eight of ten nations; this is the same read, ranked.
func _ranked_sites(ns) -> Array:
	var scored := []
	for rid in ns.region_pop_share:
		scored.append({"id": String(rid), "fresh": Campaign.fresh_factor(ns, _main._loader, String(rid))})
	scored.sort_custom(func(a, b): return float(a["fresh"]) > float(b["fresh"]))
	var out := []
	for entry in scored:
		out.append(String(entry["id"]))
	return out


func _open_the_campaign() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	var to_open: int = Campaign.months_to_election(state, ns) - CampaignK.CAMPAIGN_WINDOW_MONTHS
	if to_open > 0:
		_tick_months(to_open)
	if not Campaign.is_open(state, ns):
		printerr("--campaign: the run-up did not open (%d months to the vote)" % Campaign.months_to_election(state, ns))
		return

	# Cheapest first, so the concurrency gate admits two rather than one expensive one.
	var starts: Array = []
	for a in _main._loader.campaign_actions:
		var terms: Dictionary = a.effects.get("campaign", {})
		if String(terms.get("op", "")) == "start":
			starts.append(a)
	starts.sort_custom(func(x, y):
		return (
			float(x.effects["campaign"]["cost_pct_gdp"]) < float(y.effects["campaign"]["cost_pct_gdp"])
		)
	)

	# V2.6b2: each started effort takes the next-ranked fresh site, so the frame shows
	# the tour actually spreading rather than two efforts camped on the capital.
	var sites := _ranked_sites(ns)
	var next_site := 0
	var begun := 0
	for a2 in starts:
		var site := ""
		if next_site < sites.size():
			site = String(sites[next_site])
			next_site += 1
		if Campaign.execute(state, ns, _main._loader.campaign_actions, a2, site).get("applied", false):
			begun += 1
	if begun == 0:
		printerr("--campaign: no effort could be started")
		return

	_tick_months(4)

	# NOT scrolled, where --build and --invest both are, and the first frame is why. This
	# panel's TOP is the half a reader has to check -- the months to the vote and the
	# campaign bill, which is the row the budget panel's own campaign line must agree
	# with -- and pinning to the bottom put both off the frame and opened on a sentence
	# cut in half. V1.6e's correction has a direction as well as a subject: scroll to
	# where the flag's own claim is, and here that is the ledger.


## V1.7b. Two promises made in the run-up, an election crossed, and one of them broken
## for a year -- because the row a reader has to check is "broken N of M months", and
## every cheaper version of this flag renders identically to no promise at all.
##
## COMMITS `managed` FIRST, and that is not decoration. The promises bind the term the
## run-up wins, so the flag has to survive an executive election to reach a single month
## the register charges on; tools/balance_probe.gd's `managed` is the budget that does.
## A flag that lost the vote would photograph a run that had ended.
##
## SCROLLED TO THE BOTTOM, where --campaign deliberately is not. The promises section is
## the last thing on this panel, so the ledger --campaign checks and the promises this
## flag checks are at opposite ends of one scroll. V1.6e's correction has a DIRECTION as
## well as a subject, and here the two flags need opposite ones.
func _make_and_break_a_promise() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	_commit_delta({"defence": -1.4}, {"vat": 3.0})

	var to_open: int = Campaign.months_to_election(state, ns) - CampaignK.CAMPAIGN_WINDOW_MONTHS
	if to_open > 0:
		_tick_months(to_open)

	var made := 0
	for a in _main._loader.pledges:
		if Pledges.execute(state, ns, _main._loader.pledges, a).get("applied", false):
			made += 1
	if made == 0:
		printerr("--pledge: no promise could be made (%d months to the vote)" % Campaign.months_to_election(state, ns))
		return

	# Past the vote and into the term the promises bind.
	_tick_months(CampaignK.CAMPAIGN_WINDOW_MONTHS + 2)
	if not ns.in_government:
		printerr("--pledge: the incumbent lost the vote, so no promise ever came due")
		return

	# Break them: the income tax up and the health line down, which is exactly what the
	# tax lock and the health guarantee forbid.
	_commit_delta({"health": -4.0}, {"income": 8.0})
	_tick_months(12)

	var broken := 0
	for entry in ns.pledges:
		broken += int(entry["breach_months"])
	if broken == 0:
		printerr("--pledge: nothing was broken, so the frame shows a promise being kept")

	if _main._campaign_panel != null:
		_main._campaign_panel.scroll_to_bottom()


## balance_probe.gd's nation-relative deltas, through the real Budget.commit() so the
## frame shows a budget the player could have set.
func _commit_delta(spending: Dictionary, taxes: Dictionary) -> void:
	var state = _main._state
	var ns = state.player()
	var pending := {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(),
		"spending_pct_gdp": ns.spending_pct_gdp.duplicate(),
	}
	for key in taxes:
		pending["tax_rates_pct"][key] = float(pending["tax_rates_pct"].get(key, 0.0)) + float(taxes[key])
	for key in spending:
		pending["spending_pct_gdp"][key] = float(pending["spending_pct_gdp"].get(key, 0.0)) + float(spending[key])
	Budget.commit(state, pending)


func _break_ground() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	# Longest first, so the one still building at capture time is the big one. Started
	# through Projects.execute() rather than by writing the register, so the frame shows
	# what a click produces -- including the bloc offsets the price is made of.
	var starts: Array = []
	for a in _main._loader.project_actions:
		var terms: Dictionary = a.effects.get("project", {})
		if String(terms.get("op", "")) == "start":
			starts.append(a)
	starts.sort_custom(func(x, y):
		return (
			int(x.effects["project"]["build_months"]) > int(y.effects["project"]["build_months"])
		)
	)

	var shortest := 0
	for a2 in starts:
		if Projects.execute(state, ns, _main._loader.project_actions, a2).get("applied", false):
			shortest = int(a2.effects["project"]["build_months"])
	if shortest <= 0:
		printerr("--build: no project could be started")
		return

	_tick_months(shortest + 12)

	# Scrolled for --invest's reason, and it applies harder here: Public Works lists
	# what is building, what is finished and what is left, so the finished section --
	# the one this flag exists to photograph -- is below both of the others.
	if _main._projects_panel != null:
		_main._projects_panel.scroll_to_bottom()


## V2.2b. The register's readout -- no state to stage, so the frame IS the check:
## the panel builds, the five-column ledger holds its widest region name
## ("Provence-Alpes-Côte d'Azur"), and the partition rows agree with the table
## under them.
func _open_the_partition() -> void:
	_main._windows.open("region")


## V2.5. Ten years of divergence, then the Region panel -- which opens at the TOP
## of its scroll by default, and that is where this flag wants to be: the partition
## rows are the first thing on the panel and the league table runs off the fold,
## which is the direction V1.6e's correction is about. No scroll handling, because
## `_open_the_partition()` has none -- the panel's own default is the frame's claim.
func _let_the_regions_diverge() -> void:
	_tick_months(120)
	_main._windows.open("region")


## V2.7, the twenty-sixth flag. Ten years through the real clock so the network
## term has moved the shares the accessibility index reads, then the Region panel
## scrolled to the LEAGUE TABLE -- V1.6e's correction has a direction per flag,
## and the claim this frame exists to check is the eighth column, which is in the
## table and not in the partition above it.
func _show_the_network() -> void:
	_tick_months(120)
	_main._windows.open("region")
	_main._region_panel.scroll_to_bottom()


## V2.8. Two orders through the real verb, the real clock past the shorter
## build, the panel open on the mix. Sites come from the register's own cities
## -- a frame proving the mix moved should not assume a coordinate of its own.
func _show_the_energy() -> void:
	var state = _main._state
	var ns = state.player()
	var loader = _main._loader
	var access: Dictionary = Regions.accessibility_for(
		ns, state.regions.get(ns.id, []), state.region_graph)
	var weights: Dictionary = {}
	for region in loader.regions.get(ns.id, []):
		weights[region.id] = Migration.region_share(ns, region.id)
	var solar = null
	var gas = null
	for a in loader.energy_actions:
		if a.id == "order_solar_park":
			solar = a
		if a.id == "order_gas_ccgt":
			gas = a
	var region_ids: Array = loader.regions.get(ns.id, [])
	var home := ""
	var away := ""
	if region_ids.size() >= 2:
		home = String(region_ids[0].id)
		away = String(region_ids[1].id)
	var home_pt := Vector2(2.3522, 48.8566)
	var away_pt := Vector2(4.35, 43.30)
	for region in loader.regions.get(ns.id, []):
		if String(region.id) == home and region.cities.size() > 0:
			home_pt = region.cities[0].lonlat
		if String(region.id) == away and region.cities.size() > 0:
			away_pt = region.cities[0].lonlat
	if solar != null and home != "":
		Energy.execute(state, ns, loader, loader.energy_actions, solar,
			home_pt, home, "", access, weights)
	if gas != null and away != "":
		Energy.execute(state, ns, loader, loader.energy_actions, gas,
			away_pt, away, "", access, weights)
	# Past solar's 12-month build and not past gas's 30: one glyph running, one
	# building, and the mix ledger carrying both.
	_tick_months(14)
	_main._windows.open("energy")


## V2.8. Two orders at real register coordinates through the real verb, ticked
## past solar's build so one glyph is FILLED and one HOLLOW, then placement armed
## so the reticle is on the frame too.
func _place_the_plants() -> void:
	var state = _main._state
	var ns = state.player()
	var loader = _main._loader
	var access: Dictionary = Regions.accessibility_for(
		ns, state.regions.get(ns.id, []), state.region_graph)
	var weights: Dictionary = {}
	for region in loader.regions.get(ns.id, []):
		weights[region.id] = Migration.region_share(ns, region.id)
	var solar = null
	var gas = null
	for a in loader.energy_actions:
		if a.id == "order_solar_park":
			solar = a
		if a.id == "order_gas_ccgt":
			gas = a
	# Real register coordinates, but deliberately NOT each region's principal
	# city: at the France fit the first screenshot pass buried the filled glyph
	# under Paris's own 9.6px city dot, and a frame whose claim is the GLYPH
	# cannot stage it where a bigger glyph already lives. Each region's LAST
	# named city is a real place the register vouches for and a clear canvas.
	var ranked: Array = loader.regions.get(ns.id, []).duplicate()
	var home = ranked[0] if ranked.size() > 0 else null
	var away = ranked[1] if ranked.size() > 1 else null
	var home_pt := Vector2(2.3522, 48.8566)
	var away_pt := Vector2(4.35, 43.30)
	if home != null and home.cities.size() > 0:
		home_pt = home.cities[home.cities.size() - 1].lonlat
	if away != null and away.cities.size() > 0:
		away_pt = away.cities[away.cities.size() - 1].lonlat
	if solar != null and home != null:
		Energy.execute(state, ns, loader, loader.energy_actions, solar,
			home_pt, String(home.id), "", access, weights)
	if gas != null and away != null:
		Energy.execute(state, ns, loader, loader.energy_actions, gas,
			away_pt, String(away.id), "", access, weights)
	_tick_months(14)
	# France fit: the map's cover fit is the whole planet; this frame's claim is
	# two glyphs a few hundred pixels apart, not the world.
	var view = _main._map_view
	var centre := Vector2((home_pt.x + away_pt.x) * 0.5, (home_pt.y + away_pt.y) * 0.5)
	view.center_on_lonlat(centre.x, centre.y)
	view.zoom_by(6.0, view.size / 2.0)
	view.begin_placement()
	# The reticle draws at the cursor, and a batch capture cannot control where
	# the OS left it -- so bring the cursor to the frame's centre and let the
	# mode's own cue land where the reader is looking.
	view.warp_mouse(view.size * 0.5)


## V2.6a. Ten years through the real clock -- _tick_months() drives
## advance_one_day(), so the top bar's date agrees with the population figures
## beside it (V1.4c's fix, and every hand-rolled month loop before it got this
## wrong). The City panel opens on its LIST view by default -- show_city() is
## never called, so `_city_id` stays "" and `_build_list()` runs -- and the
## ranked-by-population rows sit at the TOP of the scroll with no explicit
## scroll call needed, `_open_the_partition()`'s own precedent: the claim this
## flag exists to photograph is the ranking itself, so the panel's own default
## view IS the frame V1.6e's per-flag direction asks for.
func _let_the_people_move() -> void:
	_tick_months(120)
	_main._windows.open("city")


## V2.2b, the map's own route driven end to end. Paris's coordinate is read from
## the register rather than hardcoded, because a frame proving the register draws
## should not assume a number of its own; the zoom doubles past CITY_MIN_ZOOM so
## the crosses separate; the hover is set on the control the way --hover-project
## sets its marker, because the label is the one thing the hit-test suites cannot
## see; and the panel opens through show_city(), main.gd's own click path.
func _point_at_the_capital() -> void:
	var lonlat := Vector2(2.3522, 48.8566)  # Paris, if the register somehow lacks it
	for region in _main._loader.regions.get("FRA", []):
		for city in region.cities:
			if city.id == "FR1_paris":
				lonlat = city.lonlat
	var view = _main._map_view
	view.center_on_lonlat(lonlat.x, lonlat.y)
	view.zoom_by(2.0, view.size / 2.0)
	view._hovered_city = "FR1_paris"
	view.queue_redraw()
	_main._city_panel.show_city("FR1_paris")
	_main._windows.open("city")


## V1.7c. A referendum called and left in flight, so the law panel's pending block is
## on the frame with a live countdown and a live yes share.
##
## NOT TICKED PAST THE VOTE, and that is the flag's whole claim. A resolved referendum
## renders as an ordinary result summary, which is a frame of the machine V1.2c already
## shipped; what V1.7c added is the state BETWEEN the division and the answer, and that
## exists for exactly REFERENDUM_DELAY_MONTHS. Ticked to roughly half of it so the
## countdown reads a number that is neither its start nor its end -- V1.6f's own bug,
## where a project hover printed "12 of 96 months" and a reader could not tell which
## twelve.
##
## SCROLLED TO THE TOP, where --pledge is scrolled to the bottom: the pending block is
## the first thing on the law panel by construction, because while a referendum is
## running it is the only thing the list of proposable laws cannot say. V1.6e's
## correction has a direction per flag.
func _call_a_referendum() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	var law = null
	for candidate in Legislature.available(ns, _main._loader.laws):
		if Legislature.can_put_to_referendum(ns, candidate):
			law = candidate
			break
	if law == null:
		printerr("--referendum: no amendment could be put to the country")
		return

	var result := Legislature.propose(state, _main._loader, law, false, true)
	if not bool(result.get("referendum_called", false)):
		printerr("--referendum: the assembly refused %s (%d of %d)" % [
			law.id, int(result.get("yes_seats", 0)), int(result.get("seats_total", 0))
		])
		return

	_tick_months(int(ReferendumK.REFERENDUM_DELAY_MONTHS / 2))
	if not Referendum.is_pending(ns):
		printerr("--referendum: the vote resolved before the frame was taken")



## V1.1e. A bill the second chamber refuses, so the law panel's held block and the
## result summary's second tally both have something live on them.
##
## Scrolled to the TOP, and the direction is the flag's own rather than the panel's --
## docs/sector-model.md's V1.6e correction with docs/campaign-model.md's V1.7a addition.
## A held bill gets its own block above the law list, the way a pending referendum does,
## so the top is where this flag's claim is. `--court` below wants the same end for a
## different reason: the result summary is up there too.
func _lose_the_senate() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	var party_list: Array = _main._loader.parties.get(ns.id, [])

	for law in Legislature.available(ns, _main._loader.laws):
		if law.constitutional:
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			continue
		if bool(Legislature.resolve_upper(ns, party_list, law)["passed"]):
			continue
		var result := Legislature.propose(state, _main._loader, law)
		if not bool(result.get("held_by_upper", false)) and not bool(result.get("blocked_by_upper", false)):
			printerr("--senate: %s was not refused: %s" % [law.id, result])
			return
		# A few months off the clock, so the held block reads a countdown that has
		# actually counted rather than the number the content authored.
		_tick_months(3)
		return
	printerr("--senate: no proposable law is carried by the Assembly and refused by the Senat")


## V1.1e. A bill both chambers carry and the court strikes down. The one flag in this
## file whose frame is meant to show the player something they could have READ in
## advance: the forecast line on the law row says the court would strike it, and the
## result summary then says it did, with the same two numbers.
func _lose_the_court() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	var party_list: Array = _main._loader.parties.get(ns.id, [])

	for law in Legislature.available(ns, _main._loader.laws):
		if law.constitutional or not Judiciary.strikes_down(ns, law):
			continue
		if not bool(Legislature.resolve_vote(ns, party_list, law, false)["passed"]):
			continue
		if not bool(Legislature.resolve_upper(ns, party_list, law)["passed"]):
			continue
		var result := Legislature.propose(state, _main._loader, law)
		if not bool(result.get("struck_down", false)):
			printerr("--court: %s was not struck down: %s" % [law.id, result])
		return
	printerr("--court: no proposable law is carried by both chambers and struck by the court")
## V1.7c. The electoral system changed by an ORDINARY Act, and then an assembly actually
## elected under it -- which is the only thing that shows the change happened, because
## the register itself is one string.
##
## TICKS PAST JUNE 2029, France's next legislative election, because that is when the
## new method first allocates a seat. A flag that stopped at the vote would photograph
## an unchanged assembly under a changed rule and prove nothing, which is V1.6f's
## all-zero-data-layer argument in a new place.
func _reform_the_ballot() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	var law = null
	for candidate in Legislature.available(ns, _main._loader.laws):
		if candidate.effects.get("institutional", {}).has("election_system"):
			law = candidate
			break
	if law == null:
		printerr("--electoral: no electoral-reform Act is proposable")
		return

	var before: String = ns.election_system
	var result := Legislature.propose(state, _main._loader, law, false)
	if not bool(result.get("passed", false)):
		printerr("--electoral: the assembly refused %s (%d of %d)" % [
			law.id, int(result.get("yes_seats", 0)), int(result.get("seats_total", 0))
		])
		return
	if ns.election_system == before:
		printerr("--electoral: the Act passed and the system did not move")
		return

	# Past the next legislative election, so the assembly on the frame is one this
	# method elected. France's is June 2029 against a January 2026 start.
	var to_vote: int = (ns.next_election_year - state.year) * 12 + (ns.next_election_month - state.month) + 1
	if to_vote > 0:
		_tick_months(to_vote)

## V1.8. Put a crisis on the desk and stop with the deadline still running.
##
## ANNOUNCED DIRECTLY rather than waited for, and that is the honest way round: the
## hazard is a pure function of (nation, event, absolute month), so waiting for one to
## draw would mean ticking an unknown number of months and photographing whatever the
## hash happened to pick. Every other state-mutating flag in this file does the same --
## `--coerce` imposes a measure rather than waiting for the agenda to.
##
## The event chosen is the one with a SUBJECT, because the subject line is the half of
## this panel that nothing else in the game does: `subject_office` is content, the person
## is resolved from U6b's register at card time, and a frame with no name in it would
## prove nothing about that path.
const HORIZON_MONTHS := 48


func _put_a_crisis_on_the_desk() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()

	# TICKED UNTIL ONE ARRIVES RATHER THAN ANNOUNCED DIRECTLY, and the first version of
	# this flag did announce: it wrote the register and then ticked a month, which put a
	# correct panel on screen and left THE MESSAGE CARD UNEXERCISED -- main.gd only cards
	# an event that was absent before the tick and present after it, so a pre-announced
	# one is already pending when _card_events() looks. The frame showed an empty column
	# beside a live crisis, which is precisely the half of this surface U5a built the
	# column for. Waiting is affordable because the hazard is deterministic: the first
	# event of a new game arrives on a fixed month, so this loop is not a search.
	for _m in range(HORIZON_MONTHS):
		_tick_months(1)
		if Events.is_pending(ns):
			break
	if not Events.is_pending(ns):
		printerr("--event: no event arrived inside %d months" % HORIZON_MONTHS)
		return
	var ev = Events.pending_event(ns, _main._loader)
	if ev != null and not ev.has_subject():
		# Not a failure -- it is a fact about which event drew first, and the subject
		# line is the half of this panel nothing else in the game does, so a frame
		# without one proves less.
		printerr("--event: '%s' names no subject, so the frame shows no person" % ev.id)


## V3.5. A sited crisis on the desk, with its place in the title.
##
## `--event`'s sibling, and separate from it because the two flags want DIFFERENT
## first arrivals: --event stops at whatever draws and only notes a missing
## subject, while this loop's whole claim is the place suffix, so it keeps ticking
## until ANY entry on the desk is one the hazard SITED. That wait is a fixed month,
## not a search -- the hazard is pure in (nation, event, month), events.gd's own
## argument -- and the non-sited events met on the way lapse on their own
## respond_months and cooldown, because answering one would put a row in the
## ledger that this frame's `--open events` companion would then not explain.
func _put_a_sited_crisis_on_the_desk() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	# 240 rather than --event's 48: the flood is a 0.06 draw competing for the
	# four-entry desk and its own cooldown, and the horizon has to cover a run of bad hashes
	# rather than the mean of them. The re-run measured ~10 draws in 168 months,
	# so the deterministic sequence lands well inside this.
	var horizon := 240
	for _m in range(horizon):
		_tick_months(1)
		# The register only gains region_id on a sited announce, so the key is the
		# honest marker -- checking the event content here would be a second opinion
		# about what sited means.
		# ANY entry: the desk is severity-ordered, so a sited flood can sit behind
		# a more severe head and the head alone would miss it.
		for entry in ns.event_queue:
			if entry.has("region_id"):
				return
	printerr("--climate: no sited event drew inside %d months" % horizon)


## The other end of the same panel, and it wants the opposite scroll.
##
## V1.6e's screenshot correction says to scroll to where the flag's own claim is, and
## V1.7b sharpened it to a direction PER FLAG rather than per panel. This is that a
## second time on one surface: the pending block is at the top and the ledger is at the
## bottom, so `--event` opens on the question and `--event-answered` opens on the record.
##
## Answers the crisis rather than letting it lapse, and then lets a SECOND one lapse, so
## the ledger shows both kinds of row -- a decision the player made and a decision the
## clock made for them. A frame of one kind would leave the "No answer given" styling as
## dead code, which is exactly what U6a's own pass caught on the diary strip.
func _answer_a_crisis() -> void:
	var state = _main._state
	if state == null:
		return
	var ns = state.player()
	if _main._loader.events.size() < 2:
		printerr("--event-answered: fewer than two events in the content")
		return

	var first = _main._loader.events[0]
	# The announce signature grew the month and the name map at V3.5; the shipped
	# content is non-sited, so both are inert -- filled as tick_month fills them.
	Events.announce(ns, first, Events._absolute_month(int(state.year), int(state.month)),
		Events.region_names(ns, _main._loader))
	var answered := ""
	for c in first.choices:
		if not bool(c["is_default"]):
			answered = String(c["id"])
			break
	# By id, not the head: a more severe entry already on the desk would be the head,
	# and choose() would then answer THAT entry (or nothing, for a choice id it lacks).
	Events.answer(state, _main._loader, String(first.id), answered)

	var second = _main._loader.events[1]
	ns.event_category_quiet = {}
	Events.announce(ns, second, Events._absolute_month(int(state.year), int(state.month)),
		Events.region_names(ns, _main._loader))
	_tick_months(second.respond_months + 1)

	if ns.event_history.size() < 2:
		printerr("--event-answered: the ledger holds %d rows, expected two" % ns.event_history.size())
	if _main._events_panel != null:
		_main._events_panel.scroll_to_bottom()


## V2.6b1. A demonstration that has actually happened, on the map, in the place the
## model put it.
##
## TICKS UNTIL AN ACT FIRES rather than a fixed number of months, which is V1.8's own
## correction: --event announced the register directly and then ticked, so main.gd
## never carded anything and the frame showed an empty column beside a live crisis.
## Affordable for the same reason it was there -- the agent is deterministic, so
## "until it fires" terminates at a known month rather than gambling.
##
## The ring is gated on UNREST_THRESHOLD_PCT, the same bar src/ui/economy_panel.gd's
## own line uses, so a frame taken before the unions organise would show a city and no
## ring and prove nothing about the thing this flag exists to photograph.
## The player's first running effort's meeting city, with its lonlat -- the ring the
## map draws while a campaign is in the field. Empty when nothing is running.
func _campaign_meeting_target() -> Dictionary:
	var state = _main._state
	if state == null:
		return {}
	var ns = state.player()
	var running: Array = Campaign.running(ns)
	if running.is_empty():
		return {}
	var site := Campaign.site_of(ns, String(running[0]))
	if site == "":
		return {}
	var city = Campaign.principal_city(_main._loader, ns, site)
	if city == null:
		return {}
	return {"city_id": String(city.id), "lonlat": city.lonlat}


func _site_the_demonstration() -> void:
	var state = _main._state
	if state == null:
		return
	# V2.6b2: a campaign effort in the field owns the map's ring when unrest is
	# quiet -- the flag photographs whatever ring the staged state actually has, and
	# only provokes the unions when there is no campaign ring to take. The staged
	# campaign's timeline is kept either way: ticking to a demonstration would
	# photograph a month the --campaign staging never lived in.
	var staged := _campaign_meeting_target()
	# `.get` rather than `[` -- the dictionary is EMPTY when no campaign is in the
	# field, which is bare `--site`'s whole path: V2.6b2 wrote this check against its
	# own `--campaign --site` pass and the bare flag crashed here until V2.6c ran it.
	if String(staged.get("city_id", "")) != "":
		var view0 = _main._map_view
		view0.center_on_lonlat(staged["lonlat"].x, staged["lonlat"].y)
		view0.zoom_by(4.0, view0.size / 2.0)
		view0.refresh_cities()
		view0._hovered_city = String(staged["city_id"])
		view0.queue_redraw()
		return
	_provoke_the_unions()

	var ns = state.player()
	var region_list: Array = state.regions.get(ns.id, [])
	var report: Dictionary = Unrest.site_report(ns, region_list,
		Regions.accessibility_for(ns, region_list, state.region_graph),
		state.project_sited_pct.get(ns.id, {}))
	var guard := 0
	while (state.unrest_acts.is_empty() or String(report["city_id"]) == "") and guard < 120:
		_tick_months(1)
		guard += 1
		ns = state.player()
		report = Unrest.site_report(ns, region_list,
			Regions.accessibility_for(ns, region_list, state.region_graph),
			state.project_sited_pct.get(ns.id, {}))
	if state.unrest_acts.is_empty():
		printerr("--site: no act fired in %d months, so there is nothing to photograph" % guard)
		return
	if String(report["city_id"]) == "":
		printerr("--site: the unions are out and the register names no place -- a nation with a flat signal cannot be sited")
		return

	var lonlat := Vector2.ZERO
	for region in region_list:
		for city in region.cities:
			if String(city.id) == String(report["city_id"]):
				lonlat = city.lonlat
	var view = _main._map_view
	view.center_on_lonlat(lonlat.x, lonlat.y)
	# Closer than --city's 2.0. The ring is the radius plus three pixels and the
	# smallest cities clamp at a radius of two, so at the city flag's zoom the mark
	# this flag exists to photograph is five pixels wide among several hundred
	# crosses -- V1.6e's correction, which is about scrolling to where the flag's own
	# claim is and applies to a map's zoom exactly as it does to a panel's scroll.
	view.zoom_by(4.0, view.size / 2.0)
	# Explicit, though the monthly hook in main.gd now rebuilds it too: every
	# state-mutating flag since --coerce got away with writing behind a view that had
	# already refreshed, which is the tool's own V1.3g bug.
	view.refresh_cities()
	# The hover is set the way --hover-project and --city set theirs: the label is the
	# one half of this mark a headless suite structurally cannot see.
	view._hovered_city = String(report["city_id"])
	view.queue_redraw()
