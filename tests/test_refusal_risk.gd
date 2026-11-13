extends SceneTree
## V5.3 audience reads (the parent's card of 2026-11-13, mockup C's Refuse card): what a
## refusal risks, and what a word of silence spares. Headless.
##
##   - A brief is not drawn: it fires when the person's grudge stands at the brief line and
##     they owe no silence (characters.gd). So the read is a projection on a copy of the
##     world as it stands -- the real Characters month, run twelve times on a copy -- and
##     the cases below pin it: over the line after the refusal, a brief in month one; no
##     grudge, none; a word of silence, none.
##   - The approval figure is the strip's: APPROVAL_SPAN times the brief's blocs' sizes
##     times the act's own magnitude (Characters.brief_magnitude), networked x1.5.
##   - The read writes nothing.
##   - THE SEEDED RUN: a real France run through WorldMonth.tick_month, every request
##     declined at the first month it can be; before each decline the read, after it the
##     briefs the person actually runs in the twelve months that follow. The realised
##     share in each bucket (the read said a brief, the read said none) is the band.
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudK = preload("res://src/sim/audience_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Deal = preload("res://src/sim/deal.gd")
const RefusalRisk = preload("res://src/sim/refusal_risk.gd")
const Staff = preload("res://src/sim/staff.gd")
const President = preload("res://src/sim/president.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

const PLAYER := "FRA"
## The seeded run's length, and the last month a decline is read in, so every window of
## twelve months after it is inside the run.
const RUN_MONTHS := 72
const READ_UNTIL := 60
## The band. Measured on this run at 114e1fba: 50 declines read; the read said a brief 7
## times and all 7 ran one; it said none 43 times and 1 ran one -- a second refusal of the
## same person inside the year, which the read cannot see. The margins allow one more of
## each: at least 85 % of "a brief" run one, at most 10 % of "none" do.
const BAND_YES_AT_LEAST := 0.85
const BAND_NO_AT_MOST := 0.10

var _failures: Array[String] = []
var _loader
var _base


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_base = GameState.new_game(_loader, PLAYER)
	_check_over_the_line_a_refusal_briefs_in_month_one()
	_check_no_grudge_no_brief()
	_check_the_read_runs_the_year()
	_check_a_word_of_silence_stops_the_brief()
	_check_refusal_and_silence_part_just_under_the_line()
	_check_silence_is_worth_what_they_would_do_left_alone()
	_check_the_approval_is_the_strips()
	_check_the_read_writes_nothing()
	_check_an_answered_request_has_no_refusal_to_price()
	_check_deal_reads_the_same()
	_check_the_read_against_a_seeded_run()
	_finish()


## A person of the nation who may brief: not the leader, a low standing (so no challenge
## comes first), no evidence held, picked once and by id.
func _person():
	var leader := President.leader_id(_base.player())
	var best = null
	for person in Staff.cast(_loader, PLAYER):
		if String(person.id) == leader or String(person.kind) == "chief_of_staff":
			continue
		if best == null or String(person.id) < String(best.id):
			best = person
	return best


func _fixture(grudge: float) -> Dictionary:
	var state = _base.duplicate_state()
	var ns = state.player()
	var person = _person()
	var pid := String(person.id)
	var now := int(state.year) * 12 + int(state.month)
	ns.person_grudges[pid] = grudge
	ns.person_standing[pid] = 0.0
	var row := {"id": "%s|%d" % [pid, now], "person_id": pid, "object": "x", "stance": "",
		"arrived_month": now, "deadline_month": now + 3, "status": AudK.STATUS_PENDING, "date": {}, "resolved_month": -1}
	ns.audience_requests.append(row)
	return {"state": state, "ns": ns, "pid": pid, "id": String(row["id"]), "person": person}


func _check_over_the_line_a_refusal_briefs_in_month_one() -> void:
	var f := _fixture(CK.GRUDGE_BRIEF_THRESHOLD - 0.05)
	var risk: Dictionary = RefusalRisk.of_refusal(f["state"], _loader, f["id"])
	_ok(int(risk.get("briefs", 0)) >= 1 and int(risk.get("first_month", -1)) == 1,
		"a refusal that lifts the grudge over the brief line did not brief in month one: %s" % [risk])


## No grudge, no brief -- while someone else in the cast is over the line and briefs: the
## read counts this person's briefs only.
func _check_no_grudge_no_brief() -> void:
	var f := _fixture(0.0)
	var other := ""
	for person in Staff.cast(_loader, PLAYER):
		if String(person.id) != String(f["pid"]) and String(person.kind) != "chief_of_staff" and String(person.id) != President.leader_id(f["ns"]):
			other = String(person.id)
			break
	f["ns"].person_grudges[other] = 1.0
	f["ns"].person_loyalty[other] = 1.0
	var risk: Dictionary = RefusalRisk.of_refusal(f["state"], _loader, f["id"])
	_ok(int(risk.get("briefs", -1)) == 0 and int(risk.get("first_month", 0)) == -1,
		"a refusal from no grudge read as a brief within the year: %s" % [risk])


## The horizon is the year: someone far over the line, loyal enough not to resign first,
## briefs month after month, so the read counts more than one.
func _check_the_read_runs_the_year() -> void:
	var f := _fixture(1.0)
	f["ns"].person_loyalty[f["pid"]] = 1.0
	var left_alone: Dictionary = RefusalRisk.of_silence(f["state"], _loader, f["id"])
	_ok(int(left_alone.get("briefs", 0)) > 1 and int(left_alone.get("briefs", 0)) <= RefusalRisk.HORIZON,
		"far over the line, the year read %s briefs" % [left_alone.get("briefs")])


func _check_a_word_of_silence_stops_the_brief() -> void:
	var f := _fixture(CK.GRUDGE_BRIEF_THRESHOLD - 0.05)
	var now := int(f["state"].year) * 12 + int(f["state"].month)
	President.commit(f["state"], f["ns"], _loader, "silence", f["pid"], "silence:fixture", now + 12)
	var risk: Dictionary = RefusalRisk.of_refusal(f["state"], _loader, f["id"])
	_ok(int(risk.get("briefs", -1)) == 0, "a person who owes silence read as briefing: %s" % [risk])


## The screen's main contrast (QA's TAKE on #322): just under the brief line, close enough
## that a refusal's pulse lifts the person over it, refusing reads a brief next month and
## leaving them alone (what silence spares) reads none.
func _check_refusal_and_silence_part_just_under_the_line() -> void:
	var f := _fixture(CK.GRUDGE_BRIEF_THRESHOLD - 0.05)
	var session := {"request_id": f["id"], "person_id": f["pid"]}
	var refused: Dictionary = Deal.refusal_risk(f["state"], f["ns"], _loader, session)
	var spared: Dictionary = Deal.silence_worth(f["state"], f["ns"], _loader, session)
	_ok(int(refused.get("first_month", -1)) == 1 and int(refused.get("briefs", 0)) >= 1,
		"just under the line, a refusal did not read a brief next month: %s" % [refused])
	_ok(int(spared.get("briefs", -1)) == 0 and int(spared.get("first_month", 0)) == -1,
		"just under the line, leaving them alone read a brief: %s" % [spared])


## From Grant's side: with no refusal, a person already over the line briefs in month one
## unless silenced -- what the word of silence spares. From no grudge, it spares nothing.
func _check_silence_is_worth_what_they_would_do_left_alone() -> void:
	var over := _fixture(CK.GRUDGE_BRIEF_THRESHOLD + 0.01)
	var spared: Dictionary = RefusalRisk.of_silence(over["state"], _loader, over["id"])
	_ok(int(spared.get("briefs", 0)) >= 1 and int(spared.get("first_month", -1)) == 1,
		"silence from someone over the line spares no brief: %s" % [spared])
	var calm := _fixture(0.0)
	var none: Dictionary = RefusalRisk.of_silence(calm["state"], _loader, calm["id"])
	_ok(int(none.get("briefs", -1)) == 0, "silence from someone with no grudge spares a brief: %s" % [none])
	# A refusal never risks less than the silence spares: it adds a grudge, never takes one.
	var below := _fixture(CK.GRUDGE_BRIEF_THRESHOLD - 0.05)
	_ok(int(RefusalRisk.of_refusal(below["state"], _loader, below["id"])["briefs"]) >= int(RefusalRisk.of_silence(below["state"], _loader, below["id"])["briefs"]),
		"a refusal read as fewer briefs than leaving the person alone")


func _check_the_approval_is_the_strips() -> void:
	for networked in [false, true]:
		var f := _fixture(0.0)
		var person = f["person"]
		var had: bool = person.traits.has("networked")
		if networked and not had:
			person.traits.append("networked")
		elif not networked and had:
			person.traits.erase("networked")
		var magnitude := CK.PRICE_BRIEF * (CK.STANDING_WEIGHT_BASE + 0.0) * (CK.NETWORKED_MAGNITUDE if networked else 1.0)
		var want := 0.0
		for bloc in CK.BRIEF_BLOCS:
			want += OpinionK.APPROVAL_SPAN * float(OpinionK.BLOC_SIZE[bloc]) * magnitude
		var risk: Dictionary = RefusalRisk.of_refusal(f["state"], _loader, f["id"])
		_ok(is_equal_approx(float(risk.get("approval_pt", 0.0)), want),
			"a brief's approval (networked %s) read %s, the strip's %s" % [networked, risk.get("approval_pt"), want])
		_ok(is_equal_approx(Characters.brief_magnitude(person, 0.0), magnitude), "brief_magnitude is not the act's price")
		if had and not person.traits.has("networked"):
			person.traits.append("networked")
		elif not had and person.traits.has("networked"):
			person.traits.erase("networked")


func _check_the_read_writes_nothing() -> void:
	var f := _fixture(CK.GRUDGE_BRIEF_THRESHOLD - 0.05)
	var before: String = JSON.stringify(f["state"].to_dict())
	RefusalRisk.of_refusal(f["state"], _loader, f["id"])
	RefusalRisk.of_silence(f["state"], _loader, f["id"])
	_ok(JSON.stringify(f["state"].to_dict()) == before, "the risk read wrote on the world")


## A request already answered (declined here) is past refusing: the read is {}, never the
## silence projection under a refusal's name.
func _check_an_answered_request_has_no_refusal_to_price() -> void:
	var f := _fixture(CK.GRUDGE_BRIEF_THRESHOLD + 0.01)
	Audiences.decline(f["state"], f["ns"], _loader, f["id"])
	_ok(RefusalRisk.of_refusal(f["state"], _loader, f["id"]).is_empty(), "an answered request read a refusal's risk")


func _check_deal_reads_the_same() -> void:
	var f := _fixture(CK.GRUDGE_BRIEF_THRESHOLD - 0.05)
	var session := {"request_id": f["id"], "person_id": f["pid"]}
	_ok(Deal.refusal_risk(f["state"], f["ns"], _loader, session) == RefusalRisk.of_refusal(f["state"], _loader, f["id"])
		and Deal.silence_worth(f["state"], f["ns"], _loader, session) == RefusalRisk.of_silence(f["state"], _loader, f["id"]),
		"Deal's door reads something else than the risk read")


func _check_the_read_against_a_seeded_run() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var reads: Array = []
	var briefs: Array = []
	var start := int(state.year) * 12 + int(state.month) - 1
	for i in RUN_MONTHS:
		# The month is set before its tick, as the game's clock does (audience_probe's loop).
		state.year = floori((start + i) / 12.0)
		state.month = (start + i) % 12 + 1
		state.day = 1
		var now := int(state.year) * 12 + int(state.month)
		if i < READ_UNTIL:
			for row in ns.audience_requests.duplicate():
				if String(row["status"]) != AudK.STATUS_PENDING or not _loader.person_by_id.has(String(row["person_id"])):
					continue
				var risk: Dictionary = RefusalRisk.of_refusal(state, _loader, String(row["id"]))
				if bool(Audiences.decline(state, ns, _loader, String(row["id"]))["ok"]):
					reads.append({"pid": String(row["person_id"]), "month": now, "briefs": int(risk["briefs"])})
		var report: Dictionary = WorldMonth.tick_month(state, _loader)
		for act in report.get("character_acts", []):
			if String(act["act"]) == "brief_against":
				briefs.append({"pid": String(act["person_id"]), "month": int(act["year"]) * 12 + int(act["month"])})
	# The decline comes before its month's tick, so the read's month 1 is the tick stamped
	# with the decline's own month: the window is that month and the HORIZON - 1 after it.
	var tally := {true: [0, 0], false: [0, 0]}
	for r in reads:
		var said: bool = int(r["briefs"]) > 0
		var ran := false
		for b in briefs:
			ran = ran or (String(b["pid"]) == String(r["pid"]) and int(b["month"]) >= int(r["month"]) and int(b["month"]) < int(r["month"]) + RefusalRisk.HORIZON)
		tally[said][0] += 1
		if ran:
			tally[said][1] += 1
	print("test_refusal_risk: seeded run, %d declines read; the read said a brief: %d, of which %d ran one; said none: %d, of which %d ran one" % [
		reads.size(), tally[true][0], tally[true][1], tally[false][0], tally[false][1]])
	_ok(reads.size() >= 20, "the seeded run declined %d requests: too few to measure" % reads.size())
	_ok(int(tally[true][0]) >= 3, "the read said a brief only %d times: the band on \"a brief\" cannot bite" % tally[true][0])
	if int(tally[true][0]) > 0:
		_ok(float(tally[true][1]) / float(tally[true][0]) >= BAND_YES_AT_LEAST,
			"the read said a brief and %d of %d ran one, under %s" % [tally[true][1], tally[true][0], BAND_YES_AT_LEAST])
	if int(tally[false][0]) > 0:
		_ok(float(tally[false][1]) / float(tally[false][0]) <= BAND_NO_AT_MOST,
			"the read said none and %d of %d ran one, over %s" % [tally[false][1], tally[false][0], BAND_NO_AT_MOST])


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_refusal_risk: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		print("test_refusal_risk: FAIL (%d)" % _failures.size())
		quit(1)
