extends RefCounted

## The asks outside the hazard -- V5.2b. Who is invited to ask this month before
## the seeded monthly ask runs: the people a programme entry gone live names (b1,
## moved here verbatim from audiences.gd) and, the month after the player's
## reshuffle, everyone whose office want is unserved (b3: the pre-mortem's third
## trigger). The model is docs/audiences-model.md "The triggers".
##
## A PURE READ of stamps other systems wrote -- the programme's months_live, the
## cabinet's reshuffle_month -- handed to Audiences, which keeps the lane's rules
## (the cooldown, one open request each, MAX_PENDING) and writes the request. So an
## invitation is a candidate, never a guaranteed card.
##
## THE RESHUFFLE IS THE PLAYER'S. Cabinet.assign() stamps it; a government seated
## by an election or a formation (Cabinet.seat) does not, because a new government
## is a different moment from a reshuffle and the want ladder already reads it.
## Read at `now - 1`: the player reshuffles on a day of the month, the tick after
## invites. C10, decided at b3: an office want is about the party's seat, which is
## what Characters.want_served() judges for a portfolio -- the request promises no
## person-level appointment.

const Characters = preload("res://src/sim/characters.gd")


## [[person, want], ...] in the order they are invited: the programme's people in
## roster order (each person's first want naming a live entry), then the
## reshuffle's (each person's first unserved office want).
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
	for person in people:
		for want in person.wants:
			var object := String(want["object"])
			if (object.begins_with("office:portfolio:") or object == "office:premiership") \
					and not Characters.want_served(ns, person, want, meters, leaders):
				out.append([person, want])
				break
	return out
