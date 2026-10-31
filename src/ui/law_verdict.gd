extends RefCounted

## The one word a division's result gets on the Legislature's header -- moved out
## of law_panel.gd at V5.1-d1b, where it gained the referendum's own outcome.
##
## ONE WORD PER OUTCOME, the readout rule this ladder was built on: a bill the
## second chamber holds is not FAILED, a bill a court struck was carried, and a
## bill put to the country is neither until the country answers. QA's pre-gate C
## item is the last of those: after "Call it off" the header still said PUT TO
## THE COUNTRY, because the division's result outlives the referendum it called.

const Referendum = preload("res://src/sim/referendum.gd")
const Strings = preload("res://src/ui/strings.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Music = preload("res://src/ui/music.gd")


static func word(result: Dictionary, ns) -> String:
	# A carried division on route B is a THIRD outcome and neither word fits it: the
	# assembly said yes and the country has not been asked. Reading "FAILED" against a
	# referendum the player just called is the em-dash-against-a-live-figure bug
	# docs/defence-model.md's screenshot pass found, one block on.
	var verdict: String = Strings.t("PASSED") if result["passed"] else Strings.t("FAILED")
	if result.get("referendum_called", false):
		verdict = Strings.t("PUT TO THE COUNTRY")
		# The division's result outlives the referendum it called: once that vote
		# is no longer in flight, its own outcome is the word.
		var answer: Dictionary = ns.last_referendum_result if ns != null else {}
		if ns != null and Referendum.pending_law_id(ns) != String(result.get("law_id", "")) and String(answer.get("law_id", "")) == String(result.get("law_id", "")):
			if bool(answer.get("withdrawn", false)):
				verdict = Strings.t("PUT TO THE COUNTRY, THEN CALLED OFF")
			elif bool(answer.get("passed", false)):
				verdict = Strings.t("CARRIED BY THE COUNTRY")
			else:
				verdict = Strings.t("REFUSED BY THE COUNTRY")
	# V1.1e. Three more outcomes that are not `FAILED`, for the same reason route B
	# is not: a bill the second chamber is holding has not been beaten, a bill it
	# blocked was beaten somewhere the tally below does not show, and a bill the court
	# struck was carried by both chambers and stopped afterwards. One word for four
	# different things is the readout bug this project keeps finding.
	elif result.get("held_by_upper", false):
		verdict = Strings.t("HELD BY THE %s") % result.get("upper_chamber", Strings.t("SECOND CHAMBER")).to_upper()
	elif result.get("blocked_by_upper", false):
		verdict = Strings.t("BLOCKED BY THE %s") % result.get("upper_chamber", Strings.t("SECOND CHAMBER")).to_upper()
	elif result.get("struck_down", false):
		verdict = Strings.t("STRUCK DOWN")
	# THE MOOT RELEASE (the ultra pass-6 finding), and it is the same one-word-
	# per-outcome rule as the four above: a repeal releasing from its hold into
	# an empty book did not come into force over anybody -- its target was
	# already gone, nothing followed, and no override price was charged. The
	# released branch below is the release that DID apply.
	elif result.get("target_already_gone", false):
		verdict = Strings.t("MOOT — its target was already gone from the book.")
	# A LAPSED release (V5.0d) is a release too: the hold ran out under a
	# constitution the bill was not written for, and nothing came into force.
	elif result.get("released", false):
		verdict = Strings.t("LAPSED — the constitution it amended is gone.") if result.get("lapsed", false) else Strings.t("IN FORCE, OVER THE %s") % result.get("upper_chamber", Strings.t("SECOND CHAMBER")).to_upper()
	return verdict


## The verdict's ResultTone (V5.3-0 RF7), branch for branch with word(): the same
## result key, never the word. A bill the country or a chamber still holds is
## RISKY (attention, not failure); a moot release and a called-off referendum
## are neutral -- nothing happened to the player.
## `control`, the verdict's line, in the verdict's tone.
static func tint(control: Control, result: Dictionary, ns) -> void:
	ResultTone.tint(control, tone(result, ns))


static func tone(result: Dictionary, ns) -> String:
	var tone_key: String = ResultTone.GOOD if result["passed"] else ResultTone.BAD
	if result.get("referendum_called", false):
		tone_key = ResultTone.RISKY
		var answer: Dictionary = ns.last_referendum_result if ns != null else {}
		if ns != null and Referendum.pending_law_id(ns) != String(result.get("law_id", "")) and String(answer.get("law_id", "")) == String(result.get("law_id", "")):
			if bool(answer.get("withdrawn", false)):
				tone_key = ""
			else:
				tone_key = ResultTone.GOOD if bool(answer.get("passed", false)) else ResultTone.BAD
	elif result.get("held_by_upper", false):
		tone_key = ResultTone.RISKY
	elif result.get("blocked_by_upper", false) or result.get("struck_down", false):
		tone_key = ResultTone.BAD
	elif result.get("target_already_gone", false):
		tone_key = ""
	elif result.get("released", false):
		tone_key = ResultTone.BAD if result.get("lapsed", false) else ResultTone.GOOD
	return tone_key


## The division's sting under `parent` (V5.3-0 (d)), by the verdict's own tone: a
## bill passed or lost; a held bill or a moot one is neither, and plays nothing,
## as does a proposal refused before any division (no "passed" key).
static func sting(parent: Node, result: Dictionary, ns) -> void:
	if not result.has("passed"):
		return
	Music.moment(parent, {ResultTone.GOOD: "vote_passed", ResultTone.BAD: "vote_failed"}.get(tone(result, ns), ""))
