extends Node

## The election sting -- this project's first sound (V3.6). Synthesized in code
## rather than shipped as a binary ON PURPOSE: there is no licence to read, no
## attribution file to keep true, no .import to commit and no fresh-clone
## loading question. The assets/fonts bytes-not-load() discipline exists because
## a font cannot be generated; a two-second chord can. If a later session swaps
## in a recorded sting, the obligations it takes on are listed in the V3.6
## plan's audit section: licence text committed beside the file, load via
## AudioStreamOggVorbis.load_from_buffer(), never load().
##
## V4.9c made it one sound of a set: its recipe (D3-A3-D4, -8 dB, still the
## loudest thing the game plays) moved to sound_constants.gd's ELECTION and its
## synthesis to synth.gd, byte-identical -- tests/test_sound.gd pins the hash.
## This file stays as the name election_panel.gd and its test already call.

const Sound = preload("res://src/ui/sound.gd")
const SoundK = preload("res://src/ui/sound_constants.gd")
const Synth = preload("res://src/ui/synth.gd")


static func _synth() -> PackedByteArray:
	return Synth.one_shot(SoundK.ELECTION)


static func play(parent: Node) -> void:
	Sound.cue(parent, "election")
