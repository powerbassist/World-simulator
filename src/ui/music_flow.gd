extends RefCounted

## The bed's gains through a crossfade and a rest -- V5.3-0, docs/design/
## v5.3-0-readability.md 4.3, band RF9 (#223's RECORD). Pure, as MusicBand is, so
## the suite pins what the player hears: Music places no player under --headless.
##
## A bed change crossfades over MUSIC_CROSSFADE_S: the old bed's gain falls as the
## new one's rises. After MUSIC_PLAYS_BEFORE_REST plays through, the bed fades out
## and rests MUSIC_REST_S (the fade inside the rest) under the ambient desk bed
## alone, then starts again from its top: a two-minute loop heard for an hour is
## the fatigue the rest exists for (spec 4.3, "against fatigue").
##
## The state is a Dictionary, {} before the first bed:
##   gain     the playing bed's gain, 0..1
##   out      the bed fading out after a change, 0..1 (0: none)
##   played   seconds of the bed heard since its top
##   rest     seconds of rest left (0: not resting)
##   restart  true on the one step a rest ends: the player starts from the top

const SoundK = preload("res://src/ui/sound_constants.gd")


## A new bed: the playing one becomes the one fading out, the new one rises from 0.
static func change(prev: Dictionary) -> Dictionary:
	return {"gain": 0.0, "out": maxf(float(prev.get("gain", 0.0)), float(prev.get("out", 0.0))),
		"played": 0.0, "rest": 0.0, "restart": false}


## `delta` seconds on. `length` is the bed's own length in seconds, 0 when unknown
## (no stream): a bed of no known length never rests.
static func step(prev: Dictionary, delta: float, length: float) -> Dictionary:
	var s := prev.duplicate() if not prev.is_empty() else change({})
	var rate := delta / SoundK.MUSIC_CROSSFADE_S
	s["restart"] = false
	s["out"] = maxf(float(s["out"]) - rate, 0.0)
	if float(s["rest"]) > 0.0:
		s["rest"] = maxf(float(s["rest"]) - delta, 0.0)
		s["gain"] = maxf(float(s["gain"]) - rate, 0.0)
		if float(s["rest"]) <= 0.0:
			s["played"] = 0.0
			s["restart"] = true
		return s
	s["played"] = float(s["played"]) + delta
	s["gain"] = minf(float(s["gain"]) + rate, 1.0)
	if length > 0.0 and float(s["played"]) >= length * SoundK.MUSIC_PLAYS_BEFORE_REST:
		s["rest"] = SoundK.MUSIC_REST_S
	return s


## A gain as the dB to add to the bed's target (0 at full, SILENT_DB at none).
static func db(gain: float) -> float:
	return maxf(linear_to_db(gain), SoundK.SILENT_DB) if gain > 0.0 else SoundK.SILENT_DB
