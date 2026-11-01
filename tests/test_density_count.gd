extends SceneTree

## V5.3 a + b, band B7 (docs/design/v5.3-ab.md section 7): the counting rule of
## `decision_surfaces_probe.gd --density`. The rule lives in tools/density_count.gd
## so it is pinned here on fixtures, without running a world:
##   - a decision counts when it has two answers whose effects strips differ on one
##     of the spec's axes (0.5 bn a year, 0.5 point of approval, a bloc arrow, a
##     person's feeling word, a division's outcome, a process stage);
##   - a society or company channel is not on that list, so a decision that differs
##     only there is dull, and the probe reports which axis would have saved it;
##   - the 3-month repeat rule: a subject counted in the last 3 months is not counted
##     again unless its state changed; an arrival and its deadline in the same month
##     count once;
##   - the band: every month at least one, a mean of at least 2, never more than 6,
##     at least 3 domains a quarter.

const DensityCount = preload("res://tools/density_count.gd")
const BriefingEffects = preload("res://src/ui/briefing_effects.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_arrow_reads_the_briefing_word_bands()
	_check_strips_differ_only_on_the_spec_axes()
	_check_meaningful_needs_two_answers_that_differ()
	_check_repeat_rule_and_state_change()
	_check_arrival_and_deadline_count_once()
	_check_summary_and_band()
	_check_the_probe_counts_through_the_rule()
	_finish()


func _check_arrow_reads_the_briefing_word_bands() -> void:
	var slight := float(BriefingEffects.OFFSET_SLIGHT)
	var clear := float(BriefingEffects.OFFSET_CLEAR)
	var cases := [
		[0.0, 0], [slight * 0.99, 0], [-slight * 0.99, 0], [slight, 1], [-slight, -1],
		[clear * 0.99, 1], [clear, 2], [-clear * 1.5, -2],
	]
	for c in cases:
		var got := DensityCount.arrow(float(c[0]))
		if got != int(c[1]):
			_failures.append("arrow(%s) is %d, want %d" % [c[0], got, c[1]])


func _check_strips_differ_only_on_the_spec_axes() -> void:
	var empty := {}
	var cases := [
		[{"money_bn": DensityCount.MONEY_BN * 0.99}, []],
		[{"money_bn": -DensityCount.MONEY_BN}, ["money"]],
		[{"debt_bn": DensityCount.MONEY_BN}, ["money"]],
		[{"approval": DensityCount.APPROVAL_PT * 0.99}, []],
		[{"approval": DensityCount.APPROVAL_PT}, ["approval"]],
		[{"arrows": {"workers": 1}}, ["arrow"]],
		[{"arrows": {"workers": 0}}, []],
		[{"division": "passes"}, ["division"]],
		[{"stage": "offer"}, ["stage"]],
		[{"other": {"society|corruption": -0.02}}, []],
	]
	for c in cases:
		var got: Array = DensityCount.differs(c[0], empty)
		if got != c[1]:
			_failures.append("differs(%s, {}) is %s, want %s" % [c[0], got, c[1]])
	# A feeling present on one side only reads that register's band against the
	# other side's: an absent band is "not moved", not a band of its own.
	var a := {"feel": {"p1|rapport": 2, "p1|grudge": 0}}
	var b := {"feel": {"p1|rapport": 2}}
	if not DensityCount.differs(a, b).is_empty():
		_failures.append("an unmoved register on one side only read as a difference")
	var colder := {"feel": {"p1|rapport": 1, "p1|grudge": 0}}
	if DensityCount.differs(a, colder) != ["feeling"]:
		_failures.append("a register landing in another band did not read as a feeling: %s" % [DensityCount.differs(a, colder)])
	var society := DensityCount.other_differs({"other": {"society|corruption": -0.02}}, empty)
	if society != ["society|corruption"]:
		_failures.append("other_differs did not name the society channel: %s" % [society])


func _check_meaningful_needs_two_answers_that_differ() -> void:
	var arrow := {"arrows": {"workers": 1}}
	if DensityCount.meaningful([arrow]):
		_failures.append("one answer counted as a decision")
	if DensityCount.meaningful([arrow, arrow.duplicate(true)]):
		_failures.append("two identical answers counted as a decision")
	if not DensityCount.meaningful([{}, {}, arrow]):
		_failures.append("three answers, one with an arrow, did not count")
	var society := {"other": {"society|press_freedom": 0.05}}
	if DensityCount.meaningful([{}, society]):
		_failures.append("a society-only difference counted (it is not a spec axis)")
	if DensityCount.saved_by([{}, society]) != ["society|press_freedom"]:
		_failures.append("saved_by did not name the axis: %s" % [DensityCount.saved_by([{}, society])])
	if not DensityCount.saved_by([{}, arrow]).is_empty():
		_failures.append("saved_by named an axis for a decision that already counts")


func _candidate(subject: String, state: String, domain := "fiscal") -> Dictionary:
	return {"source": "event", "subject": subject, "state": state, "domain": domain,
		"due": "arrival", "answers": [{}, {"arrows": {"workers": 1}}]}


func _check_repeat_rule_and_state_change() -> void:
	var memory := {}
	var first := DensityCount.month([_candidate("event|x", "")], memory, 10)
	if (first["counted"] as Array).size() != 1:
		_failures.append("a first offer did not count")
	for now in range(11, 11 + DensityCount.REPEAT_MONTHS):
		var again := DensityCount.month([_candidate("event|x", "")], memory, now)
		if not (again["counted"] as Array).is_empty() or (again["repeat"] as Array).size() != 1:
			_failures.append("the same subject counted again %d months later" % [now - 10])
	var later := DensityCount.month([_candidate("event|x", "")], memory, 11 + DensityCount.REPEAT_MONTHS)
	if (later["counted"] as Array).size() != 1:
		_failures.append("the same subject did not count again after %d months" % (DensityCount.REPEAT_MONTHS + 1))
	# A changed state is a new decision inside the window.
	var memory2 := {}
	DensityCount.month([_candidate("request|p1", "budget|support")], memory2, 20)
	var changed := DensityCount.month([_candidate("request|p1", "law:x|oppose")], memory2, 21)
	if (changed["counted"] as Array).size() != 1:
		_failures.append("a changed state did not count inside the window")
	# A dull offer is reported, never remembered: it does not block a later one.
	var memory3 := {}
	var dull := _candidate("event|y", "")
	dull["answers"] = [{}, {}]
	var d := DensityCount.month([dull], memory3, 30)
	if (d["dull"] as Array).size() != 1 or not (d["counted"] as Array).is_empty():
		_failures.append("a dull offer was not reported as dull")
	var after := DensityCount.month([_candidate("event|y", "")], memory3, 31)
	if (after["counted"] as Array).size() != 1:
		_failures.append("a dull offer blocked the next one")


func _check_arrival_and_deadline_count_once() -> void:
	var arrival := _candidate("event|z", "")
	var deadline := _candidate("event|z", "")
	deadline["due"] = "deadline"
	var out := DensityCount.month([arrival, deadline], {}, 40)
	if (out["counted"] as Array).size() != 1:
		_failures.append("an arrival and its deadline in one month counted %d times" % (out["counted"] as Array).size())


func _check_summary_and_band() -> void:
	# Six months, two quarters: counts 1 0 0 | 2 3 7.
	var months := [
		{"now": 1, "count": 1, "domains": ["fiscal"]},
		{"now": 2, "count": 0, "domains": []},
		{"now": 3, "count": 0, "domains": []},
		{"now": 4, "count": 2, "domains": ["fiscal", "audience"]},
		{"now": 5, "count": 3, "domains": ["industrial"]},
		{"now": 6, "count": 7, "domains": ["fiscal"]},
	]
	var s := DensityCount.summary(months)
	var want := {"months": 6, "with_one": 4, "max": 7, "longest_none": 2, "over_max": 1,
		"quarters": 2, "quarters_ok": 1}
	for k in want:
		if int(s[k]) != int(want[k]):
			_failures.append("summary %s is %s, want %s" % [k, s[k], want[k]])
	if absf(float(s["mean"]) - 13.0 / 6.0) > 1e-9 or absf(float(s["share"]) - 4.0 / 6.0) > 1e-9:
		_failures.append("summary mean/share wrong: %s / %s" % [s["mean"], s["share"]])
	if bool(s["pass"]):
		_failures.append("a run with empty months passed the band")
	var full := []
	for i in range(6):
		full.append({"now": i, "count": 2, "domains": ["fiscal", "audience", "industrial"]})
	if not bool(DensityCount.summary(full)["pass"]):
		_failures.append("a run meeting every bar failed the band: %s" % [DensityCount.summary(full)])
	# A partial last quarter (a defeat ends a run) is judged on what it has.
	full.append({"now": 6, "count": 2, "domains": ["fiscal"]})
	if bool(DensityCount.summary(full)["pass"]):
		_failures.append("a last quarter with one domain passed")


func _check_the_probe_counts_through_the_rule() -> void:
	var text := FileAccess.get_file_as_string("res://tools/decision_surfaces_probe.gd")
	for needle in ["--density", "DensityCount.month(", "DensityCount.summary(", "WorldMonth.tick_month("]:
		if not text.contains(needle):
			_failures.append("decision_surfaces_probe.gd does not contain %s" % needle)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_density_count")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
