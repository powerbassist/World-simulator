extends RefCounted

## V4.9c. Additive synthesis for the sound set: sine partials under exponential
## envelopes, rendered to 16-bit mono PCM. Pure functions of a recipe from
## sound_constants.gd -- the same recipe gives the same bytes on every build,
## which tests/test_sound.gd pins, so a sound cannot quietly become
## nondeterministic noise. Static and node-free, so sound_bed.gd can run a bed
## on a worker thread: nothing here touches the scene tree or a Resource.


## A one-shot: every partial summed, under one envelope and one attack ramp. The
## arithmetic is written in exactly V3.6's order (sum left to right, then
## sum x env x attack) because the election sting moved here from sting.gd and
## its bytes are pinned by hash -- a reordered product is a different float.
static func one_shot(recipe: Dictionary) -> PackedByteArray:
	var rate: int = int(recipe["rate"])
	# roundi, not int: 44100 x 1.4 is 61739.999... in floats, and a truncated
	# length came back one sample short of the duration (V3.6).
	var n := roundi(float(rate) * float(recipe["duration_s"]))
	var attack_s: float = float(recipe["attack_s"])
	var env_decay: float = float(recipe["env_decay"])
	# The partials unpacked once into typed arrays: indexing a Variant Array per
	# partial per sample was most of the cost. TAU x hz and -decay are the very
	# subexpressions the products evaluate first, so hoisting them changes no
	# float.
	var w := PackedFloat64Array()
	var amp := PackedFloat64Array()
	var neg_decay := PackedFloat64Array()
	var onset := PackedFloat64Array()
	for p in recipe["partials"]:
		w.append(TAU * float(p[0]))
		amp.append(float(p[1]))
		neg_decay.append(-float(p[2]))
		onset.append(float(p[3]))
	var count := w.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-env_decay * t)
		var s := 0.0
		for k in count:
			if onset[k] > 0.0:
				# A late partial carries its own attack: the global one is long
				# over by its onset, and starting a sine at full amplitude
				# mid-buffer is the click the attack exists to prevent.
				var tt := t - onset[k]
				if tt < 0.0:
					continue
				s += amp[k] * sin(w[k] * tt) * exp(neg_decay[k] * tt) * minf(1.0, tt / attack_s)
			else:
				s += amp[k] * sin(w[k] * t) * exp(neg_decay[k] * t)
		var attack: float = minf(1.0, t / attack_s)
		var v := int(clampf(s * env * attack, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	return bytes


## A bed: one loop of partials that each swell between silence and full at their
## own rate. No envelope -- the player fades a bed in and out -- and no attack,
## because the loop has no first sample: sample n would be sample 0 again, which
## is what the whole-cycle rule in sound_constants.gd buys.
static func bed(recipe: Dictionary) -> PackedByteArray:
	var rate: int = int(recipe["rate"])
	var n := roundi(float(rate) * float(recipe["loop_s"]))
	var w := PackedFloat64Array()
	var amp := PackedFloat64Array()
	var swell_w := PackedFloat64Array()
	var phase := PackedFloat64Array()
	for p in recipe["partials"]:
		w.append(TAU * float(p[0]))
		amp.append(float(p[1]))
		swell_w.append(TAU * float(p[2]))
		phase.append(float(p[3]))
	var count := w.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var s := 0.0
		for k in count:
			s += amp[k] * sin(w[k] * t) * (0.5 + 0.5 * sin(swell_w[k] * t + phase[k]))
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return bytes


## The PCM wrapped for a player. `looped` sets the loop over the whole buffer --
## a bed's seam is sample n-1 to sample 0.
static func wav(bytes: PackedByteArray, rate: int, looped: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = bytes.size() / 2
	return stream
