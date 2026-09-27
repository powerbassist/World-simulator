extends SceneTree

## V4.7 step-0 probe -- the handoff's "re-measure what a verb moves at
## major-scale shares vs body-scale", run before any plan code exists.
## docs/companies-model.md section 2 and section 8 read cold first; this probe
## quantifies WHY the register must split into two tiers: at a hundred-plus
## firms per nation the average share is ~1 %, and the measured question is
## whether a verb pointed at such a firm can move anything a player can read.
##
## THE BAND, DECLARED BEFORE THE RUN (V1.4b's own readable floor, and its
## noise side: polling headline floor is +/-3.0 points, jobs floor 0.05 pts):
##   MAJOR  -- subsidise FRA_aurignac (authored share 0.14, industry) to
##             intensity 1.0 for 60 months. Must CLEAR the floor:
##             |jobs| >= 0.05 pts at month 60 OR peak |impulse| >= 0.05 %/yr.
##   BODY   -- a synthetic firm at share 0.01 (the average the ~2,500-body
##             register implies), headcount scaled off the named register's
##             jobs-per-share, same verb, same 60 months. Must land SUB-NOISE:
##             |jobs| < 0.02 pts AND peak |impulse| < 0.01 %/yr.
## A major below the floor or a body firm above it each kill the two-tier
## design's premise from opposite directions, so the probe verdicts on both.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")

const PLAYER := "FRA"
const MAJOR := "FRA_aurignac"
const BODY_ID := "FRA_bodyprobe"
const MONTHS := 60

var _loader
var _lines: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_line("DATA DID NOT LOAD CLEANLY: %s" % [_loader.errors])
		_finish(1)
		return

	# The body-scale stand-in is appended to the in-memory loader list AFTER
	# load_all(): _validate_companies() has already run, the quiet baseline keeps
	# every channel at exactly 0.0 for a never-touched firm, and no data file is
	# edited. headcount is scaled off the named register's own jobs-per-share so
	# the body firm is a fair average, not a straw one.
	# V4.7a: the stand-in is a real Company (a raw Dictionary crashes is_major's
	# typed read) tiered MAJOR so the verb can reach it -- available()'s tier
	# gate refuses body firms since the A1 fix wave, and the probe's question is
	# SHARE SCALE, not tier: what does a verb on a 0.01-share firm do. That the
	# body tier itself is refused is pinned in tests/test_companies_tiers.gd;
	# this probe measures the pre-gate world the finding came from, which is
	# the evidence the gate exists for.
	var jobs_per_share := 0.0
	for c in _loader.companies[PLAYER]:
		jobs_per_share += float(c.headcount) / float(c.share)
	jobs_per_share /= float(_loader.companies[PLAYER].size())
	var body_headcount := int(round(jobs_per_share * 0.01))
	var probe_errors: Array[String] = []
	var stand_in = preload("res://src/core/company.gd").from_dict({
		"id": BODY_ID, "name": "Bodyprobe", "sector": "industry",
		"share": 0.01, "headcount": body_headcount,
		"city": "FRI_paris", "tier": "major",
	}, 0, "probe", probe_errors)
	_loader.companies[PLAYER].append(stand_in)
	_line("body stand-in: share 0.01, headcount %d (register mean jobs/share %.0f)" % [
		body_headcount, jobs_per_share])

	var major := _run_one(MAJOR)
	var body := _run_one(BODY_ID)

	_line("")
	_line("channel            MAJOR(0.14)   BODY(0.01)")
	_line("peak impulse %%/yr   %10.4f   %10.4f" % [major.peak_impulse, body.peak_impulse])
	_line("jobs pts @mo60      %10.4f   %10.4f" % [major.jobs_pts, body.jobs_pts])
	_line("share endpoint      %10.4f   %10.4f" % [major.share_end, body.share_end])
	_line("bill %%GDP @mo60     %10.4f   %10.4f" % [major.bill, body.bill])
	_line("")

	var major_ok := absf(major.jobs_pts) >= 0.05 or absf(major.peak_impulse) >= 0.05
	var body_ok := absf(body.jobs_pts) < 0.02 and absf(body.peak_impulse) < 0.01
	_line("MAJOR clears the readable floor:  %s" % ["PASS" if major_ok else "FAIL"])
	_line("BODY lands sub-noise (theatre):   %s" % ["PASS" if body_ok else "FAIL"])
	_finish(0 if (major_ok and body_ok) else 1)


## Quiet and subsidised states from the same loader, driven the way
## tests/test_companies.gd drives them (Economy + Companies per month).
func _run_one(firm_id: String) -> Dictionary:
	var quiet = GameState.new_game(_loader, PLAYER)
	var sub = GameState.new_game(_loader, PLAYER)
	var action = null
	for a in _loader.company_actions:
		if a.id == "strategic_rescue":
			action = a
	Companies.execute(sub, sub.nations[PLAYER], _loader.company_actions, action, firm_id, _loader)
	Companies.tick_month(sub, _loader)

	var peak_impulse := 0.0
	var q_u: float = quiet.nations[PLAYER].unemployment_pct
	var s_u: float = sub.nations[PLAYER].unemployment_pct
	for _m in range(MONTHS):
		Economy_tick(quiet)
		Economy_tick(sub)
		Companies.tick_month(sub, _loader)
		peak_impulse = maxf(peak_impulse, absf(float(sub.nations[PLAYER].firm_impulse_pct)))
		q_u = quiet.nations[PLAYER].unemployment_pct
		s_u = sub.nations[PLAYER].unemployment_pct

	var share_end := Companies.share_of(sub.nations[PLAYER], firm_id)
	return {
		"peak_impulse": peak_impulse,
		"jobs_pts": s_u - q_u,
		"share_end": share_end,
		"bill": float(sub.nations[PLAYER].subsidy_bill_pct_gdp),
	}


## Economy.tick_month() is the month the tests drive; kept as a helper so the
## probe's loop reads as the pair it is.
func Economy_tick(state) -> void:
	preload("res://src/sim/economy.gd").tick_month(state)


func _line(s: String) -> void:
	_lines.append(s)
	print(s)


func _finish(code: int) -> void:
	var f := FileAccess.open("res://reports/industry_step0_probe.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	quit(code)
