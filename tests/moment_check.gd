extends RefCounted

## Which sting a Music.moment() placed, for the tests that pin a moment (#223 QA's
## TAKE on the merge with #228): a COUNT of players passes whichever sting plays,
## so a fallen 49.3 playing the passing sting stayed green once vote_passed had a
## recorded file. Not a test: a helper the tests preload.

const Music = preload("res://src/ui/music.gd")
const Sound = preload("res://src/ui/sound.gd")

## A manifest naming a recorded file for two moments and none for the others, so
## one run checks both paths. The files are voice clips: any committed .ogg does.
const FIXTURE := {"stings": {
	"vote_passed": {"file": "../voice/activist_f_30/agree.ogg"},
	"election_won": {"file": "../voice/activist_f_30/refuse.ogg"},
}}


## Whether `id` makes any sound under the manifest Music reads now.
static func sounds(id: String) -> bool:
	return Music.track("stings", id) != "" or String(Music.MOMENTS.get(id, "")) != ""


## Whether `player` is moment `id`'s sting under the manifest Music reads now: its
## recorded file when the manifest names one, else its synthesized stand-in.
static func plays(player: Node, id: String) -> bool:
	if not (player is AudioStreamPlayer):
		return false
	var file := Music.track("stings", id)
	if file != "":
		return String(player.get_meta("track", "")) == file
	var synth := String(Music.MOMENTS.get(id, ""))
	return synth != "" and (player as AudioStreamPlayer).stream == Sound.stream(synth)


## The last AudioStreamPlayer child of `parent`, the sting a moment just placed.
static func last_player(parent: Node) -> Node:
	for i in range(parent.get_child_count() - 1, -1, -1):
		if parent.get_child(i) is AudioStreamPlayer:
			return parent.get_child(i)
	return null
