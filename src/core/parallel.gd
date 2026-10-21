extends RefCounted

## The month's one fan-out primitive -- V5.0c2. Diplomacy scores an acting
## nation's targets, and judges an act's observers, on WorkerThreadPool; this
## file is how, and the rules it holds are the reason the threaded month is the
## serial month bit for bit (the 51-regime table is cmp-identical, three runs):
##
##   1. WORKERS ONLY READ SHARED STATE. Element i writes only into slots[i], a
##      Dictionary nothing else touches; GameState is read, never written.
##   2. EVERY COMBINE IS SERIAL, on the calling thread after the join, in index
##      order -- the order the serial loop visited -- so every comparison and
##      every float sum happens in the order it always did.
##   3. THE STATIC MEMOS ARE READ-ONLY WHILE `active`. Org.shared_bonus(), the
##      trade turn memo and Cycle's seed memos serve their hits and, on a miss,
##      compute without storing: a worker never writes a shared Dictionary, and
##      a value it computes is the value the memo would have held (each memo's
##      hit is already proven equal to its miss).
##   4. NO pow(), exp() OR OTHER LIBM CALL ON A WORKER. Measured on this build:
##      pow() and exp() on a pool thread return a different last bit from the
##      main thread's for the same input (sqrt(), +, -, *, / are correctly
##      rounded and never differ). A fan-out takes its pow()s on the calling
##      thread first -- Trade.masses_open(), ForeignPolicy.stake_factor() -- and
##      the workers read them.
##   5. ELEMENT 0 RUNS FIRST, ALONE, ON THE CALLING THREAD -- G2. GDScript caches
##      an untyped operator's evaluator in the bytecode the first time it runs
##      (gdscript_vm.cpp:806-809, 4.7.2 and master): the signature is stored
##      before the function pointer, unordered, and a thread that reads the
##      signature in between takes the unlocked fast path (:813-820) and calls
##      address 0. Trade._raw()'s `state == _mass_state` is reached only while
##      the masses table is open, so its first run was always on every worker
##      at once: a SIGSEGV in CI, and in a fresh-bytecode stress on the Linux
##      build 6 processes in 12 (0 in 6 with one run on the caller first;
##      tools/opcache_race_probe.gd). Element
##      0 primes every operator on its own path before the pool starts, for one
##      element's time per fan-out. A branch element 0 skips -- score_targets()
##      element 0 with no offer returns before target_terms() -- is primed by
##      nothing, so a worker-only branch should compare TYPED values, which
##      compile to the validated opcode and carry no cache.
##
## `enabled` false runs every fan-out as the plain serial loop with the memos
## writable -- the reference tests/test_diplomacy_parallel.gd compares the
## threaded month against. A fan-out asked for while one is running (nothing
## does today) runs serially rather than nest pools.

static var enabled := true
static var active := false


## One empty Dictionary per element, for the elements to fill.
static func slots(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({})
	return out


## fn.call(i) for every i in [0, n): on the pool when enabled, else in order.
## Element 0 runs on the calling thread before the rest are posted (rule 5).
static func each(n: int, fn: Callable) -> void:
	if not enabled or active or n < 2:
		for i in n:
			fn.call(i)
		return
	active = true
	fn.call(0)
	var rest := func(i: int) -> void: fn.call(i + 1)
	var task := WorkerThreadPool.add_group_task(rest, n - 1, -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	active = false
