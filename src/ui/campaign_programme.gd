extends RefCounted

## The Promises section's opening line: the term's programme, read-only. Split
## from campaign_panel.gd at its size ratchet (V5.3-0 (b), the campaign diet).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")


## The term's programme as a READ-ONLY line, docs/programme-model.md section 4's
## mitigation: pledges and programmes are kept apart, but "apart" must not rot
## into two lists the player reconciles by hand -- so the Promises section opens
## on the programme, read through the same Programme.this_term() /
## progress_of() / PanelKit.progress_fraction() trio the Agenda and the Overview
## read. Never a second answer to one read, and never a write: the choice
## happens on the Agenda or nowhere. A concluded entry prints its verdict rather
## than a fraction -- a bar over a delivered programme would be a lie about a
## term that is already priced.
static func build(body: Control, ns, loader) -> void:
	var this_term: Array = Programme.this_term(ns)
	if this_term.is_empty():
		if Programme.is_term_start(ns):
			PanelKit.line(body, Strings.t("No programme yet: see the Agenda (K)."), PanelKit.Tone.DIM)
		else:
			PanelKit.line(body, Strings.t("No programme was set this term."), PanelKit.Tone.DIM)
		return
	for entry in this_term:
		var terms: Dictionary = Programme.terms_of(loader, String(entry["entry_id"]))
		if terms.is_empty():
			# Content the loader no longer defines: the id stands in rather
			# than a bar over nothing, agenda_panel.gd's rule.
			PanelKit.line(body, Strings.t("%s -- the content behind it is gone; it concludes on the next tick.") % String(entry["entry_id"]), PanelKit.Tone.DIM)
			continue
		var name_text := Strings.row_name("programme", terms)
		match String(entry["status"]):
			ProgrammeK.STATUS_ACTIVE:
				var read: Dictionary = Programme.progress_of(ns, terms)
				var fraction: float = PanelKit.progress_fraction(
					float(read["current_value"]), float(read["goal_value"]), String(read["progressbar"]))
				PanelKit.line(body, Strings.t("%s · now %s · goal %s · %d%% there") % [
					name_text, Num.f(float(read["current_value"]), 2), Num.f(float(read["goal_value"]), 2), roundi(fraction * 100.0),
				], PanelKit.Tone.PLAIN)
			ProgrammeK.STATUS_COMPLETE:
				PanelKit.line(body, Strings.t("%s · Delivered.") % name_text, PanelKit.Tone.GOOD)
			ProgrammeK.STATUS_FAIL:
				PanelKit.line(body, Strings.t("%s · Missed.") % name_text, PanelKit.Tone.BAD)
			_:
				PanelKit.line(body, Strings.t("%s · Overtaken by the world.") % name_text, PanelKit.Tone.DIM)
