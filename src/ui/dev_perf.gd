extends RefCounted

## The perf overlay's numbers (V5.1-0b), kept apart from the Control that draws
## them so a test can feed frames and read them back.
##
## Frame time is the engine's own `delta`: the whole frame, UI and draw included,
## which is what a player feels. "Worst" is over the last WINDOW_SEC seconds, so a
## spike stays on screen long enough to be read and then lets go.
##
## The month's cost per system comes from src/ui/month_runner.gd, which times every
## UNIT of the month it runs (Economy and Diplomacy come in slices that can span
## frames, so the step hook's before/after would measure the frames between, not
## the work -- V5.1-0a's PR body). The hook is not used for this on purpose.
## The unit timing still includes whatever the step's own hooks do around it (main.gd's
## cards for a step's record), so a step reads as the system plus its UI work.

const WINDOW_SEC := 5.0
## Steps the month line names; the rest are in the total.
const TOP_STEPS := 5

var _frames: Array = []  # [time_sec, ms], oldest first


func record(frame_ms: float, now_sec: float) -> void:
	_frames.append([now_sec, frame_ms])
	while not _frames.is_empty() and now_sec - float(_frames[0][0]) > WINDOW_SEC:
		_frames.pop_front()


func current() -> float:
	return 0.0 if _frames.is_empty() else float(_frames[-1][1])


func worst() -> float:
	var out := 0.0
	for frame in _frames:
		out = maxf(out, float(frame[1]))
	return out


## `costs` is step name -> microseconds, one month's. "month 243 ms | Economy 90 ..."
## names the heaviest few; an empty table means no real-time month has closed yet.
func month_text(costs: Dictionary) -> String:
	if costs.is_empty():
		return "no real-time month since"
	var names: Array = costs.keys()
	names.sort_custom(func(a, b): return int(costs[a]) > int(costs[b]))
	var total := 0
	for name in names:
		total += int(costs[name])
	var parts: Array[String] = []
	for name in names.slice(0, TOP_STEPS):
		parts.append("%s %d" % [name, roundi(int(costs[name]) / 1000.0)])
	return "month %d ms | %s" % [roundi(total / 1000.0), " ".join(parts)]


func overlay_text(costs: Dictionary) -> String:
	return "frame %.1f ms  worst %.1f ms (%ds)\n%s" % [current(), worst(), int(WINDOW_SEC), month_text(costs)]
