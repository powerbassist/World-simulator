extends RefCounted

## The Promises section's opening line: the term's programme, read-only. Split
## from campaign_panel.gd at its size ratchet (V5.3-0 (b), the campaign diet).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const ProgrammeDistance = preload("res://src/ui/programme_distance.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")


## The term's programme as a READ-ONLY line, docs/programme-model.md section 4's
## mitigation: pledges and programmes are kept apart, but "apart" must not rot
## into two lists the player reconciles by hand -- so the Promises section opens
## on the programme, read through the same Programme.this_term() /
## progress_of() pair and the same distance words (programme_distance.gd) as the
## file page and the Presidency page. Never a second answer to one read, and never a write: the choice
## happens on the Agenda or nowhere. A concluded entry prints its verdict rather
## than a distance -- a figure over a delivered programme would be a lie about a
## term that is already priced.
static func build(body: Control, state, loader) -> void:
	var ns = state.player()
	var this_term: Array = Programme.this_term(ns)
	if this_term.is_empty():
		if Programme.is_term_start(ns):
			PanelKit.line(body, Strings.t("No programme yet: choose it on its file in the Folder."), PanelKit.Tone.DIM)
		else:
			PanelKit.line(body, Strings.t("No programme was set this term."), PanelKit.Tone.DIM)
		return
	for entry in this_term:
		var terms: Dictionary = Programme.terms_of(loader, String(entry["entry_id"]))
		if terms.is_empty():
			# Content the loader no longer defines: the id stands in rather
			# than a bar over nothing, the retired Agenda's rule.
			PanelKit.line(body, Strings.t("%s -- the content behind it is gone; it concludes on the next tick.") % String(entry["entry_id"]), PanelKit.Tone.DIM)
			continue
		var name_text := Strings.row_name("programme", terms)
		match String(entry["status"]):
			ProgrammeK.STATUS_ACTIVE:
				PanelKit.line(body, "%s · %s" % [name_text, ProgrammeDistance.of(state, terms)], PanelKit.Tone.PLAIN)
			ProgrammeK.STATUS_COMPLETE:
				ResultTone.tint(PanelKit.line(body, Strings.t("%s · Delivered.") % name_text, PanelKit.Tone.PLAIN), ResultTone.GOOD)
			ProgrammeK.STATUS_FAIL:
				ResultTone.tint(PanelKit.line(body, Strings.t("%s · Missed.") % name_text, PanelKit.Tone.PLAIN), ResultTone.BAD)
			_:
				PanelKit.line(body, Strings.t("%s · Overtaken by the world.") % name_text, PanelKit.Tone.DIM)
