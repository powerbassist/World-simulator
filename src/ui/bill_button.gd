extends RefCounted

## "Table a bill" for an ownership bill -- V5.2 b+ R14 (docs/design/v5.2-bplus-spec.md
## "R14"; Systems' Bills). Owning a firm is a law's to decide, so the companies panel
## offers each ready bill as this button, and a press opens the bill's briefing
## through the Legislature: the one propose path (brief_requested -> main's briefing
## -> run_proposal). The Legislature is found through the window manager's group, so
## main.gd and law_panel.gd (both at their size baselines) are untouched. Its own
## file because companies_panel.gd sits at the 300-line ceiling.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const Bills = preload("res://src/sim/bills.gd")
const Legislature = preload("res://src/sim/legislature.gd")


## The firm's ownership bills the player may table now: Legislature.available's
## gates (a lost vote's cooldown, a once-only bill) on top of the verb's own, the
## filter the Legislature's list reads, so no button opens a briefing that refuses.
static func ready_bills(state, ns, loader, company_id: String) -> Array:
	return Legislature.available(ns, Bills.ownership(state, ns, loader, company_id))


static func make(loader, bill) -> Button:
	var verb = null
	for a in loader.company_actions:
		if String(a.id) == String(bill.effects["company_ownership"]["action_id"]):
			verb = a
	var button := PanelKit.sized(Button.new())
	button.name = "TableBill"  # i18n: ok a node name, found by tests
	button.set_meta("law_id", String(bill.id))
	button.text = Strings.t("Table a bill: %s") % Strings.row_name("company-actions", verb)
	button.tooltip_text = Strings.t("A law, voted by the assembly: %s") % Strings.law_name(bill)
	button.pressed.connect(func() -> void:
		var windows = button.get_tree().get_first_node_in_group(WindowManager.GROUP)
		var law_panel = windows.content("legislature") if windows != null else null
		if law_panel != null:
			law_panel.brief_requested.emit(bill))
	return button
