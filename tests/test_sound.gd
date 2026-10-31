extends SceneTree

## V4.9c. The synthesized sound set (src/ui/sound_constants.gd, synth.gd,
## sound.gd, sound_bed.gd), measured on the RENDERED samples rather than on the
## recipes' own numbers: the election sting's bytes unchanged by its move (a
## SHA-256 pin), every sound deterministic and unclipped, click-free at both
## ends, the level ladder in its stated order, every bed seamless at its loop
## point. Then the wiring: the Sound setting gates every cue, a window gesture is
## one sound, the clock's pause by hand, the event sting at the month's worst
## severity behind the NOTIFY band, and a bed that swells in, answers Ambience
## off, and fades out.

const Sound = preload("res://src/ui/sound.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Synth = preload("res://src/ui/synth.gd")
const SoundBed = preload("res://src/ui/sound_bed.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const Events = preload("res://src/sim/events.gd")
const Elections = preload("res://src/sim/elections.gd")
const Motion = preload("res://src/ui/motion.gd")
const ElectionPanel = preload("res://src/ui/election_panel.gd")

## V3.6's sting as it was rendered by sting.gd before V4.9c moved its recipe:
## the hash of 123480 bytes, taken 2026-10-17 from the pre-move code.
const ELECTION_SHA256 := "f16b7676a1e1f67828fbc04f0467cca3a06b8758b7feae2acc966b089c9ac1e2"

## The last 5 ms of a one-shot must be this quiet (fraction of full scale) before
## the player's level: a sound that ends loud ends on a click. The election
## sting's own tail is ~0.011; nothing in the set may end louder than 0.02.
const TAIL_MAX := 0.02

## How long a frame-driven bed check waits on wall-clock time before failing:
## the bed renders on a worker (~400 ms measured) and fades over fade_s.
const BED_WAIT_MS := 8000

## suite-exclusive: backs up and restores user://settings.cfg -- the gate checks write the Sound and Ambience settings
var _had_settings := false
var _settings_backup := ""

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := 0
var _bed
var _leaving_bed
var _wait_started := 0
var _faded_player: AudioStreamPlayer
var _night
var _night_sounds := {}


func _init() -> void:
	_backup_settings()
	_set_audio(true, true)
	_check_election_unchanged()
	_check_renders()
	_check_ladder()
	_check_beds_seamless()
	_check_recipe_lookup()
	_check_warm()
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let main's _ready() run
	match _phase:
		0:
			_check_headless_bed_is_inert()
			_check_gate()
			_check_window_gestures()
			if _main._state == null:
				_fail("main.tscn did not produce a running game")
			else:
				_check_pause_cue()
				_check_event_sting()
			SoundBed.override = 1
			Synth.primed_thread = -1
			_bed = SoundBed.start(root, "menu")
			_wait_started = Time.get_ticks_msec()
			_phase = 1
		1:
			# Rendering on a worker, then swelling in.
			if _bed.playing() and _bed._player.volume_db > SoundK.SILENT_DB + 1.0:
				if Synth.primed_thread != OS.get_thread_caller_id():
					_fail("the bed rendered on a worker before Synth was primed on the calling thread")
				_set_audio(true, false)
				_phase = 2
			elif _waited_out("the menu bed never started playing"):
				return _finish()
		2:
			# Ambience off: the next frame the bed sees the save and fades its
			# player out -- the same player, kept for the way back.
			if _bed.playing():
				_fail("Ambience off: the bed still reports playing")
			_faded_player = _first_player(_bed)
			if _faded_player == null:
				_fail("Ambience off: the bed cut its player instead of fading it")
				return _finish()
			_wait_started = Time.get_ticks_msec()
			_phase = 6
		6:
			# The fade ends in silence and a stopped player, not a muted loop
			# still running.
			if not _faded_player.playing:
				if _faded_player.volume_db > SoundK.SILENT_DB + 0.5:
					_fail("Ambience off: the player stopped at %.1f dB, not after fading out" % _faded_player.volume_db)
				_set_audio(true, true)
				_wait_started = Time.get_ticks_msec()
				_phase = 3
			elif _waited_out("Ambience off: the bed never fell silent"):
				return _finish()
		3:
			# Back on: the same player fades back up -- never a second copy of
			# the loop overlapping the first's fade-out (review pass 1).
			if _bed.playing():
				var players := 0
				for c in _bed.get_children():
					if c is AudioStreamPlayer:
						players += 1
				if players != 1 or _first_player(_bed) != _faded_player:
					_fail("Ambience back on made a new player (%d now) instead of reviving the faded one" % players)
				_leaving_bed = _bed
				_leaving_bed.fade_out()
				_wait_started = Time.get_ticks_msec()
				_phase = 4
			elif _waited_out("Ambience on again: the bed did not come back"):
				return _finish()
		4:
			if not is_instance_valid(_leaving_bed):
				_start_night()
				_phase = 5
			elif _waited_out("fade_out() never freed the bed"):
				return _finish()
		5:
			# A second into the count: some regions have declared, not all.
			if Time.get_ticks_msec() - _wait_started >= 1000:
				_check_night_ticks_then_skip()
				return _finish()
	return false


# --- the rendered set ---------------------------------------------------------

func _all_one_shots() -> Dictionary:
	var out := {"election": SoundK.ELECTION}
	for id in SoundK.CUES:
		out[id] = SoundK.CUES[id]
	for id in SoundK.STINGS:
		out[id] = SoundK.STINGS[id]
	for i in SoundK.EVENTS.size():
		out["event_%d" % (i + 1)] = SoundK.EVENTS[i]
	return out


func _check_election_unchanged() -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(Synth.one_shot(SoundK.ELECTION))
	var got := ctx.finish().hex_encode()
	if got != ELECTION_SHA256:
		_fail("the election sting's bytes changed: sha256 %s" % got)


func _check_renders() -> void:
	var shots := _all_one_shots()
	for id in shots:
		var r: Dictionary = shots[id]
		var a := Synth.one_shot(r)
		if a != Synth.one_shot(r):
			_fail("%s: two renders differ -- the synth is not a pure function" % id)
		var n := roundi(float(r["rate"]) * float(r["duration_s"]))
		if a.size() != n * 2:
			_fail("%s: %d bytes, expected %d" % [id, a.size(), n * 2])
		if _peak(a) >= 32767:
			_fail("%s: clips -- a sample reached full scale" % id)
		if a.decode_s16(0) != 0:
			_fail("%s: the first sample is %d, not 0 -- it starts on a step" % [id, a.decode_s16(0)])
		var tail := _peak(a, n - roundi(float(r["rate"]) * 0.005)) / 32767.0
		if tail > TAIL_MAX:
			_fail("%s: ends at %.3f of full scale (> %.2f) -- it ends on a click" % [id, tail, TAIL_MAX])
	for id in SoundK.BEDS:
		var r: Dictionary = SoundK.BEDS[id]
		var b := Synth.bed(r)
		if b != Synth.bed(r):
			_fail("bed %s: two renders differ" % id)
		if _peak(b) >= 32767:
			_fail("bed %s: clips" % id)


## The ladder as heard: a sound's player level plus its own rendered peak.
func _check_ladder() -> void:
	var heard := {}
	var shots := _all_one_shots()
	for id in shots:
		heard[id] = float(shots[id]["level_db"]) + _db(_peak(Synth.one_shot(shots[id])))
	var beds_max := -INF
	for id in SoundK.BEDS:
		var r: Dictionary = SoundK.BEDS[id]
		beds_max = maxf(beds_max, float(r["level_db"]) + _db(_peak(Synth.bed(r))))
	var cues_min := INF
	var cues_max := -INF
	for id in SoundK.CUES:
		cues_min = minf(cues_min, heard[id])
		cues_max = maxf(cues_max, heard[id])
	if not beds_max < cues_min:
		_fail("ladder: a bed (%.1f dB) is as loud as a UI cue (%.1f dB)" % [beds_max, cues_min])
	if not cues_max < heard["event_1"]:
		_fail("ladder: a UI cue (%.1f dB) is as loud as a minor event (%.1f dB)" % [cues_max, heard["event_1"]])
	if not (heard["event_1"] < heard["event_2"] and heard["event_2"] < heard["event_3"]):
		_fail("ladder: the event stings are not minor < major < critical (%.1f, %.1f, %.1f)" % [
			heard["event_1"], heard["event_2"], heard["event_3"]])
	if not heard["event_3"] < heard["election"]:
		_fail("ladder: a critical event (%.1f dB) is as loud as the election sting (%.1f dB)" % [
			heard["event_3"], heard["election"]])
	# V5.3-0 (d): the losing stings sit above every UI cue, the lost election above
	# the failed vote, and both under the election toll, still the loudest sound.
	if not (cues_max < heard["vote_failed"] and heard["vote_failed"] < heard["election_lost"] 			and heard["election_lost"] < heard["election"]):
		_fail("ladder: cues %.1f < vote_failed %.1f < election_lost %.1f < election %.1f fails" % [
			cues_max, heard["vote_failed"], heard["election_lost"], heard["election"]])
	for id in shots:
		if float(shots[id]["level_db"]) > -8.0:
			_fail("%s: level %.1f dB is above the -8 dB ceiling" % [id, float(shots[id]["level_db"])])


## Whole cycles over the loop, then the seam itself: the jump from the last
## sample back to the first is no bigger than the bed's ordinary steps.
func _check_beds_seamless() -> void:
	for id in SoundK.BEDS:
		var r: Dictionary = SoundK.BEDS[id]
		var loop_s: float = r["loop_s"]
		for p in r["partials"]:
			for hz in [float(p[0]), float(p[2])]:
				var cycles: float = hz * loop_s
				if absf(cycles - roundf(cycles)) > 1e-6:
					_fail("bed %s: %.4f Hz is %.4f cycles over the loop -- it clicks at the seam" % [id, hz, cycles])
		var b := Synth.bed(r)
		var n := b.size() / 2
		var biggest := 0
		for i in range(1, n):
			biggest = maxi(biggest, absi(b.decode_s16(i * 2) - b.decode_s16((i - 1) * 2)))
		var seam := absi(b.decode_s16(0) - b.decode_s16((n - 1) * 2))
		if seam > biggest:
			_fail("bed %s: the seam jumps %d, the largest ordinary step is %d" % [id, seam, biggest])


func _check_recipe_lookup() -> void:
	if Sound.recipe("event_9") != SoundK.EVENTS[SoundK.EVENTS.size() - 1]:
		_fail("an out-of-range severity does not clamp to the worst sting")
	if not Sound.recipe("no_such_cue").is_empty():
		_fail("an unknown cue id has a recipe")
	var seen := {}
	for i in SoundK.EVENTS.size():
		seen[Synth.one_shot(SoundK.EVENTS[i]).hex_encode().sha256_text()] = true
	if seen.size() != SoundK.EVENTS.size():
		_fail("two severities share one sting")


# --- the wiring ---------------------------------------------------------------

## The worker path: warm() renders the set off the main thread, and what it
## renders is what the main thread would have.
func _check_warm() -> void:
	Sound._cache.clear()
	Synth.primed_thread = -1
	Sound.warm(true)
	if Sound._warm_task < 0:
		_fail("warm(true) started no worker")
		return
	# src/core/parallel.gd rule 5: Synth's lines run once on the calling thread before
	# any worker runs them (V5.1b3).
	if Synth.primed_thread != OS.get_thread_caller_id():
		_fail("warm() posted its worker before Synth was primed on the calling thread")
	Sound.settle()
	for id in Sound.ids():
		if not Sound._cache.has(id):
			_fail("warm() left %s unrendered" % id)
		elif Sound._cache[id].data != Synth.one_shot(Sound.recipe(id)):
			_fail("warm() rendered %s differently from the main thread" % id)

## Election night, counted by what enters the plate: players free themselves
## when they end, so a count of live children would undercount a 50 ms tick.
func _start_night() -> void:
	Motion.override = 1
	var ns = _main._state.player()
	var parties: Array = _main._loader.parties.get(ns.id, [])
	var result = Elections.resolve(ns, parties, ns.election_system, ns.election_threshold_pct, "national", 2029, 6)
	_night = ElectionPanel.new()
	root.add_child(_night)
	_night.setup(_main._state, _main._loader)
	_night.child_entered_tree.connect(func(c: Node):
		if c is AudioStreamPlayer:
			_night_sounds[c.stream] = int(_night_sounds.get(c.stream, 0)) + 1
	)
	_night.show_results([result])
	_wait_started = Time.get_ticks_msec()


## One tick per region declared, none for the regions a skip lands at once, and
## the verdict's sting once.
func _check_night_ticks_then_skip() -> void:
	var n: int = _night._night.size()
	var ticks := int(_night_sounds.get(Sound.stream("declare"), 0))
	if n < 3:
		_fail("the staged night has %d regions -- too few to test ticks against a skip" % n)
		return
	if ticks < 1 or ticks >= n:
		_fail("a second into a %d-region count, %d declare ticks played" % [n, ticks])
	if ticks != int(_night._ticked):
		_fail("%d ticks played for %d regions declared" % [ticks, int(_night._ticked)])
	_night.skip()
	if int(_night_sounds.get(Sound.stream("declare"), 0)) != ticks:
		_fail("skip() ticked the regions it declared at once -- the count's sound did not stop")
	if int(_night_sounds.get(Sound.stream("election"), 0)) != 1:
		_fail("the verdict after a skip played %d election stings, expected 1" % int(_night_sounds.get(Sound.stream("election"), 0)))
	Motion.override = -1

func _check_headless_bed_is_inert() -> void:
	SoundBed.override = -1
	var bed = SoundBed.start(root, "menu")
	if bed._task >= 0 or bed.is_processing():
		_fail("under --headless a bed rendered or processes -- it must stay inert")
	bed.queue_free()


func _check_gate() -> void:
	var host := Node.new()
	root.add_child(host)
	_set_audio(false, true)
	Sound.cue(host, "open")
	if _players(host, "open") != 0:
		_fail("Sound off: a cue placed a player anyway")
	_set_audio(true, true)
	Sound.cue(host, "open")
	if _players(host, "open") != 1:
		_fail("Sound on: a cue placed no player")
	var p := _first_player(host)
	if p != null and not is_equal_approx(p.volume_db, float(SoundK.CUES["open"]["level_db"])):
		_fail("a cue played at %.1f dB, its recipe says %.1f" % [p.volume_db, float(SoundK.CUES["open"]["level_db"])])
	Sound.cue(host, "no_such_cue")
	if host.get_child_count() != 1:
		_fail("an unknown cue id placed a player")
	host.queue_free()


## Opening a window is one sound even when it displaces another; closing the
## lot with close_all() is one sound.
func _check_window_gestures() -> void:
	var wm = WindowManager.new()
	root.add_child(wm)
	wm.size = Vector2(1920, 1080)
	for id in ["a", "b", "c"]:
		var content := Control.new()
		content.custom_minimum_size = Vector2(200, 100)
		wm.register(id, id, content)
	wm.open("a")
	if _players(wm, "open") != 1:
		_fail("opening a window played %d open cues, expected 1" % _players(wm, "open"))
	wm.open("a")
	if _players(wm, "open") != 1:
		_fail("raising a window already open played another open cue")
	wm.open("b")
	if _players(wm, "close") != 0:
		_fail("a window displaced by an open played a close cue -- one gesture, two sounds")
	wm.close("b")
	if _players(wm, "close") != 1:
		_fail("closing a window played %d close cues, expected 1" % _players(wm, "close"))
	# V5.1-c2.2: one tab is open at a time (the pin went with the floating
	# windows), so close_all() puts away one tab -- with one cue, not a cue and a
	# second for the way back to the map.
	wm.open("a")
	wm.open("c")
	var closes := _players(wm, "close")
	wm.close_all()
	if _players(wm, "close") != closes + 1:
		_fail("close_all() over an open tab played %d close cues, expected 1" % (_players(wm, "close") - closes))
	wm.queue_free()


func _check_pause_cue() -> void:
	_main._clock.paused = false
	_main._toggle_pause_by_hand()
	if _players(_main, "pause") != 1:
		_fail("pausing by hand played %d pause cues, expected 1" % _players(_main, "pause"))
	_main._toggle_pause_by_hand()
	if _players(_main, "resume") != 1:
		_fail("resuming by hand played %d resume cues, expected 1" % _players(_main, "resume"))


## One sting for a month's arrivals, at the worst severity among those NOTIFY
## lets through; a category set not to notify arrives silent.
func _check_event_sting() -> void:
	var ns = _main._state.player()
	var picks := _two_severities()
	if picks.is_empty():
		_fail("the book has no two non-interrupt events of different severities to stage")
		return
	var low = picks[0]
	var high = picks[1]
	_reset_desk()
	_main._messages = MessageSettings.defaults()
	var before := _sting_count()
	var month := Events._absolute_month(int(_main._state.year), int(_main._state.month))
	var names: Dictionary = Events.region_names(ns, _main._loader)
	Events.announce(ns, low, month, names)
	Events.announce(ns, high, month, names)
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if _sting_count() != before + 1:
		_fail("two arrivals in one month played %d stings, expected 1" % (_sting_count() - before))
	if _players(_main, "event_%d" % int(high.severity)) < 1:
		_fail("the month's sting is not the worst severity's (%d)" % int(high.severity))

	_reset_desk()
	var reg := MessageSettings.defaults()
	reg[low.category]["notify"] = MessageSettings.OFF
	_main._messages = reg
	before = _sting_count()
	Events.announce(ns, low, month, names)
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if _sting_count() != before:
		_fail("notify OFF: the arrival still played a sting")

	# An interrupt ignores the register: notify OFF still stings, and the
	# Dispatches window the interrupt opens adds no open tick on top.
	var urgent = _interrupt_event()
	if urgent == null:
		_fail("the book has no interrupt event to stage")
	else:
		_reset_desk()
		_main._windows.close_all()
		reg = MessageSettings.defaults()
		reg[urgent.category]["notify"] = MessageSettings.OFF
		_main._messages = reg
		before = _sting_count()
		var opens := _players(_main._windows, "open")
		Events.announce(ns, urgent, month, names)
		_main._card_events(_main._state.year, _main._state.month, {}, {})
		_main._enforce_interrupt()
		if _sting_count() != before + 1:
			_fail("notify OFF silenced an interrupt -- the register must not apply to it")
		# V5.1-c3.2: the inbox shows the decision, silently -- the sting is the sound.
		if not _main._hud.inbox.visible:
			_fail("the staged interrupt left the inbox away")
		elif _players(_main._windows, "open") != opens:
			_fail("the interrupt played an open tick over the sting")
	_reset_desk()
	_main._messages = MessageSettings.defaults()


func _interrupt_event():
	for ev in _main._loader.events:
		if bool(ev.interrupt):
			return ev
	return null


func _two_severities() -> Array:
	var by_severity := {}
	for ev in _main._loader.events:
		if bool(ev.interrupt) or int(ev.respond_months) < 2:
			continue
		if not by_severity.has(int(ev.severity)):
			by_severity[int(ev.severity)] = ev
	var keys := by_severity.keys()
	keys.sort()
	if keys.size() < 2:
		return []
	return [by_severity[keys[0]], by_severity[keys[keys.size() - 1]]]


func _reset_desk() -> void:
	var ns = _main._state.player()
	ns.event_queue.clear()
	_main._unseen_events.clear()
	for leftover in _main._event_cards.keys().duplicate():
		_main._hud.inbox.dismiss(leftover)
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._clock.paused = false


func _sting_count() -> int:
	var n := 0
	for i in SoundK.EVENTS.size():
		n += _players(_main, "event_%d" % (i + 1))
	return n


# --- helpers ------------------------------------------------------------------

func _players(host: Node, id: String) -> int:
	var want := Sound.stream(id)
	var n := 0
	for c in host.get_children():
		if c is AudioStreamPlayer and c.stream == want and not c.is_queued_for_deletion():
			n += 1
	return n


func _first_player(host: Node) -> AudioStreamPlayer:
	for c in host.get_children():
		if c is AudioStreamPlayer:
			return c
	return null


func _peak(pcm: PackedByteArray, from_sample: int = 0) -> int:
	var peak := 0
	for i in range(maxi(0, from_sample), pcm.size() / 2):
		peak = maxi(peak, absi(pcm.decode_s16(i * 2)))
	return peak


func _db(peak: int) -> float:
	return 20.0 * log(maxf(1.0, float(peak)) / 32767.0) / log(10.0)


func _waited_out(message: String) -> bool:
	if Time.get_ticks_msec() - _wait_started > BED_WAIT_MS:
		_fail(message)
		return true
	return false


## Writes the two audio keys and bumps the screen's save counter, which is what
## a save from the settings screen does and what a bed watches.
func _set_audio(sound: bool, ambient: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("audio", "enabled", sound)
	cfg.set_value("audio", "ambient", ambient)
	cfg.save(SettingsPanel.CONFIG_PATH)
	SettingsPanel.revision += 1


func _backup_settings() -> void:
	_had_settings = FileAccess.file_exists(SettingsPanel.CONFIG_PATH)
	if _had_settings:
		_settings_backup = FileAccess.get_file_as_string(SettingsPanel.CONFIG_PATH)


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SettingsPanel.CONFIG_PATH, FileAccess.WRITE)
		f.store_string(_settings_backup)
		f.close()
	elif FileAccess.file_exists(SettingsPanel.CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsPanel.CONFIG_PATH))


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	SoundBed.override = -1
	_restore_settings()
	if _failures.is_empty():
		print("test_sound: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
	return true
