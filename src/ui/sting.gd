extends Node

## The election sting -- this project's first and only sound (V3.6). Synthesized
## in code rather than shipped as a binary ON PURPOSE: there is no licence to
## read, no attribution file to keep true, no .import to commit and no
## fresh-clone loading question. The assets/fonts bytes-not-load() discipline
## exists because a font cannot be generated; a two-second chord can. If a
## later session swaps in a recorded sting, the obligations it takes on are
## listed in the V3.6 plan's audit section: licence text committed beside the
## file, load via AudioStreamOggVorbis.load_from_buffer(), never load().

const SettingsPanel = preload("res://src/ui/settings_panel.gd")

const SAMPLE_RATE := 44100
const DURATION_S := 1.4

## Quiet by design: a ceremony accent, not an alarm. -8 dB is roughly half
## amplitude -- anything louder than the game's own brass would be a second
## aesthetic, and U5a settled that there is one.
const VOLUME_DB := -8.0

## Three partials of a D chord (D3-A3-D4), each with its own decay, under one
## overall envelope and a 12 ms attack so the first sample is not a step: a low
## toll that fits a result plate. A pure function of the sample index -- two
## builds are byte-identical, which the test pins so this cannot quietly become
## nondeterministic noise.
static func _synth() -> PackedByteArray:
	# roundi, not int: 44100 x 1.4 is 61739.999... in floats, and a truncated
	# length came back one sample short of the duration the test pins.
	var n := roundi(SAMPLE_RATE * DURATION_S)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-2.6 * t)
		var s := 0.44 * sin(TAU * 146.83 * t) \
			+ 0.27 * sin(TAU * 220.0 * t) * exp(-3.4 * t) \
			+ 0.18 * sin(TAU * 293.66 * t) * exp(-4.2 * t)
		var attack: float = minf(1.0, t / 0.012)
		var v := int(clampf(s * env * attack, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes

static var _stream_cache: AudioStreamWAV


static func _stream() -> AudioStreamWAV:
	if _stream_cache == null:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = SAMPLE_RATE
		wav.stereo = false
		wav.data = _synth()
		_stream_cache = wav
	return _stream_cache


## One-shot: the player frees itself when the stream ends, so there is no pool
## and no state to keep -- the whole audio side of V3.6 is this one call. Safe
## under --headless (the Dummy driver plays nothing and opens no device), which
## is what the whole test suite runs on.
static func play(parent: Node) -> void:
	if not SettingsPanel.sound_enabled():
		return
	var player := AudioStreamPlayer.new()
	player.stream = _stream()
	player.volume_db = VOLUME_DB
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
