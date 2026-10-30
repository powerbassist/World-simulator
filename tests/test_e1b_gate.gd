extends SceneTree

## V5.2d. The E1b gate (D4) after the author's call of 2026-10-30 ("Mesurer les
## événements seuls, le reste en V5.3"): events_probe judges the EVENT BOOK'S OWN
## share of each bloc's offset -- every applied choice's authored bloc_offset,
## counted from the run's fires -- against the clamp, and only REPORTS the live
## offset, which other writers (V5.3's carry) also move. The rule lives in
## tools/e1b_gate.gd; this pins it and that the probe gates through it.

const DataLoader = preload("res://src/core/data_loader.gd")
const E1bGate = preload("res://tools/e1b_gate.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_share_sums_the_applied_choices()
	_check_saturation_is_the_clamp_on_the_share()
	_check_the_probe_gates_through_it()
	_finish()


## Two fires of one choice and one of another: the share is their authored offsets
## times the counts, bloc by bloc, every bloc present; an unknown event counts nothing.
func _check_share_sums_the_applied_choices() -> void:
	var ev = null
	for candidate in _loader.events:
		var offsets: Dictionary = (candidate.choices[0].get("effects", {}) as Dictionary).get("bloc_offset", {})
		var other: Dictionary = (candidate.choices[1].get("effects", {}) as Dictionary).get("bloc_offset", {})
		if not offsets.is_empty() and not other.is_empty():
			ev = candidate
			break
	var a: Dictionary = ev.choices[0]
	var b: Dictionary = ev.choices[1]
	var fires := {ev.id: {String(a["id"]): 2, String(b["id"]): 1}, "no_such_event": {"x": 5}}
	var share := E1bGate.event_share(_loader, fires)
	for bloc in OpinionK.BLOC_KEYS:
		var want := 2.0 * float((a["effects"] as Dictionary).get("bloc_offset", {}).get(bloc, 0.0)) \
				+ float((b["effects"] as Dictionary).get("bloc_offset", {}).get(bloc, 0.0))
		if not share.has(bloc) or absf(float(share[bloc]) - want) > 1e-9:
			_failures.append("%s share on %s is %s, want %.6f" % [ev.id, bloc, share.get(bloc), want])


func _check_saturation_is_the_clamp_on_the_share() -> void:
	var clamp_max := float(LegislatureK.BLOC_OFFSET_MAX)
	var slack := {"workers": -0.98, "students": 0.5}
	if not E1bGate.saturated(slack, clamp_max).is_empty():
		_failures.append("a share strictly inside the clamp was flagged: %s" % [E1bGate.saturated(slack, clamp_max)])
	var at := {"workers": -clamp_max, "students": 0.2, "rural": clamp_max + 0.4}
	var hit := E1bGate.saturated(at, clamp_max)
	if not (hit.has("workers") and hit.has("rural") and not hit.has("students")):
		_failures.append("a share at or past the clamp, either sign, was not flagged: %s" % [hit])


## Structural: the probe's E1b band reads E1bGate over the share, never the live
## offset (a reverted gate would fail on clamps the event book does not cause).
func _check_the_probe_gates_through_it() -> void:
	var src := FileAccess.get_file_as_string("res://tools/events_probe.gd")
	if not src.contains("E1bGate.event_share(") or not src.contains("E1bGate.saturated("):
		_failures.append("tools/events_probe.gd's E1b band does not gate through tools/e1b_gate.gd")


func _finish() -> void:
	if _failures.is_empty():
		print("test_e1b_gate: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
