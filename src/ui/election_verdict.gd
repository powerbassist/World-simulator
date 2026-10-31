extends RefCounted

## Which result on an election night carries the verdict, and what it says --
## moved out of election_panel.gd at V5.1-d1b2, when the polls-closed beat grew
## the panel past its size baseline. The reading is the panel's own, unchanged:
## the executive result carries the verdict where there is one, a term limit ends
## the run whatever the vote said, and a legislative election under a separate
## executive decides a majority, not the term.

const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")


## {national, eu_result, executive, defeated, termed_out, title} for `results`.
## The verdict's title on `label`, in its tone (RF7): RE-ELECTED and DEFEATED are
## the word, the tone colours them; a neutral title is plain.
static func show_title(label: Label, verdict: Dictionary) -> void:
	ResultTone.say(label, String(verdict["title"]), String(verdict["tone"]))


static func read(results: Array, ns) -> Dictionary:
	var title := ""
	var national = null
	var eu_result = null
	var executive = null
	for r in results:
		if r["kind"] == "national":
			national = r
		elif r["kind"] == "eu_parliament":
			eu_result = r
		elif r["kind"] == "executive":
			executive = r
		elif r["kind"] == "termed_out":
			# Read as the executive verdict for every purpose on this screen -- it
			# ends the term exactly as a lost election does -- while staying a
			# distinct kind everywhere else. See elections.gd.
			executive = r

	# Only an executive election can end the player's term. Where the executive
	# is drawn from the chamber there is no separate executive result and the
	# national one carries the verdict, exactly as before V1.1a.
	var verdict_result = executive if executive != null else national
	var defeated: bool = verdict_result != null and not verdict_result["incumbent_largest"] and not ns.in_government
	# V1.6 audit, V1. A term limit ends the run whatever the vote said, so the
	# defeat test above misses it -- the incumbent's PARTY may well have won.
	var termed_out: bool = verdict_result != null and bool(verdict_result.get("termed_out", false))
	if termed_out:
		defeated = true

	var snap: bool = national != null and bool(national.get("snap", false))

	# RF7: the verdict's ResultTone, from the same keys as the title. A term limit
	# and a new assembly that changes no majority are neutral; cohabitation is
	# the player losing the chamber.
	var tone := ""
	if executive != null:
		title = Strings.t("TERM LIMIT") if termed_out else (Strings.t("DEFEATED") if defeated else Strings.t("RE-ELECTED"))
		tone = "" if termed_out else (ResultTone.BAD if defeated else ResultTone.GOOD)
	elif national != null:
		# A legislative election under a separately elected executive does not
		# end the term. It decides whether the player still commands a majority.
		if ns.has_executive:
			if ns.is_cohabitation:
				title = Strings.t("COHABITATION")
				tone = ResultTone.BAD
			elif snap:
				title = Strings.t("SNAP ELECTION")
			else:
				title = Strings.t("NEW ASSEMBLY")
		else:
			title = Strings.t("DEFEATED") if defeated else Strings.t("RE-ELECTED")
			tone = ResultTone.BAD if defeated else ResultTone.GOOD
	else:
		title = Strings.t("EUROPEAN PARLIAMENT ELECTION")
	return {
		"national": national, "eu_result": eu_result, "executive": executive,
		"defeated": defeated, "termed_out": termed_out, "title": title, "tone": tone,
	}
