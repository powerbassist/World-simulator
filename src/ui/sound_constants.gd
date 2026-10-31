extends RefCounted

## V4.9c. The sound set's authored constants, in one place with their reasons --
## the *_constants.gd rule, audio edition. Every sound in the game is generated
## from a recipe below by synth.gd: no recording, no binary, no licence surface
## (the author's call at the tier signing, 2026-09-13; V3.6's sting.gd is the
## precedent). A later session wanting a recorded sound re-opens every obligation
## sting.gd's header lists and writes them down before downloading anything.
##
## THE LEVEL LADDER. A sound's loudness is its player level plus its recipe's own
## peak, and the set is ordered on that sum, quietest first:
##   beds  <  UI cues  <  event stings (minor < major < critical)  <  election sting
## A cue the player triggers is quieter than news the world sends, and the one
## sound a term ends on stays the loudest -- V3.6's -8 dB, unchanged. Nothing is
## louder than -8: anything over the game's own brass is a second aesthetic, and
## U5a settled that there is one. tests/test_sound.gd measures the ladder on the
## rendered samples, not on these numbers.
##
## A ONE-SHOT recipe: rate (Hz), duration_s, attack_s (the ramp that keeps the
## first sample from being a step -- a click), env_decay (1/s, one exp over the
## whole sound), level_db (the player's volume), and partials, each
## [hz, amplitude, own_decay (1/s, on top of env), onset_s]. An onset > 0 starts
## that partial late with its own attack, which is how a two-note cue is one
## buffer rather than two players to keep in step.
##
## A BED recipe: rate, loop_s, level_db, fade_s, and partials, each
## [hz, amplitude, swell_hz, swell_phase]: a sine whose amplitude breathes
## between 0 and 1 at swell_hz. The loop is seamless only if every hz and every
## swell_hz completes a WHOLE number of cycles in loop_s -- the test checks it, so
## a retuned bed that would click at its seam fails rather than ships.

const RATE := 44100

## Beds are low drones with nothing above ~400 Hz, so half the rate loses
## nothing audible and halves the synthesis -- which is the cost that matters:
## a 16 s bed is ~380 ms of GDScript (measured 2026-10-17), built off the main
## thread by sound_bed.gd so neither the menu's first frame nor the loading bar
## pays for it.
const BED_RATE := 22050

## V3.6's election sting, moved here from sting.gd unchanged: D3-A3-D4, a low
## toll that fits a result plate. Its bytes are pinned by SHA-256 in
## tests/test_sound.gd, so the move is proved identical rather than claimed.
const ELECTION := {
	"rate": RATE, "duration_s": 1.4, "attack_s": 0.012, "env_decay": 2.6,
	"level_db": -8.0,
	"partials": [
		[146.83, 0.44, 0.0, 0.0],
		[220.0, 0.27, 3.4, 0.0],
		[293.66, 0.18, 4.2, 0.0],
	],
}

## UI cues: a window opening or closing, the clock paused or resumed, a region
## declaring on election night. Short (under a quarter second, so none overlaps
## the next of its kind at a player's pace) and high and soft, so they sit above
## the beds without reading as news. Only where V4.9a's motion already marks a
## change -- a button press that changes nothing on screen makes no sound,
## because a cue on every click is noise the player learns to hate.
const CUES := {
	# E6 over B6: a light tick, rising -- something arrived.
	"open": {
		"rate": RATE, "duration_s": 0.09, "attack_s": 0.003, "env_decay": 38.0,
		"level_db": -22.0,
		"partials": [[1318.51, 0.34, 0.0, 0.0], [1975.53, 0.16, 12.0, 0.0]],
	},
	# A fifth lower than open and quieter: the same gesture, going away.
	"close": {
		"rate": RATE, "duration_s": 0.08, "attack_s": 0.003, "env_decay": 44.0,
		"level_db": -24.0,
		"partials": [[987.77, 0.34, 0.0, 0.0], [1479.98, 0.14, 12.0, 0.0]],
	},
	# Two notes falling a fourth (A5 to E5): the world stops.
	"pause": {
		"rate": RATE, "duration_s": 0.24, "attack_s": 0.004, "env_decay": 12.0,
		"level_db": -21.0,
		"partials": [[880.0, 0.3, 18.0, 0.0], [659.26, 0.32, 0.0, 0.07]],
	},
	# The same two notes rising: the world runs again.
	"resume": {
		"rate": RATE, "duration_s": 0.24, "attack_s": 0.004, "env_decay": 12.0,
		"level_db": -21.0,
		"partials": [[659.26, 0.3, 18.0, 0.0], [880.0, 0.32, 0.0, 0.07]],
	},
	# G6, 50 ms: one more region in. At DECLARE_S (0.28 s) per beat the ticks
	# stay separate; the count's last region declares with the sting instead.
	"declare": {
		"rate": RATE, "duration_s": 0.05, "attack_s": 0.002, "env_decay": 70.0,
		"level_db": -24.0,
		"partials": [[1567.98, 0.32, 0.0, 0.0], [3135.96, 0.06, 30.0, 0.0]],
	},
}

## The event sting, keyed to V4.4's severity (index = severity - 1). Each step
## is lower, longer and louder than the one before, so the ear ranks an arrival
## before the eye reads the card: a minor bell, a major two-strike, a critical
## low minor chord that rings. Heard (level + rendered peak, measured
## 2026-10-17): -21.3, -19.2, -14.2 dB. The durations are what the envelopes
## need to have decayed under 2% of full scale by the last sample (the test's
## TAIL_MAX): the first cut of major and critical (0.95 s, 1.3 s) ended on a
## click the test caught.
const EVENTS := [
	# Minor: E5 with its fifth and octave above, a single soft bell.
	{
		"rate": RATE, "duration_s": 0.6, "attack_s": 0.004, "env_decay": 6.0,
		"level_db": -17.0,
		"partials": [[659.26, 0.4, 0.0, 0.0], [987.77, 0.2, 3.0, 0.0], [1318.51, 0.1, 6.0, 0.0]],
	},
	# Major: G4, then D5 a beat later over the G an octave up -- two strikes, a
	# question asked twice.
	{
		"rate": RATE, "duration_s": 1.2, "attack_s": 0.005, "env_decay": 3.6,
		"level_db": -11.0,
		"partials": [[392.0, 0.34, 0.0, 0.0], [783.99, 0.12, 4.0, 0.0], [587.33, 0.32, 0.0, 0.15]],
	},
	# Critical: D2 under a D minor triad (D3-F3-A3) and D4 -- dark, and long
	# enough to still be ringing when the card has landed.
	{
		"rate": RATE, "duration_s": 1.8, "attack_s": 0.01, "env_decay": 2.2,
		"level_db": -11.0,
		"partials": [
			[73.42, 0.22, 0.0, 0.0],
			[146.83, 0.28, 0.0, 0.0],
			[174.61, 0.2, 1.5, 0.0],
			[220.0, 0.18, 2.0, 0.0],
			[293.66, 0.1, 3.0, 0.0],
		],
	},
]

## V5.2d. The Voices ladder's levels (settings_panel.gd's row, index 0 is Off and
## never played). The clips are normalised to -16 LUFS with -1.5 dBTP of headroom
## (tools/voice_pipeline.py), so Loud is the clip as made and nothing goes above
## it; Normal sits a step under the critical sting's -11 dB peak so the line reads
## as speech beside the cues rather than over them.
## V5.3-0 (d): the two losing stings, synthesized on the ELECTION precedent because
## no losing sting with a clean licence exists (docs/design/v5.3-0-music-sourcing.md).
## Both are a low, string-like tone (a fundamental under two soft harmonics) and
## both stay under the election toll, the loudest thing the game plays.
const STINGS := {
	# About 2 s: E3 falling a minor third to C#3, no resolution, a short dry tail.
	# A bill lost is a setback, not a death: sober, and quieter than election night.
	"vote_failed": {
		"rate": RATE, "duration_s": 2.0, "attack_s": 0.03, "env_decay": 1.2,
		"level_db": -16.0,
		"partials": [
			[164.81, 0.30, 4.0, 0.0], [329.63, 0.10, 6.0, 0.0], [494.44, 0.05, 8.0, 0.0],
			[138.59, 0.32, 1.4, 0.45], [277.18, 0.10, 2.4, 0.45], [415.77, 0.05, 3.4, 0.45],
		],
	},
	# About 4 s: A3, F3, E3 falling slowly, coming to rest on an open fifth (D3 and
	# A3) over a low D2 drone that fades. Grave and final, no game-over cliche;
	# louder and longer than the failed vote, so the two never sound alike.
	"election_lost": {
		"rate": RATE, "duration_s": 4.0, "attack_s": 0.05, "env_decay": 0.6,
		"level_db": -11.0,
		"partials": [
			[73.42, 0.20, 0.4, 0.0],
			[220.0, 0.26, 3.0, 0.0], [440.0, 0.06, 5.0, 0.0],
			[174.61, 0.26, 3.0, 0.6], [349.23, 0.06, 5.0, 0.6],
			[164.81, 0.26, 3.0, 1.2], [329.63, 0.06, 5.0, 1.2],
			[146.83, 0.26, 0.8, 1.8], [220.0, 0.18, 0.8, 1.8],
		],
	},
}

## V5.3-0 (d): the Music setting's steps (Off, Quiet, Normal, Loud), far under
## the voices: music is a floor the speech sits on.
const MUSIC_DB := [-80.0, -30.0, -24.0, -18.0]
## How far the music drops while a voice line plays, and how fast it moves.
const DUCK_DB := 12.0
const DUCK_DB_PER_S := 30.0

const VOICE_DB := [-80.0, -12.0, -6.0, 0.0]

## Ambient beds, one per screen. 16 s loops: long enough that the swells do not
## read as a pattern, and every frequency sits on the 1/16 Hz grid that makes
## the loop seamless (D2 is 73.4375 here rather than 73.42 -- 0.02 Hz off pitch
## costs nothing audible; a click every sixteen seconds costs everything).
## fade_s: a bed swells in and out rather than starting or stopping on a cut.
## Levels: a bed's partials sum to a peak of about -6 dB, so it is set low enough
## that its PEAK sits under the quietest UI tick (heard -38.6 and -39.9 dB against
## the close cue's -34.7) -- a drone is continuous, and at equal peak it would
## read far louder than a 50 ms tick.
const BEDS := {
	# The front door: an open D -- D2, A2, D3, A3 and a faint E4 -- unhurried,
	# not yet a mood. Each partial swells at its own rate and phase, so the
	# chord turns over slowly instead of pulsing as one.
	"menu": {
		"rate": BED_RATE, "loop_s": 16.0, "level_db": -32.0, "fade_s": 2.0,
		"partials": [
			[73.4375, 0.3, 0.0625, 0.0],
			[110.0, 0.22, 0.125, 1.6],
			[146.875, 0.16, 0.1875, 3.1],
			[220.0, 0.08, 0.0625, 4.4],
			[329.625, 0.05, 0.25, 2.2],
		],
	},
	# The desk: A minor and lower -- A1, E2, A2, C3 -- quieter than the menu's,
	# because here it sits under a game the player is reading for hours.
	"game": {
		"rate": BED_RATE, "loop_s": 16.0, "level_db": -34.0, "fade_s": 3.0,
		"partials": [
			[55.0, 0.3, 0.0625, 0.0],
			[82.5, 0.2, 0.125, 2.0],
			[110.0, 0.14, 0.0625, 4.0],
			[130.8125, 0.07, 0.1875, 1.0],
		],
	},
}

## The floor a bed fades from and to: -60 dB is inaudible under any room noise,
## and a fade that starts lower only spends its first half being silent.
const SILENT_DB := -60.0
