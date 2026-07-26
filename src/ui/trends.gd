extends RefCounted

## Turns GameState.history into the deltas a panel can show -- U3. One job: read
## the monthly snapshots backwards and answer "how much has this moved, and which
## figure is moving worst". No state of its own, so every function is static and
## the caller holds nothing between refreshes.
##
## History is written once per simulated month by main.gd's _on_month_elapsed()
## -- Budget.snapshot() merged with Opinion.snapshot(), stamped year and month.
## It survives save/load. It is the only rolling series the game keeps, which is
## why this module exists rather than each panel caching its own previous values
## the way polling_panel.gd has to for its poll-to-poll column.

const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")

## The comparison window. Six months is long enough that one noisy month does not
## dominate and short enough to still be about the player's current term.
const TREND_MONTHS := 6

## Everything the Overview tab watches, with the sign convention that makes them
## comparable: `worse_when_rising` false means falling is the bad direction.
##
## `scale` is how many points of movement over the window counts as one unit of
## "this is the story". Dividing by it is what lets a 1.2-point unemployment rise
## be weighed against a 5-point approval slide -- without it, whichever figure
## happens to be measured on the largest numbers always wins.
const WATCHED: Array[Dictionary] = [
	{"key": "unemployment_pct", "label": "Unemployment", "worse_when_rising": true, "scale": 1.0, "unit": "pp"},
	{"key": "overall_approval_pct", "label": "Approval", "worse_when_rising": false, "scale": 5.0, "unit": "pp"},
	{"key": "deficit_pct_gdp", "label": "Deficit", "worse_when_rising": false, "scale": 1.0, "unit": "pp"},
	{"key": "growth_annual_pct", "label": "Growth", "worse_when_rising": false, "scale": 0.5, "unit": "pp"},
	{"key": "debt_to_gdp_pct", "label": "Debt", "worse_when_rising": true, "scale": 3.0, "unit": "pp"},
]

const APPROVAL_KEY := "overall_approval_pct"

## Below this, the worst-moving figure is not worth leading a screen with -- a
## quarter of the scale, i.e. movement a player would not have noticed.
const NOTABLE_SEVERITY := 0.25


## The snapshot `months_ago` months back, or {} if history does not reach that
## far. Zero is the current month. A new game has no history at all until the
## first month elapses, so {} is the normal early-game answer and not an error.
static func entry_at(state, months_ago: int) -> Dictionary:
	if state == null:
		return {}
	var index: int = state.history.size() - 1 - months_ago
	if index < 0 or index >= state.history.size():
		return {}
	return state.history[index]


## Change in a raw history field over `months`, NAN when history is too short.
## Callers render NAN as an em dash rather than a zero -- "no data yet" and "has
## not moved" are different statements and the player should not have to guess.
static func delta(state, key: String, months: int) -> float:
	var now := entry_at(state, 0)
	var then := entry_at(state, months)
	if now.is_empty() or then.is_empty():
		return NAN
	if not now.has(key) or not then.has(key):
		return NAN
	return float(now[key]) - float(then[key])


## Approval moves through PollNoise at BOTH ends. History stores the true figure;
## every approval the player has ever seen is a noised one, so a delta of true
## values would silently contradict the polls it sits next to -- and would leak
## the real number's movement, which is exactly what poll noise exists to hide.
## Same reasoning as polling_panel.gd's poll-against-poll change column.
static func approval_delta(state, months: int) -> float:
	var now := entry_at(state, 0)
	var then := entry_at(state, months)
	if now.is_empty() or then.is_empty():
		return NAN
	return _polled(now) - _polled(then)


static func _polled(entry: Dictionary) -> float:
	return PollNoise.displayed(
		PollNoise.poll_id(int(entry.get("year", 0)), int(entry.get("month", 1))),
		PollingPanel.HEADLINE_KEY,
		float(entry.get(APPROVAL_KEY, 0.0))
	)


## Every watched figure over the window, in WATCHED order. Each row is
## {key, label, unit, change, severity}: `change` is the signed movement as the
## player reads it, `severity` is that movement expressed as "how bad", positive
## meaning worse. Both are NAN when history is too short.
static func movements(state, months := TREND_MONTHS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for watch in WATCHED:
		var key: String = watch["key"]
		var change: float = approval_delta(state, months) if key == APPROVAL_KEY else delta(state, key, months)
		var severity := NAN
		if not is_nan(change):
			var worse: float = change if watch["worse_when_rising"] else -change
			severity = worse / float(watch["scale"])
		out.append({
			"key": key,
			"label": watch["label"],
			"unit": watch["unit"],
			"change": change,
			"severity": severity,
		})
	return out


## The figure moving worst, or {} when nothing has moved enough to be worth
## saying. Same row shape movements() returns.
static func worst(state, months := TREND_MONTHS) -> Dictionary:
	var found := {}
	for row in movements(state, months):
		if is_nan(row["severity"]) or float(row["severity"]) < NOTABLE_SEVERITY:
			continue
		if found.is_empty() or float(row["severity"]) > float(found["severity"]):
			found = row
	return found


## Months from the current game date to the given one. Negative or zero means it
## has arrived. Lives here rather than in a panel because two tabs and the lead
## line all need the same arithmetic.
static func months_until(state, year: int, month: int) -> int:
	return (year - int(state.year)) * 12 + (month - int(state.month))


## "3 months" / "1 month" / "this month", so callers do not each re-derive the
## plural and the zero case.
static func months_text(months: int) -> String:
	if months <= 0:
		return "this month"
	if months == 1:
		return "1 month"
	return "%d months" % months


## A signed change with its unit, or an em dash when there is no history to
## compare against.
static func change_text(change: float, unit := "pp") -> String:
	if is_nan(change):
		return "—"
	# Snapped, or a figure that fell by a thousandth of a point prints as "-0.0"
	# -- a minus sign in front of a zero, which reads as a bug.
	if absf(change) < 0.05:
		return "0.0 %s" % unit
	return "%+.1f %s" % [change, unit]
