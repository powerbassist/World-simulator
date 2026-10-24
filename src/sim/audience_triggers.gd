extends RefCounted

## The asks outside the hazard -- V5.2b. Who is invited to ask this month before
## the seeded monthly ask runs: the people a programme entry gone live names (b1,
## moved here verbatim from audiences.gd) and, the month after the player handed a
## portfolio to another party, whoever wanted that portfolio and did not get it
## (b3: the pre-mortem's third trigger). The model is docs/audiences-model.md
## "The triggers".
##
## A PURE READ of stamps other systems wrote -- the programme's months_live, the
## cabinet's reshuffle_month -- handed to Audiences, which keeps the lane's rules
## (the cooldown, one open request each, MAX_PENDING) and writes the request. So an
## invitation is a candidate, never a guaranteed card.
##
## THE RESHUFFLE IS THE PLAYER'S, AND IT MOVED A PORTFOLIO. Cabinet.assign() stamps
## the month and the portfolio when the portfolio changes hands; a no-op assign and
## a government seated by an election or a formation (Cabinet.seat) stamp nothing --
## nobody's office moved, or a new government is another moment the want ladder
## already reads. A portfolio reshuffle never moves the premiership, so only that
## portfolio's wanters ask. Read at `now - 1`: the player reshuffles on a day of the
## month, the tick after invites. (b3's first measurement invited every office want
## at every assign, and audience_probe A2, which books a reshuffle every month --
## mostly no-ops -- re-invited the same four people all term.) C10, decided at b3:
## an office want is about the party's seat, which is what Characters.want_served()
## judges for a portfolio -- the request promises no person-level appointment.

const Characters = preload("res://src/sim/characters.gd")


## [[person, want], ...] in the order they are invited: the programme's people in
## roster order (each person's first want naming a live entry), then the
## reshuffle's (each person's unserved want for the portfolio that moved).
static func invitations(state, ns, loader, meters: Dictionary, leaders: Dictionary, now: int) -> Array:
	var out := []
	var people: Array = loader.people.get(state.player_nation_id, [])
	var live := {}
	for entry in ns.programme:
		if int(entry.get("chosen_term", -1)) == int(ns.terms_served) and int(entry.get("months_live", 0)) == 1 \
				and String(entry.get("status", "")) == "active":
			live["programme:%s" % String(entry["entry_id"])] = true
	for person in people:
		for want in person.wants:
			if live.has(String(want["object"])):
				out.append([person, want])
				break
	if int(ns.reshuffle_month) != now - 1:
		return out
	var moved := "office:portfolio:%s" % String(ns.reshuffle_portfolio)
	for person in people:
		for want in person.wants:
			if String(want["object"]) == moved and not Characters.want_served(ns, person, want, meters, leaders):
				out.append([person, want])
				break
	return out
