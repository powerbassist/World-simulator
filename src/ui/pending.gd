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


## The window ids with something on them awaiting an answer, in the order a
## president would deal with them: the thing with a deadline first.
static func window_ids(state) -> Array:
	var out: Array = []
	if state == null:
		return out
	var ns = state.player()
	if ns == null:
		return out

	# A crisis with a countdown, which answers itself if nobody answers it.
	if Events.is_pending(ns):
		out.append("events")

	# A vote the country has already been called to. V1.7c.
	if not ns.referendum_pending.is_empty():
		out.append("legislature")

	# A proposal before the council that binds the player whether or not they
	# voted for it. V1.3d.
	if not Dictionary(state.bloc.get("pending", {})).is_empty():
		out.append("bloc")

	# The run-up, which is the only window in which an effort can be started at
	# all -- V1.7a's "a standing rate with a deadline", and the deadline is a date
	# the player cannot move.
	if Campaign.is_open(state, ns):
		out.append("campaign")

	return out
