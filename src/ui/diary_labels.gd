extends RefCounted

## The Diary's labels, out of calendar_panel.gd at the month page (its size ratchet).

const K = preload("res://src/sim/calendar_constants.gd")
const Strings = preload("res://src/ui/strings.gd")

## A fixed date's word in a grid cell (the long name rides on the hover).
const FIXED_SHORT := {
	K.FIXED_ELECTION: "Election",  # i18n: msgid
	K.FIXED_EP_ELECTION: "EU election",  # i18n: msgid
	K.FIXED_EXECUTIVE: "Presidential",  # i18n: msgid
	K.FIXED_HEAD_OF_STATE: "Term ends",  # i18n: msgid
	K.FIXED_COUNCIL_PROPOSAL: "Council",  # i18n: msgid
	K.FIXED_COUNCIL_VOTE: "Council vote",  # i18n: msgid
	K.FIXED_COUNCIL_RATIFICATION: "Ratify by",  # i18n: msgid
	K.FIXED_DISSOLUTION: "Dissolution",  # i18n: msgid
	K.FIXED_COOLDOWN: "Available",  # i18n: msgid
	K.FIXED_PROJECT: "Opens",  # i18n: msgid
	K.FIXED_REFERENDUM: "Referendum",  # i18n: msgid
	K.FIXED_EVENT: "Deadline",  # i18n: msgid
}
const BOOKING_SHORT := {K.KIND_LAW: "Bill", K.KIND_ADDRESS: "Address", K.KIND_RESHUFFLE: "Reshuffle"}  # i18n: msgid


## The word a grid cell shows for a register row or a fixed date: the person's surname for an
## audience, the host nation for a visit, else the kind's short word.
static func short(row: Dictionary, loader) -> String:
	var kind := String(row.get("kind", ""))
	if not row.has("status"):
		return Strings.t(String(FIXED_SHORT.get(kind, kind)))
	if kind == K.KIND_AUDIENCE:
		var name := String(loader.person_name(String(row.get("target_id", ""))))
		return name.get_slice(" ", name.get_slice_count(" ") - 1)
	if kind == K.KIND_DIPLOMATIC:
		var id := String(row.get("target_id", ""))
		return loader.nation_name(id)
	return Strings.t(String(BOOKING_SHORT.get(kind, kind)))

## What each fixed-date kind is called on screen. Presentation, so it lives here
## rather than in calendar_constants.gd — src/sim/ names the kind, the panel says
## it in English.
const FIXED_LABEL := {
	K.FIXED_ELECTION: "Legislative election",  # i18n: msgid
	K.FIXED_EP_ELECTION: "European election",  # i18n: msgid
	K.FIXED_EXECUTIVE: "Presidential election",  # i18n: msgid
	K.FIXED_HEAD_OF_STATE: "Head of state's term ends",  # i18n: msgid
	K.FIXED_COUNCIL_PROPOSAL: "Council proposes",  # i18n: msgid
	K.FIXED_COUNCIL_VOTE: "Council votes",  # i18n: msgid
	K.FIXED_COUNCIL_RATIFICATION: "Ratification deadline",  # i18n: msgid
	K.FIXED_DISSOLUTION: "Dissolution available again",  # i18n: msgid
	K.FIXED_COOLDOWN: "Available again",  # i18n: msgid
	K.FIXED_PROJECT: "Opens",  # i18n: msgid
	K.FIXED_REFERENDUM: "Referendum",  # i18n: msgid
	K.FIXED_EVENT: "Deadline",  # i18n: msgid -- one word on the Diary (RF6)
}

const KIND_LABEL := {
	K.KIND_DIPLOMATIC: "Diplomatic act",  # i18n: msgid
	K.KIND_LAW: "Propose a law",  # i18n: msgid
	K.KIND_RESHUFFLE: "Reshuffle a portfolio",  # i18n: msgid
}
