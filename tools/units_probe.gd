extends SceneTree

## V5.3 c' slice C: the construction register's bands U3-U7 (docs/design/v5.3-c-register.md
## section 12). U1 and U2 are the balance table's (tools/balance_parallel.py, main against the
## branch, byte for byte); this probe prints the rest, each band against its pass rule.
##
## Run (isolated, AGENTS.md; BLOCS is a table, not a band):
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/units_probe.gd -- [--bands=U3,U5,BLOCS] [--seeds=200] [--json=PATH]
##
## THE MONTH IS THE GAME'S: every multi-month band ticks WorldMonth.tick_month (advance the
## clock, then tick, as tools/balance_probe.gd does), never a copy of the order. One
## exception, named where it runs: U6's shortcut count drives UnitBuild.tick_month alone
## over many seeds, because the cards depend on the programmes' own dates and nothing else
## the month writes; U6's stops are measured on the real month.
##
## THE VOTE IS STOOD IN: a programme is applied as a passed finance bill applies it
## (FinanceRows.apply over FinanceBill.drafted), at the month the regime tables it. The
## finance bill's own vote is the balance probe's business, not the register's.
##
## The nations are the ones with a stock file (loader.unit_stock): where the register is
## offered, which is the four playable today. No nation id below.
##
##   U3 the range        contract inside the shown range in every seed; the share of seeds
##                       with an overrun within 5 points of the odds shown.
##   U4 no dominant      band_units placed by need, by population, all in the largest region,
##      "where"          and the same money on the line's lever: no one best on every read;
##                       by need best on the worst region; the lever best on the nation per euro.
##   U5 a visible step   band_units in one region moves its figure >= 5 % in 3/4 of regions.
##   U6 the stops        a programme tabled every January for ten years: <= 2 overrun cards a
##                       year, <= 1 regional warning a month, a card holds only its last month;
##                       and the capped-card shortcut (unit_overrun.gd tick) counted.
##   U7 the envelope     never build: nothing paid, no number moves against a run with no
##                       envelope; open after the date: nothing; open in time: each row's
##                       category rate of its quoted cost.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")
const Units = preload("res://src/sim/units.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")
const UnitWarnings = preload("res://src/sim/unit_warnings.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const UK = preload("res://src/sim/units_constants.gd")

const STEP_SHARE := 0.05  # U5
const STEP_REGIONS := 0.75  # U5
const ODDS_POINTS := 0.05  # U3
const U6_YEARS := 10
const U6_REAL_SEEDS := 2

var _loader
var _seeds := 200
var _out := {}
var _verdicts := {}


func _init() -> void:
	var bands := ["U3", "U4", "U5", "U6", "U7", "BLOCS"]
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bands="):
			bands = arg.substr(8).split(",")
		elif arg.begins_with("--seeds="):
			_seeds = int(arg.substr(8))
		elif arg.begins_with("--json="):
			json_path = arg.substr(7)
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("units_probe: data did not load: %s" % [_loader.errors])
		quit(1)
		return
	for band in bands:
		call("_" + band.to_lower())
	print("")
	for band in bands:
		print("%s %s" % [band, "PASS" if bool(_verdicts.get(band, false)) else "FAIL"])
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"bands": _out, "verdicts": _verdicts}, "\t"))
	quit(0)


# --- U3 ----------------------------------------------------------------------

func _u3() -> void:
	var ok := true
	for nat in _nations():
		var state = _game(nat, 1)
		var ns = state.player()
		for type_id in _types(nat):
			var rows := Units.fill_by_need(ns, _loader, type_id, _band(type_id))
			var inside := 0
			var falls := 0
			var odds := 0.0
			for seed in range(1, _seeds + 1):
				ns.unit_programmes.clear()
				ns.unit_programme_seq = 0
				ns.draw_seed = seed
				var p := _vote(state, ns, type_id, rows)
				odds = float(p["odds"])
				if float(p["contract_eur_m"]) >= float(p["lo_eur_m"]) and float(p["contract_eur_m"]) <= float(p["hi_eur_m"]):
					inside += 1
				if p.has("overrun"):
					falls += 1
			var share := float(falls) / float(_seeds)
			var passed: bool = inside == _seeds and absf(share - odds) <= ODDS_POINTS
			ok = ok and passed
			_row("U3", "%s %s: inside %d/%d, overrun share %.3f vs odds %.3f %s" % [nat, type_id, inside, _seeds, share, odds, _mark(passed)],
				{"nation": nat, "type": type_id, "inside": inside, "seeds": _seeds, "share": share, "odds": odds})
	_verdicts["U3"] = ok


# --- U4 ----------------------------------------------------------------------

## Four ways to spend on one type, read at the programmes' opening: the worst region's
## figure, the nation's figure per euro paid, the capital paid, the Union's money.
func _u4() -> void:
	var ok := true
	for nat in _nations():
		for type_id in _types(nat):
			var n := _band(type_id)
			var probe = _game(nat, 1)
			var pns = probe.player()
			var largest := ""
			for id in _buildable(pns, type_id):
				if largest == "" or float(pns.region_pop_share.get(id, 0.0)) > float(pns.region_pop_share.get(largest, 0.0)):
					largest = id
			var ways := {"need": Units.fill_by_need(pns, _loader, type_id, n),
				"population": Units.fill_by_population(pns, _loader, type_id, n),
				"largest": [{"region": largest, "units": n}], "lever": []}
			var base_worst := _worst(pns, type_id)
			# The nation's figure drifts on its own over a build (need, income): each way's gain
			# is read against a run that spends nothing, at the same month.
			var idle := _spend(nat, type_id, "none", [])
			var reads := {}
			for way in ways:
				var r := _spend(nat, type_id, way, ways[way])
				r["per_euro"] = (float(r["nation"]) - float(idle["nation"])) / maxf(float(r["paid_eur_m"]) / 1000.0, 1e-9)
				reads[way] = r
			var better := _sign(type_id)
			# Higher is better for every read once oriented: the worst region and the nation
			# per euro by the figure's own sense, the capital as its negative, the Union as is.
			var best := {}
			for read in ["worst", "per_euro", "capital", "union"]:
				var top := ""
				for way in reads:
					var v := _oriented(read, reads[way], better)
					if top == "" or v > _oriented(read, reads[top], better) + 1e-12:
						top = way
				best[read] = top
			var dominant := ""
			for way in reads:
				if best.values().count(way) == best.size():
					dominant = way
			var passed: bool = dominant == "" and best["worst"] == "need" and best["per_euro"] == "lever"
			ok = ok and passed
			var parts: Array = []
			for way in reads:
				var r: Dictionary = reads[way]
				parts.append("%s worst %.3f nation %+.4f/bn capital %.0f M union %.0f M" % [way, float(r["worst"]),
					float(r["per_euro"]), float(r["capital"]), float(r["union"])])
			_row("U4", "%s %s (start worst %.3f): %s; best %s %s" % [nat, type_id, base_worst, "; ".join(parts), best, _mark(passed)],
				{"nation": nat, "type": type_id, "reads": reads, "best": best})
	_verdicts["U4"] = ok


func _spend(nat: String, type_id: String, way: String, rows: Array) -> Dictionary:
	var state = _game(nat, 1)
	var ns = state.player()
	var t: Dictionary = _loader.unit_types[type_id]
	var months := int(t["build_months"])
	var capital := 0.0
	var union := 0.0
	var raise := 0.0
	var line := String(t["line"])
	if way == "lever":
		# The same money as the by-need build's estimate, on the line, over the same months.
		var q := UnitPrice.quote(state, ns, _loader, {"type": type_id, "op": UK.OP_BUILD,
			"rows": Units.fill_by_need(ns, _loader, type_id, _band(type_id))})
		raise = 100.0 * float(q["estimate_eur_m"]) / float(months) * 12.0 / (float(ns.gdp_eur_bn) * 1000.0)
		Legislature.apply_effects(state, ns, {"spending_pct_gdp": {line: raise}}, _loader, "laws")
	elif way != "none":
		var p := _vote(state, ns, type_id, rows)
		union = float(p.get("union", {}).get("reserved_eur_m", 0.0))
	var paid := 0.0
	for i in months + 1:
		_month(state)
		var gdp_m := float(ns.gdp_eur_bn) * 1000.0
		paid += (ns.unit_bill_pct_gdp + ns.unit_running_total_pct_gdp() + raise) / 100.0 * gdp_m / 12.0
	if not ns.unit_programmes.is_empty():
		capital = float(ns.unit_programmes[0]["paid_eur_m"])
	return {"worst": _worst(ns, type_id), "nation": Units.national_figure(ns, _loader, type_id), "capital": capital,
		"union": union, "paid_eur_m": paid}


func _oriented(read: String, r: Dictionary, better: float) -> float:
	match read:
		"worst":
			return -better * float(r["worst"])
		"per_euro":
			return -better * float(r["per_euro"])
		"capital":
			return -float(r["capital"])
	return float(r["union"])


## The worst region's shown figure of the type.
func _worst(ns, type_id: String) -> float:
	var shown := Units.preview(ns, _loader, type_id, {})
	var out := NAN
	for id in _buildable(ns, type_id):
		var v := float(shown[id])
		if is_nan(out) or _sign(type_id) * v > _sign(type_id) * out:
			out = v
	return out


# --- U5 ----------------------------------------------------------------------

func _u5() -> void:
	var ok := true
	for nat in _nations():
		var state = _game(nat, 1)
		var ns = state.player()
		for type_id in _types(nat):
			var n := _band(type_id)
			var open := _buildable(ns, type_id)
			var steps := _steps(ns, type_id, open, n)
			var moved := _moved(steps)
			var passed: bool = float(moved) >= STEP_REGIONS * float(open.size())
			ok = ok and passed
			# The spec's fallback: the step declared from the measure, the smallest N that
			# passes, so the author sees the size the real stock asks for.
			var needed := n
			while not passed and needed < 1000 and float(_moved(_steps(ns, type_id, open, needed))) < STEP_REGIONS * float(open.size()):
				needed += 1
			steps.sort()
			_row("U5", "%s %s x%d: %d/%d regions move >= 5 %% (steps %s) %s%s" % [nat, type_id, n, moved, open.size(), steps, _mark(passed),
				"" if passed else "; the smallest N that passes: %d" % needed],
				{"nation": nat, "type": type_id, "units": n, "moved": moved, "regions": open.size(), "steps": steps, "needed": needed})
	_verdicts["U5"] = ok


## How far band-size units built in each region alone move that region's figure.
func _steps(ns, type_id: String, open: Array, n: int) -> Array:
	var out: Array = []
	for id in open:
		var before := Units.shown_figure(ns, _loader, type_id, id)
		var after := float(Units.preview(ns, _loader, type_id, {id: n})[id])
		out.append(snappedf(absf(after / before - 1.0), 0.001))
	return out


func _moved(steps: Array) -> int:
	var n := 0
	for s in steps:
		if float(s) >= STEP_SHARE:
			n += 1
	return n


# --- U6 ----------------------------------------------------------------------

func _u6() -> void:
	var ok := true
	for nat in _nations():
		for seed in range(1, U6_REAL_SEEDS + 1):
			var r := _yearly(nat, seed, true)
			var passed: bool = int(r["max_cards_a_year"]) <= UK.UNIT_OVERRUN_CARDS_A_YEAR and int(r["max_warnings_a_month"]) <= 1 \
				and int(r["holds_outside_last_month"]) == 0
			ok = ok and passed
			_row("U6", "%s seed %d (real month): %d programmes, %d refused, cards a year max %d, warnings a month max %d (%d in all), holds %d (outside a card's last month %d), overruns drawn %d posted %d dropped by the cap %d %s" % [
				nat, seed, int(r["tabled"]), int(r["refused"]), int(r["max_cards_a_year"]), int(r["max_warnings_a_month"]),
				int(r["warnings"]), int(r["holds"]), int(r["holds_outside_last_month"]), int(r["drawn"]), int(r["posted"]), int(r["dropped"]), _mark(passed)], r)
		# The shortcut: how often the year's cap turns a drawn overrun into no card at all,
		# over many seeds on the register's own month (UnitBuild alone, named above).
		var drawn := 0
		var dropped := 0
		var capped := 0
		for seed in range(1, _seeds + 1):
			var r := _yearly(nat, seed, false)
			drawn += int(r["drawn"])
			dropped += int(r["dropped"])
			capped += int(r["capped_years"])
		_row("U6", "%s shortcut over %d seeds x %d years (UnitBuild alone): overruns drawn %d, dropped by the cap %d (%.2f %%), years at the cap %d" % [
			nat, _seeds, U6_YEARS, drawn, dropped, 100.0 * float(dropped) / maxf(float(drawn), 1.0), capped],
			{"nation": nat, "seeds": _seeds, "drawn": drawn, "dropped": dropped, "capped_years": capped})
	_verdicts["U6"] = ok


## A regime that tables one programme every January for U6_YEARS, the types in turn, the
## band's size placed by need. `real`: the game's month; otherwise UnitBuild alone.
func _yearly(nat: String, seed: int, real: bool) -> Dictionary:
	var state = _game(nat, seed)
	var ns = state.player()
	var types := _types(nat)
	var r := {"tabled": 0, "refused": 0, "cards": {}, "warnings_by_month": {}, "warnings": 0, "holds": 0,
		"holds_outside_last_month": 0, "drawn": 0, "posted": 0, "dropped": 0, "capped_years": 0}
	for i in U6_YEARS * 12:
		if int(state.month) == 1:
			var type_id: String = types[(int(state.year) - 2026) % types.size()]
			var rows := Units.fill_by_need(ns, _loader, type_id, _band(type_id))
			if UnitBuild.refusal(state, ns, _loader, [{"type": type_id, "op": UK.OP_BUILD, "rows": rows}]) == "":
				_vote(state, ns, type_id, rows)
				r["tabled"] = int(r["tabled"]) + 1
			else:
				r["refused"] = int(r["refused"]) + 1
		var notes: Array = []
		if real:
			_month(state)
			# The month's report is consumed inside _month; re-read the stamps it left.
			notes = _last_units
		else:
			_advance(state)
			notes = UnitBuild.tick_month(state, _loader)
		var now := UnitBuild.now(state)
		for n in notes:
			if String(n["kind"]) == "overrun_landed":
				r["cards"][state.year] = int(r["cards"].get(state.year, 0)) + 1
			if String(n["kind"]) == UnitWarnings.KIND:
				r["warnings_by_month"][now] = int(r["warnings_by_month"].get(now, 0)) + 1
				r["warnings"] = int(r["warnings"]) + 1
		# A card holds the clock in its last month only (section 9): a waiting card at due - 1.
		for p in ns.unit_programmes:
			var ask: Dictionary = p.get("ask", {})
			if not ask.is_empty() and not p.has("answer") and now < int(ask["due"]):
				if now == int(ask["due"]) - 1:
					r["holds"] = int(r["holds"]) + 1
	for p in ns.unit_programmes:
		if p.has("overrun"):
			r["drawn"] = int(r["drawn"]) + 1
			if p.has("ask"):
				r["posted"] = int(r["posted"]) + 1
			elif String(p["state"]) == UK.STATE_DONE:
				r["dropped"] = int(r["dropped"]) + 1
	for y in r["cards"]:
		if int(r["cards"][y]) >= UK.UNIT_OVERRUN_CARDS_A_YEAR:
			r["capped_years"] = int(r["capped_years"]) + 1
	r["max_cards_a_year"] = (r["cards"].values() as Array).max() if not r["cards"].is_empty() else 0
	r["max_warnings_a_month"] = (r["warnings_by_month"].values() as Array).max() if not r["warnings_by_month"].is_empty() else 0
	r.erase("cards")
	r.erase("warnings_by_month")
	return r


# --- U7 ----------------------------------------------------------------------

func _u7() -> void:
	var ok := true
	for nat in _nations():
		var probe = _game(nat, 1)
		var org := UnitEnvelope.org_of(_loader, probe.player())
		if org == "":
			_row("U7", "%s: no co-financing organisation, nothing to test" % nat, {"nation": nat, "member": false})
			continue
		# Never build: nothing paid, and the run reads as one with no envelope at all.
		var with_env := _idle(nat, true)
		var without := _idle(nat, false)
		var same := String(with_env["nation"]) == String(without["nation"])
		ok = ok and same and float(with_env["receipt_max"]) == 0.0
		_row("U7", "%s never builds: receipt max %.6f, lapse notes %d, identical to a run with no envelope: %s %s" % [
			nat, float(with_env["receipt_max"]), int(with_env["lapse_notes"]), same, _mark(same and float(with_env["receipt_max"]) == 0.0)],
			{"nation": nat, "idle": with_env})
		for type_id in _types(nat):
			if not bool(_loader.unit_types[type_id].get("cofinanced", false)):
				continue
			# In time: voted at the start if the build opens by the period's last payment year,
			# else in the first January of the next period (a 48-month hospital voted in 2026
			# opens in 2030, after the first period's 2029).
			var start := UnitEnvelope.period_of(_loader, org, 2026)
			var vote_year := 2026
			if 2026 + int(ceilf(float(_loader.unit_types[type_id]["build_months"]) / 12.0)) > int(start["pays_until_year"]):
				vote_year = int(start["last_year"]) + 1
			var early := _cofinanced(nat, type_id, vote_year, 1)
			# Late: voted in the period's last year, so the build opens after its payment year.
			var period := UnitEnvelope.period_of(_loader, org, 2026)
			var late := _cofinanced(nat, type_id, int(period["last_year"]), 12)
			var pass_early: bool = absf(float(early["paid"]) - float(early["want"])) <= 1e-6 * maxf(1.0, float(early["want"])) and float(early["want"]) > 0.0
			var pass_late: bool = float(late["paid"]) == 0.0 and float(late["reserved"]) == 0.0
			ok = ok and pass_early and pass_late
			_row("U7", "%s %s in time: paid %.2f M of the categories' rate %.2f M %s; opened %s after %d (pays until %d): paid %.2f M %s" % [
				nat, type_id, float(early["paid"]), float(early["want"]), _mark(pass_early), late["opened"], int(period["last_year"]),
				int(period["pays_until_year"]), float(late["paid"]), _mark(pass_late)], {"nation": nat, "type": type_id, "early": early, "late": late})
	_verdicts["U7"] = ok


func _idle(nat: String, envelope: bool) -> Dictionary:
	var saved: Dictionary = _loader.unit_cofinancing
	if not envelope:
		_loader.unit_cofinancing = {}
	var state = _game(nat, 1)
	var ns = state.player()
	var receipt_max := 0.0
	var lapse := 0
	for i in 60:
		_month(state)
		receipt_max = maxf(receipt_max, absf(ns.unit_receipt_pct_gdp))
		for n in _last_units:
			if String(n["kind"]) == "lapse_warning":
				lapse += 1
	_loader.unit_cofinancing = saved
	# The whole nation, saved as a save writes it: any number the envelope moved shows here.
	return {"receipt_max": receipt_max, "lapse_notes": lapse if envelope else 0,
		"nation": JSON.stringify(ns.to_dict()).sha256_text()}


func _cofinanced(nat: String, type_id: String, year: int, month: int) -> Dictionary:
	var state = _game(nat, 1)
	var ns = state.player()
	while UnitBuild.now(state) < year * 12 + month:
		_month(state)
	var rows := Units.fill_by_need(ns, _loader, type_id, _band(type_id))
	var p := _vote(state, ns, type_id, rows)
	var reserved := float(p.get("union", {}).get("reserved_eur_m", 0.0))
	# Each row's category rate of its quoted cost, read here from the data, not the envelope.
	var org := UnitEnvelope.org_of(_loader, ns)
	var rates: Dictionary = _loader.unit_cofinancing[org]["rates"]
	var category := {}
	for r in _loader.regions[nat]:
		category[r.id] = r.cohesion_category
	var cost := float(_loader.unit_types[type_id]["cost_eur_m"][nat])
	var want := 0.0
	for r in p["rows"]:
		want += float(rates.get(String(category.get(r["region"], "")), 0.0)) * float(r["units"]) * cost \
			* (1.0 + float(p.get("surcharge", {}).get(r["region"], 0.0)))
	# The rate is on the cost as built (the contract over the estimate), never more than the
	# estimate's rate, nor than the period's envelope (unit_envelope.gd reserve() and opening()).
	want = minf(minf(want, want * float(p["contract_eur_m"]) / float(p["estimate_eur_m"])),
		UnitEnvelope.envelope_eur_m(UnitEnvelope.period_of(_loader, org, int(state.year)), nat))
	for i in int(p["build_months"]) + UK.UNIT_RECEIPT_MONTHS + 2:
		_month(state)
	return {"reserved": reserved, "want": want, "paid": float(p.get("union", {}).get("paid_eur_m", 0.0)),
		"opened": "%d-%02d" % [UnitEnvelope.year_of(int(p.get("opened", 0))), (int(p.get("opened", 1)) - 1) % 12 + 1]}


# --- BLOCS (a table for the author, no pass rule) -------------------------------

## What the vote moves on the blocs (UnitBuild.blocs, the parent's ruling on slice C) for
## 1, 3 and the band's units in the region furthest behind, and 40 placed by population.
func _blocs() -> void:
	for nat in _nations():
		var state = _game(nat, 1)
		var ns = state.player()
		for type_id in _types(nat):
			var first := String(Units.fill_by_need(ns, _loader, type_id, 1)[0]["region"])
			var sizes := {"1 in %s" % first: [{"region": first, "units": 1}], "3 in %s" % first: [{"region": first, "units": 3}],
				"%d (band) in %s" % [_band(type_id), first]: [{"region": first, "units": _band(type_id)}],
				"40 by population": Units.fill_by_population(ns, _loader, type_id, 40)}
			for label in sizes:
				var moves := UnitBuild.blocs(ns, _loader, {"type": type_id, "op": UK.OP_BUILD, "rows": sizes[label]})
				var parts: Array = []
				for bloc in moves:
					parts.append("%s %+.4f" % [bloc, float(moves[bloc])])
				_row("BLOCS", "%s %s, %s: %s" % [nat, type_id, label, ", ".join(parts)],
					{"nation": nat, "type": type_id, "size": label, "moves": moves})
	_verdicts["BLOCS"] = true


# --- helpers -----------------------------------------------------------------

var _last_units: Array = []


func _month(state) -> void:
	_advance(state)
	_last_units = WorldMonth.tick_month(state, _loader).get("units", [])


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _game(nat: String, seed: int):
	var state = GameState.new_game(_loader, nat)
	state.year = 2026
	state.month = 1
	state.player().draw_seed = seed
	return state


func _vote(state, ns, type_id: String, rows: Array) -> Dictionary:
	var row := {"type": type_id, "op": UK.OP_BUILD, "rows": rows.duplicate(true)}
	FinanceRows.apply(state, _loader, ns, FinanceBill.drafted(state, _loader, {FinanceRows.UNITS: [row]}))
	return ns.unit_programmes[ns.unit_programmes.size() - 1]


func _nations() -> Array:
	var out: Array = _loader.unit_stock.keys()
	out.sort()
	return out


func _types(nat: String) -> Array:
	var out: Array = []
	for type_id in _loader.unit_types:
		if Units.offered(_loader, nat, type_id):
			out.append(type_id)
	out.sort()
	return out


func _band(type_id: String) -> int:
	return int(_loader.unit_types[type_id]["band_units"])


func _sign(type_id: String) -> float:
	return 1.0 if String(_loader.unit_types[type_id]["figure"]["better"]) == "lower" else -1.0


func _buildable(ns, type_id: String) -> Array:
	var out: Array = []
	for r in _loader.regions.get(ns.id, []):
		if Units.start_capacity(_loader, ns.id, type_id, r.id) > 0.0:
			out.append(String(r.id))
	return out


func _mark(passed: bool) -> String:
	return "ok" if passed else "MISS"


func _row(band: String, line: String, data: Dictionary) -> void:
	print("%s %s" % [band, line])
	(_out.get_or_add(band, []) as Array).append(data)
