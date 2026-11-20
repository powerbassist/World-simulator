extends RefCounted

## The Diary's labels, out of calendar_panel.gd at the month page (its size ratchet).

const K = preload("res://src/sim/calendar_constants.gd")

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
