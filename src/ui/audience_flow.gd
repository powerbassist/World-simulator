extends RefCounted

## The audience's states, in ONE place -- V5.3 (the author's C4 / C4-talk). The old scene
## kept them in scattered flags (`_over`, a reason string compared for "struck", the grid
## rebuilt on every press), and H3 -- "no choice resets on a press" -- was what that cost:
## the date, the person and the line chosen went back to their defaults after each verb.
## Here a state is a name in a table, an event is the only way to move, and what the player
## has chosen lives beside it and is never rebuilt:
##
##   MONEY         an offer of money is on the table (corrupt, the rare draw): answered first,
##                 the cards held (the sim refuses Grant and Bargain while it is open)
##   QUESTION      the three cards: Grant / Counter / Refuse
##   COUNTER_OPEN  the Counter's date field is open (a QUESTION with its grid down)
##   GRANTED       a deal is struck (Grant, or a Counter she took): the band and the talk
##   ANSWERED      a line was put to her and she answered: still the talk
##   REFUSED       Refuse was pressed: her parting line, what it cost, the way out
##   ENDED         the audience is over; the scene comes down
##
## "Talk after Refuse" is not a state the table has: REFUSED goes to ENDED only, which is
## the test of the author's second ruling. The deal's own state is the sim's (the session's
## `struck`): `sync()` takes it from the view the wiring hands in, so the table is not asked
## to remember what the session already knows.

enum S { QUESTION, COUNTER_OPEN, GRANTED, ANSWERED, REFUSED, ENDED, MONEY }

const NEXT := {
	# Take is Grant plus the money (Deal.take): a struck deal. Leave is the question, with the offer gone.
	S.MONEY: {"money_left": S.QUESTION, "deal_struck": S.GRANTED, "abandon": S.ENDED},
	S.QUESTION: {"open_date": S.COUNTER_OPEN, "deal_struck": S.GRANTED, "refuse": S.REFUSED, "money_due": S.MONEY, "abandon": S.ENDED},
	S.COUNTER_OPEN: {"close_date": S.QUESTION, "deal_struck": S.GRANTED, "refuse": S.REFUSED, "money_due": S.MONEY, "abandon": S.ENDED},
	S.GRANTED: {"ask": S.ANSWERED, "end": S.ENDED, "abandon": S.ENDED},
	S.ANSWERED: {"ask": S.ANSWERED, "end": S.ENDED, "abandon": S.ENDED},
	S.REFUSED: {"end": S.ENDED, "abandon": S.ENDED},
	S.ENDED: {},
}

var state: int = S.QUESTION
## The Counter's date: {year, month, day}, {} until one is picked (the view's default stands).
var date := {}
## The talk, ranked once when the deal is struck (TalkMenu.lines) and held, so a press does
## not re-rank it; each row {id, topic, tag, args, facts, people, ...}.
var lines: Array = []
## line id -> true once it was put to her; the id, not the topic, because three lines are Opinion.
var asked := {}
## line id -> the person id picked among a gossip's faces; survives every redraw.
var picked := {}
## True once the talk has been ranked: the ranking is held, never redone.
var ranked := false


## True when `event` moves the flow; an event the state has no row for changes nothing.
func fire(event: String) -> bool:
	var row: Dictionary = NEXT[state]
	if not row.has(event):
		return false
	state = int(row[event])
	return true


## The sim's half: a struck deal is GRANTED whatever the UI was doing; an offer of money still open
## holds the question (MONEY) and, answered, gives way to the question or, taken, to the deal.
## Nothing else is read, and a struck or refused audience never goes back to the money.
func sync(struck: bool, money_open := false) -> void:
	if state == S.MONEY:
		if struck:
			fire("deal_struck")
		elif not money_open:
			fire("money_left")
	elif struck and (state == S.QUESTION or state == S.COUNTER_OPEN):
		fire("deal_struck")
	elif money_open and (state == S.QUESTION or state == S.COUNTER_OPEN):
		fire("money_due")


## The talk is open: a deal is struck and the audience is not over.
func in_talk() -> bool:
	return state == S.GRANTED or state == S.ANSWERED


func ask(line_id: String) -> bool:
	if not fire("ask"):
		return false
	asked[line_id] = true
	return true


func pick(line_id: String, person_id: String) -> void:
	picked[line_id] = person_id


func name_of(s: int) -> String:
	return String(S.keys()[s])
