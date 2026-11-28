extends RefCounted

## The Finances page's wiring -- V5.3 screen 4, direction A. Static over main, as the other drivers are: it
## registers the page as the first tab of the Finances domain (domains.gd) and sends its "Open the bill"
## to the Bills tab. The window manager's own sweep rebinds it on a load, like every registered panel.

const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const FinanceSheet = preload("res://src/ui/finance_sheet.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const Strings = preload("res://src/ui/strings.gd")


static func register(main) -> void:
	var panel := FinancesPanel.new()
	main._windows.register("finances", Strings.t("Books"), panel, KEY_B, main.ICONS + "payments.svg")
	panel.setup(main._state, main._loader)
	# G3 S4: the bill's rail stays beside every Finances tab (Books, Public works, Register, Building).
	main._windows.set_aside("finances", panel.rail())
	# R1: the folded line's chevron puts the inbox away; the window manager then opens the rail beside the page.
	panel.rail().unfold_pressed.connect(main._hud.inbox.slide_out)
	panel.go_requested.connect(main._windows.open)
	_stage_sheet(main, panel)
	# The one fiscal command the page sends (a bill tabled, added to or withdrawn): the shell's card and effect baseline.
	panel.committed.connect(func(before: Dictionary, tabling: Dictionary) -> void:
		main._fiscal_committed(Strings.t("Finance bill"), tabling, before))


## The bill's document owns the screen (the author's pick C): a scene on the stack, the world dimmed behind it, Escape
## closes it. The clock holds while it is open and comes back as it was (the parent's ruling P1, the phone call's
## pattern): a player's own pause stays, and so does a decision's hold.
static func _stage_sheet(main, panel: FinancesPanel) -> void:
	var sheet: FinanceSheet = panel.sheet()
	panel.remove_child(sheet)
	# Added shown, then hidden: the stack's holder and dim follow the panel's visibility from its first change.
	sheet.show()
	main._stack.add(ScreenStack.SCENE, sheet, true, panel.close_sheet)
	sheet.hide()
	# The clock follows the document's own visibility, so no way of putting it away can leave it held. The stack's
	# holder re-emits the signal on its panel, so only a change counts.
	var held := {"open": false, "was_paused": false}
	sheet.visibility_changed.connect(func() -> void:
		if sheet.visible == held["open"]:
			return
		held["open"] = sheet.visible
		if sheet.visible:
			held["was_paused"] = main._clock.paused
			main._clock.paused = true
		elif not bool(held["was_paused"]) and not main._decision_holds_clock():
			main._clock.paused = false
		main._hud.clock_cluster.refresh(main._clock, HoldReason.show(main)))
