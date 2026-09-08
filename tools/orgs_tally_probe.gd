extends SceneTree

## V3.3 scratch probe: how each council proposal tallies over the EU-27 seats,
## and whether the player's abstain/against flip changes any outcome. Mirrors
## tests/test_orgs.gd's _force_vote exactly. Not committed at closeout.

const Orgs = preload("res://src/sim/orgs.gd")

var _loader


func _init() -> void:
	_loader = load("res://src/core/data_loader.gd").new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		for e in _loader.errors:
			push_error(e)
		quit(1)
		return

	var GameStateT = load("res://src/core/game_state.gd")
	for p in _loader.bloc_proposals:
		var args := OS.get_cmdline_user_args()
		if not args.is_empty() and p.id != args[0]:
			continue
		if args.size() > 1 and args[1] == "verbose":
			var vs = GameStateT.new_game(_loader, "FRA")
			for mid in Orgs.members(vs, p.org_id):
				var mn = vs.nations[mid]
				var cp: Dictionary = mn.coalition_position
				print("  %s (%d seats): %s support=%.4f deficit=%.2f debt=%.1f pos=(%.2f,%.2f)" % [mid, Orgs.live_seats(vs, p.org_id, mid), Orgs._vote_of(vs, mid, p, {"player_vote": Orgs.VOTE_ABSTAIN}), Orgs.support(vs, mn, p), mn.deficit_pct_gdp, mn.debt_to_gdp_pct(), float(cp.get("economic", 0.0)), float(cp.get("social", 0.0))])
		var outcomes := []
		for choice in [Orgs.VOTE_ABSTAIN, Orgs.VOTE_AGAINST, Orgs.VOTE_FOR]:
			var s = GameStateT.new_game(_loader, "FRA")
			s.orgs[p.org_id]["pending"] = {
				"proposal_id": p.id, "name": p.proposal_name,
				"summary": p.summary, "months_left": 1,
				"player_vote": Orgs.VOTE_ABSTAIN,
				"opened_year": s.year, "opened_month": s.month,
			}
			Orgs.cast_vote(s, p.org_id, choice)
			Orgs.tick_month(s, _loader)
			var lv: Dictionary = Orgs.last_vote(s, p.org_id)
			outcomes.append("%s(f%d/a%d)" % [lv.get("passed", false), int(lv.get("seats_for", 0)), int(lv.get("seats_against", 0))])
		var pivotal: bool = outcomes[0] != outcomes[1]
		print("%s/%s: abstain=%s against=%s for=%s %s" % [p.org_id, p.id, outcomes[0], outcomes[1], outcomes[2], "PIVOTAL" if pivotal else ""])
	quit(0)
