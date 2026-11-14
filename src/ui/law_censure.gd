extends RefCounted

## What a division's record says about a bypassed or rebel Assembly -- the 49.3 censure summary
## and the rebellion line, moved out of law_panel.gd (V5.3 screen 4, PR 1: the tab host sits at
## its size ceiling and the order paper needed the room). Verbatim, with the panel's state and
## loader handed in; no behaviour moved.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")


## What the assembly did about being bypassed. Names the parties that moved to
## censure, so a survived 49.3 still tells the player who came after them.
static func box(state, loader, censure: Dictionary) -> Control:
	var box := VBoxContainer.new()
	if censure.is_empty():
		return box

	var ns = state.player()

	PanelKit.line(box, Strings.t("Adopted without a vote under Article 49.3."), PanelKit.Tone.PLAIN)

	PanelKit.line(box, Strings.t("Censure motion: %d for · %d against · %d abstained, of %d seats (needs %d)") % [
		censure["for_seats"], censure["against_seats"], censure["abstain_seats"],
		censure["seats_total"], censure["threshold"],
	], PanelKit.Tone.PLAIN)

	var verdict := Label.new()
	if censure["carried"]:
		verdict.text = Strings.t("CENSURED. %s falls; %s %s now heads the government.") % [
			loader.person_name(censure["pm_person_id"]), ns.head_of_government_title, loader.person_name(ns.pm_person_id)
		]
	else:
		verdict.text = Strings.t("The motion failed. %s %s survives and the law stands.") % [
			ns.head_of_government_title, loader.person_name(ns.pm_person_id)
		]
	box.add_child(verdict)

	var movers := PackedStringArray()
	for party in loader.parties.get(ns.id, []):
		if censure["party_votes"].get(party.id, "") == "for":
			movers.append(party.party_name)
	if not movers.is_empty():
		PanelKit.line(box, Strings.t("Moved to censure: %s") % ", ".join(movers), PanelKit.Tone.PLAIN)

	var rebellion := rebellion_text(state, loader, censure.get("party_rebels", {}))
	if rebellion != "":
		PanelKit.line(box, rebellion, PanelKit.Tone.PLAIN)

	# Distinct from the line above on purpose: that one is members who ignored
	# their party, this one is parties that walked. Only the second is expelled.
	var defectors: Array = censure["defectors"]
	if not defectors.is_empty():
		PanelKit.line(box, Strings.tn("%d coalition party voted to censure and is out of government.", "%d coalition parties voted to censure and are out of government.", defectors.size()) % defectors.size(), PanelKit.Tone.PLAIN)

	return box


## Who ignored their own party's line, and by how much. The payoff line of the
## whole discipline model -- the player is told which benches they have lost, by
## name, at the moment it costs them a vote.
static func rebellion_text(state, loader, party_rebels: Dictionary) -> String:
	if party_rebels.is_empty():
		return ""
	var parts := PackedStringArray()
	var total := 0
	for party in loader.parties.get(state.player().id, []):
		var rebels: int = int(party_rebels.get(party.id, 0))
		if rebels <= 0:
			continue
		total += rebels
		parts.append("%d %s" % [rebels, party.party_name])
	if parts.is_empty():
		return ""
	return Strings.t("%d seats broke ranks: %s.") % [total, ", ".join(parts)]
