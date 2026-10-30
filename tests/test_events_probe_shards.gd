extends SceneTree

## V5.2d. events_probe runs in CI as CI_SHARDS, one matrix job each (it took ~30
## minutes in one job, at its timeout). Sharding must not drop a gate: together the
## shards name every table the probe dispatches, E1b's regime parts cover every
## residue, and the workflow's matrix lists one job per shard.

const Probe = preload("res://tools/events_probe.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_shards_cover_every_table()
	_check_e1b_parts_cover_every_regime()
	_check_the_dispatch_names_every_table()
	_check_the_workflow_runs_every_shard()
	_finish()


func _check_shards_cover_every_table() -> void:
	var named := {}
	for shard in Probe.CI_SHARDS:
		for t in shard["only"]:
			named[String(t)] = true
	for t in Probe.TABLES:
		if not named.has(String(t)):
			_failures.append("table %s is in no CI shard -- CI would never gate it" % t)
	for t in named:
		if not Probe.TABLES.has(t):
			_failures.append("a CI shard names %s, which is not a table" % t)


## Every shard that runs E1b names a part [i, n]; together the parts of each n are
## 1..n, so every regime index lands in exactly one shard.
func _check_e1b_parts_cover_every_regime() -> void:
	var parts := {}
	for shard in Probe.CI_SHARDS:
		if not (shard["only"] as Array).has("E1B"):
			continue
		var part: Array = shard.get("e1b", [1, 1])
		var n := int(part[1])
		if not parts.has(n):
			parts[n] = []
		parts[n].append(int(part[0]))
	if parts.size() != 1:
		_failures.append("E1b's CI parts mix denominators: %s" % [parts])
		return
	for n in parts:
		var got: Array = parts[n]
		got.sort()
		var want: Array = range(1, n + 1)
		if got != want:
			_failures.append("E1b's CI parts of %d are %s, not 1..%d once each" % [n, got, n])


## The probe's own dispatch names exactly TABLES (a table added to _init() and not to
## TABLES would escape the coverage check above).
func _check_the_dispatch_names_every_table() -> void:
	var src := FileAccess.get_file_as_string("res://tools/events_probe.gd")
	var rx := RegEx.create_from_string("if _runs\\(\"([A-Z0-9]+)\"\\)")
	var dispatched: Array[String] = []
	for m in rx.search_all(src):
		dispatched.append(m.get_string(1))
	var want: Array[String] = []
	for t in Probe.TABLES:
		want.append(String(t))
	dispatched.sort()
	want.sort()
	if dispatched != want:
		_failures.append("_init() dispatches %s but TABLES is %s" % [dispatched, want])


func _check_the_workflow_runs_every_shard() -> void:
	var yml := FileAccess.get_file_as_string("res://.github/workflows/tests.yml")
	if yml.is_empty():
		_failures.append("could not read .github/workflows/tests.yml")
		return
	var list: Array[String] = []
	for k in range(1, Probe.CI_SHARDS.size() + 1):
		list.append(str(k))
	var want := "events_shard: [%s]" % ", ".join(list)
	if not yml.contains(want):
		_failures.append("the workflow's events matrix is not '%s' -- one job per CI_SHARDS entry" % want)
	if not yml.contains("--ci-shard=${{ matrix.events_shard }}"):
		_failures.append("the workflow's events job does not pass --ci-shard")


func _finish() -> void:
	if _failures.is_empty():
		print("test_events_probe_shards: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
