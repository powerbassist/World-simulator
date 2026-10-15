extends RefCounted

## What is waiting for the player, as a list of WINDOW IDS -- V2.1c.
##
## Static, like `trends.gd`, `panel_kit.gd` and `ui_theme.gd`, and read-only over
## `GameState`, like every other file in `src/ui/`.
##
## **The measurement this exists for.** `tools/nav_probe.gd` ran fourteen years
## with nothing ever opened and counted the months in which a decision was in
## front of the player against the months in which anything on the resting screen
## said so: **42 of 74 pending-months silent for a president who never touches a
## card, 64 of 74 for one who reads a card and closes it.** The message column is
## the only route a pending thing has ever had, it holds six cards, drops the
## oldest, and nothing re-pushes -- so a council vote and an open campaign window
## were silent in **100 %** of their months, having no card at all.
##
## **What this is NOT.** It is not a dashboard and it is not a second readout: it
## returns ids, and `action_bar.gd` turns them into a mark on the cluster where
## the answer is given. U5a deleted `dashboard.gd` on purpose and the map is still
## the resting screen.
##
## **The test for an entry is that it awaits THE PLAYER**, not that it is
## interesting. A dissolution already called and an election already scheduled are
## consequences in flight with no button behind them, so they are deliberately not
## here; `ns.dissolution_pending` was measured (0 months in the probe's run) and
## refused on the rule rather than on the number. A later block adds a line here
## rather than a branch anywhere else -- V2.4's day agenda and V2.8's energy each
## know their own answer to *is something waiting?*

const Events = preload("res://src/sim/events.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const Programme = preload("res://src/sim/programme.gd")
const Industry = preload("res://src/sim/industry.gd")
const Statute = preload("res://src/sim/statute.gd")


## The window ids with something on them awaiting an answer, in the order a
## president would deal with them: the thing with a deadline first. The loader
## rides along for the reads that need content -- the programme's offer, and
## the industry checks whose orphan skip walks the loader's majors (a register
## entry for a firm a content edit removed must not light a mark forever).
static func window_ids(state, loader) -> Array:
	var out: Array = []
	if state == null:
		return out
	var ns = state.player()
	if ns == null:
		return out

	# The term's programme, ahead of everything else: Programme.available() is
	# empty everywhere but an unchosen term start -- structurally, before any
	# content is consulted -- so a non-empty offer IS the pending choice. And
	# the clock is paused behind it (main.gd's term-start enforcement), which
	# makes it the first thing a president deals with rather than one mark
	# among many. Nothing offerable, nothing pending.
	if loader != null and not Programme.available(state, ns, loader).is_empty():
		out.append("agenda")

	# A crisis with a countdown, which answers itself if nobody answers it.
	if Events.is_pending(ns):
		out.append("events")

	# A vote the country has already been called to. V1.7c. V4.2 T6 extends the
	# mark's source: a private member's bill in its endorsement window awaits
	# THE PLAYER's public stand -- past the window the assembly divides on its
	# own -- while an endorsed bill awaits only the calendar, so the mark keys
	# on the unendorsed live bills, not on the in-tray whole.
	if not ns.referendum_pending.is_empty() or not Statute.awaiting_endorsement(ns).is_empty():
		out.append("legislature")

	# A proposal before any council the player sits on, binding them whether or
	# not they voted for it. V1.3d; per-org since V3.2.
	for org_id in Orgs.council_ids(state):
		if not state.nations[state.player_nation_id].orgs.has(org_id):
			continue
		if not (Orgs.pending(state, org_id) as Dictionary).is_empty():
			out.append("orgs")
			break
		# A treaty waiting on THIS assembly: an idle player otherwise kills it by
		# default at the window's end, and is charged for it.
		var ratifying: Dictionary = state.orgs[org_id].get("ratifying", {})
		if String((ratifying.get("nations", {}) as Dictionary).get(state.player_nation_id, "")) == CouncilK.RATIFY_PENDING:
			out.append("orgs")
			break

	# The run-up, which is the only window in which an effort can be started at
	# all -- V1.7a's "a standing rate with a deadline", and the deadline is a date
	# the player cannot move.
	if Campaign.is_open(state, ns):
		out.append("campaign")

	# V4.7b: the autonomy machine's two answerable states -- a foreign bid with
	# a window, a failing major with a rescue window. Both are "awaits THE
	# PLAYER" by the file's own test: each lapses to a committed outcome if
	# ignored, and the verbs that answer live on the companies window.
	if not Industry.pending_bid(state, ns, loader).is_empty() or not Industry.failing(state, ns, loader).is_empty():
		out.append("companies")

	return out
