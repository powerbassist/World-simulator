extends "res://src/ui/audience_talk_view.gd"

## The money on the table -- V5.3, mockup C4-offer. Two lines in the talk's own grammar answer an
## offer: take it (a money trail, the tag says so) or leave it (she cools). The words of each are the
## president's, from the dialogue; the sim's refusals (Deal.take's `why_not`) hang on the take line
## as its tooltip and put it down. It draws what it is handed and writes nothing.

const DialogueLines = preload("res://src/ui/dialogue_lines.gd")

const TAKE := "money_take"  # i18n: ok a line id
const LEAVE := "money_leave"  # i18n: ok a line id


## `money`: {take_why: String, ...}; `vars` the dialogue's variables; `resource` the stance's lines.
## Async: the sentences arrive from the addon, and `still_mine` says whether a newer build took over.
func fill(money: Dictionary, vars: Dictionary, resource, still_mine: Callable) -> void:
	var rows: Array = []
	for def in [[TAKE, "trail", String(money.get("take_why", "")), tr("Your benefactors are welcome.")], [LEAVE, "cools", "", tr("Keep your money.")]]:
		var said: String = await DialogueLines.line(resource, String(def[0]), vars)
		if not still_mine.call():
			return
		var open_quote := "“"  # i18n: ok a quotation mark
		var shut_quote := "”"  # i18n: ok a quotation mark
		rows.append({"id": def[0], "topic": "money", "tag": def[1], "args": {}, "people": [], "asked": false, "blocked": def[2],
			"prefix": open_quote + (said if said != "" else String(def[3])) + shut_quote, "suffix": ""})
	show_lines(rows)
