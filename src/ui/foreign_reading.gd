extends RefCounted

## What the player can know of another nation's approval -- V5.1-d4, the author's
## fog call on G2 ("Une fourchette + source"): a range with where it comes from,
## never the true figure. The player's own approval is a published poll (±3, as the
## strip and the Society tab print it); another government's is an estimate, and how
## good it is depends on who is there to make it -- a resident embassy (V5.1-0d's
## register, data/world/embassies.json) or only the foreign press.
##
## In src/ui and pure, on poll_noise.gd's argument: the sim holds the truth and no
## randomness; the noise is added the moment a figure is shown, as a function of
## (month, nation), so a range is the same on every repaint within a month and
## survives a save. The centre is noised as well, so the middle of the range does
## not give the truth away; the half-width always covers the noise, so the truth is
## always inside.

const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const Strings = preload("res://src/ui/strings.gd")

## Half the width of the range, in points: an embassy's estimate, the press's. Both
## above PollNoise.NOISE_MAX_PCT, the centre's own error, so the range holds the truth.
const EMBASSY_HALF_PCT := 5.0
const PRESS_HALF_PCT := 10.0


## Whether the player holds a resident embassy in `nation_id`'s capital.
static func has_embassy(state, nation_id: String) -> bool:
	var ns = state.player()
	return ns != null and ns.embassies.has(nation_id)


## [low, high] of `nation_id`'s approval as the player can know it, in whole points.
static func approval_range(state, nation_id: String) -> Array:
	var ns = state.nations.get(nation_id)
	if ns == null:
		return []
	var centre: float = PollNoise.displayed(
		PollNoise.poll_id(int(state.year), int(state.month)), "foreign:%s" % nation_id, float(ns.overall_approval_pct))
	var half := EMBASSY_HALF_PCT if has_embassy(state, nation_id) else PRESS_HALF_PCT
	return [roundi(clampf(centre - half, 0.0, 100.0)), roundi(clampf(centre + half, 0.0, 100.0))]


## The approval line for a nation's card: the player's own poll, or another's range
## and its source.
static func approval_text(state, nation_id: String) -> String:
	var ns = state.nations.get(nation_id)
	if ns == null:
		return ""
	if nation_id == String(state.player_nation_id):
		var shown: float = PollNoise.displayed(
			PollNoise.poll_id(int(state.year), int(state.month)), PollingPanel.HEADLINE_KEY, float(ns.overall_approval_pct))
		return Strings.t("Approval: %d%% (a poll, ±%d points)") % [roundi(shown), int(PollNoise.NOISE_MAX_PCT)]
	var span := approval_range(state, nation_id)
	if has_embassy(state, nation_id):
		return Strings.t("Approval: %d–%d%% (our embassy's estimate)") % [span[0], span[1]]
	return Strings.t("Approval: %d–%d%% (the foreign press)") % [span[0], span[1]]
