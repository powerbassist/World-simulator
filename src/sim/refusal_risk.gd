extends RefCounted

## What refusing an audience risks, and what a word of silence spares -- the V5.3 audience
## reads (the parent's card of 2026-11-13; mockup C's Refuse card: "a brief likely within a
## year, about -0.6 approval"). Deal's leaf: Deal.refusal_risk() and Deal.silence_worth()
## are the doors the scene reads.
##
## A BRIEF IS NOT DRAWN. characters.gd runs one when a person's grudge stands at
## GRUDGE_BRIEF_THRESHOLD and they owe the president no silence, once a month at most,
## after the acts ahead of it in ACT_KEYS. So there is no chance to read off a roll: the
## honest figure is a projection, and the one this file makes is THE WORLD AS IT STANDS --
## on a copy, the refusal priced through the same door Refuse takes (a decline, or a held
## audience settled as declined: the same price, the broken word included), then the real
## Characters month run HORIZON times with today's meters, counting this person's briefs.
## The acts' order, the silence gate, the relief a brief takes and the one-act rule are
## characters.gd's own, not copied. What the copy cannot see is the world moving: a want
## served or denied later, a second refusal, a deal. tests/test_refusal_risk.gd measures
## how far that carries on a real run and states the band.
##
## Two more limits, both of the copy: the commitment judge never runs on it, so a silence
## already owed stands for the whole horizon; and Grant's own relief is not in the silence
## figure, which is what the person would do left alone with no word of silence.
##
## The approval is the strip's convention (the density probe's and the campaign panel's):
## APPROVAL_SPAN times each brief bloc's size times the act's own offset
## (Characters.brief_magnitude). It is the move of the approval TARGET; the realised move
## is smaller, since approval walks to its target and the act's share of the offset fades
## (ACT_OFFSET_MONTHLY_KEEP).

const Audiences = preload("res://src/sim/audiences.gd")
const AudK = preload("res://src/sim/audience_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const DealK = preload("res://src/sim/deal_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

## The months the projection runs: the silence's own term, so a refusal and a word of
## silence are read over the same year.
const HORIZON := DealK.SILENCE_MONTHS


## Refused now: {briefs, first_month, approval_pt, basis}. `briefs` this person runs in the
## HORIZON months after the refusal, `first_month` the first of them counted from now (1 is
## next month's tick), -1 for none; `approval_pt` one brief's price; `basis` names the
## assumption. {} when the request or its person is unknown.
static func of_refusal(state, loader, request_id: String) -> Dictionary:
	var copy = state.duplicate_state()
	var cns = copy.player()
	var row := Audiences.request(cns, request_id)
	if row.is_empty() or not loader.person_by_id.has(String(row.get("person_id", ""))):
		return {}
	if not bool(Audiences.decline(copy, cns, loader, request_id).get("ok", false)):
		Audiences.settle(copy, cns, loader, request_id, AudK.STATUS_DECLINED)
	return _project(copy, loader, String(row["person_id"]))


## Granted a word of silence: the same figures with nothing written -- what this person
## would do over the silence's term left alone, so what the silence spares.
static func of_silence(state, loader, request_id: String) -> Dictionary:
	var row := Audiences.request(state.player(), request_id)
	if row.is_empty() or not loader.person_by_id.has(String(row.get("person_id", ""))):
		return {}
	return _project(state.duplicate_state(), loader, String(row["person_id"]))


## The real Characters month, HORIZON times on `copy`, with the meters of today.
static func _project(copy, loader, pid: String) -> Dictionary:
	var person = loader.person_by_id[pid]
	var magnitude := Characters.brief_magnitude(person, float(copy.player().person_standing.get(pid, 0.0)))
	var approval := 0.0
	for bloc in CK.BRIEF_BLOCS:
		approval += OpinionK.APPROVAL_SPAN * float(OpinionK.BLOC_SIZE.get(bloc, 0.0)) * magnitude
	var meters := WorldMonth.character_meters(copy)
	var briefs := 0
	var first := -1
	for month in HORIZON:
		for act in Characters.tick_month(copy, loader, meters):
			if String(act["act"]) == "brief_against" and String(act["person_id"]) == pid:
				briefs += 1
				if first < 0:
					first = month + 1
	return {"briefs": briefs, "first_month": first, "approval_pt": approval, "basis": "as_things_stand"}
