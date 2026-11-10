extends RefCounted

## V5.3 B7 (docs/design/v5.3-b7-density.md, section 4): two decisions the councils
## already put to the player, which no card pointed at -- only the Orgs tab's mark.
## A treaty the council carried that waits on the player's own assembly (`ratifying`),
## and a division the player's vote can swing (Orgs' `player_swings` stamp, set at the
## session's opening). One quiet card each, with a Go on the Orgs tab, whose verbs are
## tagged with the same subjects (council_section.gd). The author's call 4: a division
## the player cannot swing gets no card, it stays the tab's mark.
##
## IT SPENDS NONE OF THE 4 + 6 A YEAR (docs/design/decision-surfaces.md): the cards wait
## in the inbox and never touch the clock -- region_arrival.gd's shape, and its rule that
## what was told lives here, not in the save. A card goes once its decision is settled
## (the assembly asked, the division held), or at its Go; one the player dismissed is
## not put up again for the same decision.

const Orgs = preload("res://src/sim/orgs.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const Strings = preload("res://src/ui/strings.gd")

## main's instance id -> {state_id, told: {key: true}, cards: {live card id: key}}.
static var _told := {}


## The month's check, at the month's end beside the Regions arrival.
static func check(main) -> void:
	var state = main._state
	var ns = state.player() if state != null else null
	if ns == null:
		return
	var memory: Dictionary = _told.get_or_add(main.get_instance_id(), {"state_id": 0, "told": {}, "cards": {}})
	var inbox = main._hud.inbox
	if int(memory["state_id"]) != state.get_instance_id():
		memory["state_id"] = state.get_instance_id()
		memory["told"] = {}
		memory["cards"] = {}
	var go := _on_go.bind(main)
	if not inbox.card_action.is_connected(go):
		inbox.card_action.connect(go)
	# What waits now, keyed by the decision: {key: [subject, title, body]}.
	var now := {}
	var month := int(state.year) * 12 + int(state.month)
	for org in main._loader.orgs:
		if not org.council or not ns.orgs.has(org.id):
			continue
		var title: String = Strings.row_name("orgs", org)
		var r: Dictionary = state.orgs.get(org.id, {}).get("ratifying", {})
		if String((r.get("nations", {}) as Dictionary).get(ns.id, "")) == CouncilK.RATIFY_PENDING:
			var left := int(r.get("months_left", 0))
			var asks := Strings.tn("%s passed the council and now needs your assembly. Put it to a vote within %d month, or it falls for every member.", "%s passed the council and now needs your assembly. Put it to a vote within %d months, or it falls for every member.", left)
			# Keyed by the window's opening month too: a treaty carried again later is news again.
			now["ratify|%s|%s|%d" % [org.id, String(r.get("proposal_id", "")), month - (CouncilK.RATIFY_WINDOW_MONTHS - left)]] = ["ratify|%s" % org.id, Strings.t("Treaty to ratify — %s") % title,
				asks % [_proposal_name(r), left]]
		var pending: Dictionary = Orgs.pending(state, org.id)
		# The player's vote cast from the tab settles it as the Go would (an abstention
		# is the default and cannot be told from no answer).
		if bool(pending.get("player_swings", false)) and String(pending.get("player_vote", Orgs.VOTE_ABSTAIN)) == Orgs.VOTE_ABSTAIN:
			var months := int(pending.get("months_left", 0))
			var swing := Strings.tn("%s goes to the council's vote in %d month, and your vote can decide it.", "%s goes to the council's vote in %d months, and your vote can decide it.", months)
			now["council|%s|%s|%d" % [org.id, String(pending.get("proposal_id", "")),
				int(pending.get("opened_year", 0)) * 12 + int(pending.get("opened_month", 0))]] = ["council|%s" % org.id, Strings.t("Council vote — %s") % title,
				swing % [_proposal_name(pending), months]]
	# Settled since: the card goes. Still waiting: its months age in place.
	var cards: Dictionary = memory["cards"]
	for card in cards.keys():
		var key := String(cards[card])
		if inbox.lane_of(String(card)) == "" or not now.has(key):
			inbox.dismiss(String(card))
			cards.erase(card)
		else:
			inbox.set_body(String(card), String(now[key][2]))
	for key in now:
		if (memory["told"] as Dictionary).has(key):
			continue
		memory["told"][key] = true
		var card: String = inbox.push(String(now[key][1]), String(now[key][2]),
			[{"label": Strings.t("Open"), "acts_on": String(now[key][0])}])
		cards[card] = key


static func _proposal_name(row: Dictionary) -> String:
	return Strings.row("bloc-proposals", String(row.get("proposal_id", "")), "name", String(row.get("name", "")))


static func _on_go(card: String, _index: int, main) -> void:
	var cards: Dictionary = (_told.get(main.get_instance_id(), {}) as Dictionary).get("cards", {})
	if not cards.has(card):
		return
	main._windows.open("orgs")
	# The tab lists the orgs that wait on the player first (orgs_panel.gd): its top.
	main._windows.content("orgs").mark_dirty()
	cards.erase(card)
	main._hud.inbox.dismiss(card)
