extends SceneTree

## Operator-cache race probe -- G2: godot --headless --script
## res://tools/opcache_race_probe.gd -- --kind=parallel --rounds=20000
##
## GDScript caches an untyped operator's evaluator in the bytecode the first
## time it runs, and on 4.7.2 publishes the signature before the function
## pointer with no ordering (src/core/parallel.gd rule 5 has the lines). This
## probe makes that first run happen over and over: each round compiles a FRESH
## script, so the cache slots are zero again, and fans its first call out over
## the pool. A crash is `handle_crash: ... signal 11` with the GDScript frame on
## the probe script's `a == b`, and the process dies -- so the verdict is the
## exit code over many processes, not one line of output.
##
## Kinds, each 64 elements a round:
##   raw      -- untyped `a == b` on the bare pool: the race, unmitigated
##   parallel -- the same through Parallel.each(), the mitigation under test
##   typed    -- `int == int` on the bare pool: the validated opcode, no cache
##
## Measured 2026-10-21 on the official Linux 4.7.2 binary, two cores, 20 000
## rounds a process: raw 6 of 12 processes crashed, parallel on the pre-G2
## Parallel 2 of 6, parallel after G2 0 of 42, typed 0 of 6. The Windows (MSVC)
## build did not crash raw in 3 processes, which is not a verdict that it is
## safe. Re-run it on an engine bump: rule 5 can go when `raw` stops crashing.
##
## Not a test, excluded from run_tests.sh: an instrument whose failure is a
## crash, and whose rate wants hundreds of thousands of first runs on a pinned,
## oversubscribed Linux core set (taskset -c 0-1).

const Parallel = preload("res://src/core/parallel.gd")

const SRC_UNTYPED := "static func f(a, b) -> bool:\n\treturn a == b\n"
const SRC_TYPED := "static func f(a: int, b: int) -> bool:\n\treturn a == b\n"
const ELEMENTS := 64


func _init() -> void:
	var kind := "parallel"
	var rounds := 20000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kind="):
			kind = arg.trim_prefix("--kind=")
		elif arg.begins_with("--rounds="):
			rounds = int(arg.trim_prefix("--rounds="))
	if kind not in ["raw", "parallel", "typed"]:
		push_error("opcache_race_probe: unknown --kind=%s (raw, parallel, typed)" % kind)
		quit(1)
		return
	var o := RefCounted.new()
	var t0 := Time.get_ticks_msec()
	for r in rounds:
		var s := GDScript.new()
		s.source_code = SRC_TYPED if kind == "typed" else SRC_UNTYPED
		s.reload()
		match kind:
			"parallel":
				Parallel.each(ELEMENTS, func(_i: int) -> void: s.f(o, o))
			"raw":
				var task := WorkerThreadPool.add_group_task(func(_i: int) -> void: s.f(o, o), ELEMENTS, -1, true)
				WorkerThreadPool.wait_for_group_task_completion(task)
			"typed":
				var task := WorkerThreadPool.add_group_task(func(_i: int) -> void: s.f(r, r), ELEMENTS, -1, true)
				WorkerThreadPool.wait_for_group_task_completion(task)
	print("opcache_race_probe: kind=%s rounds=%d survived in %d ms" % [kind, rounds, Time.get_ticks_msec() - t0])
	quit(0)
