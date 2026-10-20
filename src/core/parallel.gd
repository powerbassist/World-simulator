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
static func each(n: int, fn: Callable) -> void:
	if not enabled or active or n < 2:
		for i in n:
			fn.call(i)
		return
	active = true
	var task := WorkerThreadPool.add_group_task(fn, n, -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	active = false
