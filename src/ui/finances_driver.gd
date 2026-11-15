extends RefCounted

## The Finances page's wiring -- V5.3 screen 4, direction A. Static over main, as the other drivers are: it
## registers the page as the first tab of the Finances domain (domains.gd) and sends its "Open the bill"
## to the Bills tab. The window manager's own sweep rebinds it on a load, like every registered panel.

const FinancesPanel = preload("res://src/ui/finances_panel.gd")
const Strings = preload("res://src/ui/strings.gd")


static func register(main) -> void:
	var panel := FinancesPanel.new()
	main._windows.register("finances", Strings.t("Books"), panel, KEY_NONE, main.ICONS + "payments.svg")
	panel.setup(main._state, main._loader)
	panel.go_requested.connect(main._windows.open)
	# The one fiscal command the page sends (a bill tabled, added to or withdrawn): the shell's card and effect baseline.
	panel.committed.connect(func(before: Dictionary, tabling: Dictionary) -> void:
		main._fiscal_committed(Strings.t("Finance bill"), tabling, before))
