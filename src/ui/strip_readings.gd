extends RefCounted

## V4.8a. The top bar's readings as ONE register -- the strip is this list rather
## than a dozen hand-built figures (docs/tiers/v4.md §V4.8: "this is where the strip
## becomes one thing rather than twelve"). Static and read-only over GameState, the
## shape of pending.gd; top_bar.gd draws whatever read() returns and knows nothing
## about any one reading.
##
## A tooltip SURFACES a figure an existing query already computes -- Trends' six-
## month deltas, Elections.attribution, Inflation.inflation_deviation,
## Government.majority_seats, the org and queue registers -- and never recomputes
## one (the author's call at the V4.8a plan gate, 2026-10-17: no src/sim/ diff).
## Where nothing computes a breakdown, the tip says what the number is and stops,
## rather than inventing a decomposition the machine does not make.
##
## Each read returns {text, tip, visible, alert_window} and, for the programme,
## a caption. `alert_window` is the window that answers a reading in a bad state;
## the bar turns the figure alert-toned and names that window with its real key.
## Only readings with a threshold the game already holds can alert -- an alert on
## a line this file drew would be taste, not the machine.

const Trends = preload("res://src/ui/trends.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const CommoditiesPanel = preload("res://src/ui/commodities_panel.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Elections = preload("res://src/sim/elections.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Government = preload("res://src/sim/government.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")

## Strip order: standing, money, the economy, the country, the assembly, the clock,
## the desk, the world. People left at V4.8b: a count of people the term has moved is
## a margin note, not a standing figure, and the outliner lists them by name.
##
## Thirteen on one line needed 2219 px on a 1920 screen (tests/test_strip_readings.gd's
## width check, 2026-10-17); the figures went two-line instead -- caption above
## value, U2's shape -- the author's call at that measurement.
const ORDER: Array[String] = [
	"approval", "deficit", "gdp", "unemployment", "inflation", "unrest",
	"assembly", "election", "programme", "desk", "europe", "commodities",
]

## B10 (playtest 2026-09-16): "Budget balance", not "Deficit" -- the value is
## signed, and "DEFICIT +10.50%" was a live contradiction on screen.
const CAPTIONS := {
	"approval": "Approval", "deficit": "Budget balance", "gdp": "GDP",
	"unemployment": "Unemployment", "inflation": "Inflation", "unrest": "Unrest",
	"assembly": "Assembly", "election": "Next vote", "programme": "Programme",
	"desk": "Desk", "europe": "Europe", "commodities": "Supplies",
}

## The NationState fields each reading's text or tip is read from.
## tests/test_strip_readings.gd perturbs every one and requires the reading to
## move -- a tip that stopped reading its input fails there, not in a playtest.
const INPUTS := {
	"approval": ["overall_approval_pct"],
	"deficit": ["deficit_pct_gdp", "debt_eur_bn"],
	"gdp": ["gdp_eur_bn", "growth_annual_pct"],
	"unemployment": ["unemployment_pct"],
	"inflation": ["inflation_pct"],
	"unrest": ["unrest_pct"],
	"assembly": ["coalition_seats"],
	"desk": ["event_queue"],
}

## Trends' own window, so the strip and the Overview cannot disagree about "lately".
const WINDOW := Trends.TREND_MONTHS

## The caller guarantees state.player() is not null (top_bar.gd returns early on
## a bad player id -- playability-audit Register B's crash row).
static func read(id: String, state, loader) -> Dictionary:
	var ns = state.player()
	match id:
		"approval":
			return _approval(state, ns)
		"deficit":
			return _deficit(state, ns)
		"gdp":
			return _gdp(state, ns)
		"unemployment":
			return _unemployment(state, ns)
		"inflation":
			return _inflation(ns)
		"unrest":
			return _unrest(ns)
		"assembly":
			return _assembly(ns)
		"election":
			return _election(state, ns, loader)
		"programme":
			return _programme(ns, loader)
		"desk":
			return _desk(ns)
		"europe":
			return _europe(state, ns)
		"commodities":
			return _commodities(ns, loader)
	return _reading("—", "")


## A reading whose tip is plain text: one level-1 line per row of it, none opening
## a child. A reading with a breakdown builds its lines itself (_reading_lines).
static func _reading(text: String, tip: String, visible := true, alert_window := "") -> Dictionary:
	var lines: Array = []
	if not tip.is_empty():
		for row in tip.split("\n"):
			lines.append(_line(row))
	return {"text": text, "tip": tip, "visible": visible, "alert_window": alert_window, "lines": lines}


## V4.8b. `lines` is the structured tip -- {text, child_id}, child_id "" for a line
## with nothing under it -- and `tip` is those texts joined, so the popup that draws
## the lines and the plain tip the walker reads are one source.
static func _reading_lines(text: String, lines: Array, visible := true, alert_window := "") -> Dictionary:
	var texts: Array[String] = []
	for line in lines:
		texts.append(String(line["text"]))
	return {
		"text": text, "tip": "\n".join(texts), "visible": visible,
		"alert_window": alert_window, "lines": lines,
	}


static func _line(text: String, child_id := "") -> Dictionary:
	return {"text": text, "child_id": child_id}


## The polled figure, PollNoise at both ends -- the same read the portrait card
## makes, so the face and the strip cannot print two approvals. The tip names the
## issues Elections.attribution already ranks: the explanation the result screen
## gives, surfaced before the vote rather than after it.
static func _approval(state, ns) -> Dictionary:
	var shown := PollNoise.displayed(
		PollNoise.poll_id(state.year, state.month), PollingPanel.HEADLINE_KEY, ns.overall_approval_pct)
	var change := Trends.approval_delta(state, WINDOW)
	var lines: Array = [
		_line("Polled approval, %s over %d months." % [Trends.change_text(change), WINDOW]),
	]
	for row in Elections.attribution(ns):
		lines.append(_line("%s: %.0f%% of minds, satisfaction %+.2f" % [
			OpinionK.ISSUE_LABEL.get(row["issue"], String(row["issue"])),
			float(row["salience"]) * 100.0, float(row["satisfaction"]),
		], "issue:%s" % row["issue"]))
	return _reading_lines("%.0f%%%s" % [shown, _arrow(change)], lines)


## Balance on the figure, the debt path in the tip -- "treasury and the debt path"
## is one reading in the tier doc, and a second figure for debt would be a number
## the player cannot act on apart from the balance that moves it.
static func _deficit(state, ns) -> Dictionary:
	var debt_change := Trends.delta(state, "debt_to_gdp_pct", WINDOW)
	var lines: Array = [
		_line("Surplus is +, deficit is −."),
		_line("Debt %.0f Bn, %.0f%% of GDP, %s over %d months." % [
			ns.debt_eur_bn, ns.debt_to_gdp_pct(), Trends.change_text(debt_change), WINDOW,
		], "debt"),
	]
	return _reading_lines("%+.2f%%" % -ns.deficit_pct_gdp, lines)


## The arrow is GDP's own six-month change -- every arrow on the strip means
## "this figure, over Trends' window", so one glyph never means two things (the
## review caught a rate-sign arrow beside approval's change arrow).
static func _gdp(state, ns) -> Dictionary:
	var tip := "Growth %.2f%% a year, %s over %d months." % [
		ns.growth_annual_pct,
		Trends.change_text(Trends.delta(state, "growth_annual_pct", WINDOW)), WINDOW,
	]
	return _reading("%.0f Bn%s" % [ns.gdp_eur_bn, _arrow(Trends.delta(state, "gdp_eur_bn", WINDOW))], tip)


static func _unemployment(state, ns) -> Dictionary:
	var tip := "Unemployment, %s over %d months." % [
		Trends.change_text(Trends.delta(state, "unemployment_pct", WINDOW)), WINDOW,
	]
	return _reading("%.2f%%" % ns.unemployment_pct, tip)


## One decimal on the level, two on the drift -- economy_panel.gd's screenshot
## finding: the whole reachable deviation is 0.145 points, so one decimal on it
## prints "+0.0" against a live, moved figure.
static func _inflation(ns) -> Dictionary:
	return _reading("%.1f%%" % ns.inflation_pct,
		"Inflation, %+.2f points since the start." % Inflation.inflation_deviation(ns))


## Zero is a real level here (nobody is angry), not an absence, so it prints. The
## bar beside it is UNREST_THRESHOLD_PCT -- economy_panel's own line -- and past
## it the unions organise, which is the alert.
static func _unrest(ns) -> Dictionary:
	var striking: bool = ns.unrest_pct >= UnrestK.UNREST_THRESHOLD_PCT
	var tip := "Grievance %.0f of 100. Organised action at %.0f." % [
		ns.unrest_pct, UnrestK.UNREST_THRESHOLD_PCT,
	]
	return _reading("%.0f" % ns.unrest_pct, tip, true, "economy" if striking else "")


## The margin a president reads: seats beyond the bare majority, signed -- "+0" is
## exactly enough, "-1" one short. A majority needs MORE than majority_seats
## (Government's own line, which the Politics panel prints), so the bare majority
## is majority_seats + 1; the first version subtracted majority_seats alone and
## read "+0" for a government one seat short.
static func _assembly(ns) -> Dictionary:
	if ns.assembly_seats <= 0:
		return _reading("—", "No assembly arithmetic for this nation.")
	var majority := Government.majority_seats(ns)
	var margin: int = ns.coalition_seats - (majority + 1)
	var standing := "Majority government"
	if ns.is_cohabitation:
		standing = "Cohabitation — the assembly majority is against you"
	elif ns.is_minority:
		standing = "Minority government"
	var tip := "%s. %d of %d seats; a majority needs more than %d." % [
		standing, ns.coalition_seats, ns.assembly_seats, majority,
	]
	var troubled: bool = ns.is_cohabitation or ns.is_minority
	return _reading_lines("%+d" % margin, [_line(tip, "coalition")], true, "politics" if troubled else "")


## Count, not date: the number ticking down is the urgency; the Overview's date
## line and the Diary carry the calendar. Same query as theirs, so the three
## surfaces cannot disagree again.
##
## B1 (playtest 2026-09-16): months_to_vote can legally go negative once the date
## has passed and the next schedule has not been drawn -- the raw int printed
## "NEXT VOTE -44 mo" in two ten-year captures. The figure clamps to a dash.
static func _election(state, ns, loader) -> Dictionary:
	var months := Trends.months_to_vote(state, ns)
	var text := "—"
	if months > 0:
		text = "%d mo" % months
	elif months == 0:
		text = "now"
	return _reading(text, _election_tooltip(ns, loader, months))


## B3: months_to_vote counts the EXECUTIVE clock where the nation elects one
## separately, the single chamber's schedule where it does not (trends.gd's note),
## while the Polling panel counts the assembly's -- both correct, so the tip names
## which vote this figure counts. Off the loader's nation data; no nation-specific
## copy. Without a loader the wording stays generic.
static func _election_tooltip(ns, loader, months: int) -> String:
	if months < 0:
		# No "Win it." here: the vote the player was supposed to win is over.
		return "The vote that ends your term has been held."
	var what := "vote"
	if loader != null and loader.nations.has(ns.id):
		var nation = loader.nations[ns.id]
		if bool(ns.has_executive):
			what = "vote for %s" % nation.executive_title
		else:
			what = "vote for the %s" % nation.chamber_name
	return "The %s that ends your term -- %s. Win it." % [what, Trends.months_text(months)]


## V4.1. The chosen programme's name (as the caption) and its nearest-deadline
## entry's progress. Hidden while nothing runs, the defence-allies rule: a
## permanent "no programme" slot says nothing in every game that never opens the
## Agenda, which is most of them. Derived off the same read the Agenda window
## draws, so the panel and the strip cannot print two answers to one question.
static func _programme(ns, loader) -> Dictionary:
	var programme := _nearest_programme(ns, loader)
	if programme.is_empty():
		return _reading("—", "", false)
	var terms: Dictionary = programme["terms"]
	var live: Dictionary = programme["entry"]
	var name_text := String(terms.get("name", String(live["entry_id"])))
	var progress: Dictionary = Programme.progress_of(ns, terms)
	var fraction := PanelKit.progress_fraction(
		float(progress["current_value"]), float(progress["goal_value"]), String(progress["progressbar"]))
	var tip := "%s -- %.2f against a %.2f goal" % [
		name_text, float(progress["current_value"]), float(progress["goal_value"]),
	]
	var clock_text := programme_clock_text(terms, live)
	if not clock_text.is_empty():
		tip += " · %s" % clock_text
	var out := _reading_lines("%.0f%%" % (fraction * 100.0), [_line(tip, "entries")])
	out["caption"] = name_text
	return out


## The register entry the strip prices: the live one with the nearest deadline,
## or the first live one when none carries a clock.
static func _nearest_programme(ns, loader) -> Dictionary:
	var best := {}
	var best_left := 1 << 30
	for entry in ns.programme:
		if String(entry["status"]) != ProgrammeK.STATUS_ACTIVE:
			continue
		var terms: Dictionary = Programme.terms_of(loader, String(entry["entry_id"]))
		if terms.is_empty():
			continue
		var timeout := int(terms.get("timeout_months", 0))
		# A deadline always beats a no-deadline entry; no-deadline entries keep
		# register order, which is the order the player chose them in.
		var left := timeout - int(entry["months_live"])
		var score := left if timeout > 0 else (1 << 30) - 1
		if best.is_empty() or score < best_left:
			best = {"terms": terms, "entry": entry}
			best_left = score
	return best


static func programme_clock_text(terms: Dictionary, live: Dictionary) -> String:
	var timeout := int(terms.get("timeout_months", 0))
	if timeout <= 0:
		return ""
	var left := timeout - int(live["months_live"])
	if left <= 0:
		return "its deadline is now"
	return "%s to its deadline" % ("1 month" if left == 1 else "%d months" % left)


## V4.4. The desk, read straight off the queue register -- the same read
## Events.is_pending() makes for the brass mark, so the strip and the mark cannot
## disagree about whether something is waiting. Deliberately NOT hidden when empty:
## the glance this serves is "is anything waiting on me", and hiding the figure
## answers that by not asking it. A critical on the desk is the alert.
static func _desk(ns) -> Dictionary:
	var desk: Array = ns.event_queue
	if desk.is_empty():
		# Em dash, not "0 pending": a confident zero here would be V1.6d's lie in
		# the strip's own handwriting.
		return _reading("— clear", "Nothing awaits an answer.")
	var by_severity := {}
	for entry in desk:
		var severity := int(entry.get("severity", 1))
		by_severity[severity] = int(by_severity.get(severity, 0)) + 1
	var critical := int(by_severity.get(3, 0)) > 0
	return _reading_lines("%d pending" % desk.size(), [_line(_desk_tooltip(by_severity), "queue")], true,
		"events" if critical else "")


## A critical is named outright -- the one line a president must not have to
## decode -- and any other desk reads as a count by severity. The names are
## events_constants' SEVERITY_NAMES (1 minor, 2 major, 3 critical), not new copy.
static func _desk_tooltip(by_severity: Dictionary) -> String:
	var parts: Array[String] = []
	for severity in [3, 2, 1]:
		var count := int(by_severity.get(severity, 0))
		if count > 0:
			parts.append("%d %s" % [count, EventsK.SEVERITY_NAMES[severity - 1]])
	return " · ".join(parts) if not parts.is_empty() else "On the desk."


## V4.5b2. The council standing off the registers: the treaty awaiting the
## assembly (state.orgs[..].ratifying), the one burden price, the rules in force
## and the IOUs owed. Hidden for a player in no council org -- a standing "— clear"
## there would claim a Europe the nation is not part of. A treaty awaiting the
## player's assembly is the alert: an idle player kills it by default and pays.
static func _europe(state, ns) -> Dictionary:
	var council: Array = Orgs.council_ids(state)
	var mine: Array = []
	for org_id in council:
		if ns.orgs.has(org_id):
			mine.append(org_id)
	if mine.is_empty():
		return _reading("—", "", false)

	var burden := Orgs.burden(state, ns, council)
	var rules: Array = Orgs.rules_in_force(state, ns)
	var breached := 0
	for rule in rules:
		if float(rule.get("breach", 0.0)) > 0.0:
			breached += 1

	var owed := 0
	var treaty_text := ""
	var treaty_left := -1
	for org_id in mine:
		var org_state: Dictionary = state.orgs[org_id]
		for debt in (org_state.get("debts", []) as Array):
			if String(debt.get("debtor", "")) == ns.id:
				owed += 1
		var r: Dictionary = org_state.get("ratifying", {})
		if not r.is_empty() and String((r.get("nations", {}) as Dictionary).get(ns.id, "")) == CouncilK.RATIFY_PENDING:
			var left := int(r.get("months_left", 0))
			if treaty_left < 0 or left < treaty_left:
				treaty_left = left
				treaty_text = "%s, %s" % [String(r.get("name", "")),
					"1 month left" if left == 1 else "%d months left" % left]

	var text := "— clear"
	if treaty_left >= 0:
		text = "Treaty: %dm" % treaty_left
	elif burden > 0.0:
		text = "Burden %.2f" % burden

	var lines: Array = [
		_line("The councils you sit on."),
		_line("Burden %.2f" % burden),
		_line(("1 rule in force binds you, %d breached" % breached) if rules.size() == 1 \
			else ("%d rules in force bind you, %d breached" % [rules.size(), breached]),
			"rules" if not rules.is_empty() else ""),
		_line("%d %s owed" % [owed, "IOU" if owed == 1 else "IOUs"]),
		_line(("Treaty awaiting your assembly: %s" % treaty_text) if treaty_left >= 0 else "No treaty awaiting you"),
	]
	return _reading_lines(text, lines, true, "orgs" if treaty_left >= 0 else "")


## V4.6's interim entry, owed and missing until V4.8a: the worst-covered good,
## read through the commodities panel's own coverage() so the strip and the
## panel's SHORTAGES section cannot disagree. Ties break by id, the panel's own
## total order. Hidden before the first month has any commodity state.
static func _commodities(ns, loader) -> Dictionary:
	if ns.commodity_state.is_empty() or loader == null:
		return _reading("—", "", false)
	var worst_id := ""
	var worst := 2.0
	for good_id in loader.commodity_goods.keys():
		var c := CommoditiesPanel.coverage(ns, String(good_id))
		if c < worst or (is_equal_approx(c, worst) and String(good_id) < worst_id):
			worst = c
			worst_id = String(good_id)
	var bar := CommoditiesPanel.SHORTAGE_COVERAGE * 100.0
	if worst_id.is_empty() or worst >= CommoditiesPanel.SHORTAGE_COVERAGE:
		return _reading("— covered", "Every good above %.0f%% of the month's demand." % bar)
	var good = loader.commodity_goods.get(worst_id)
	var name := String(good.name) if good != null else worst_id
	return _reading_lines("%s %.0f%%" % [name, worst * 100.0], [_line(
		"%s covers %.0f%% of the month's demand -- the shortage line is %.0f%%." % [name, worst * 100.0, bar],
		"short")], true, "commodities")


## ▲/▼ beside a figure; nothing for NAN or a move under Trends' own snap.
static func _arrow(change: float) -> String:
	if is_nan(change) or absf(change) < 0.05:
		return ""
	return " ▲" if change > 0.0 else " ▼"
