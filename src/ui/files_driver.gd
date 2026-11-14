extends RefCounted

## The docked file page's wiring -- V5.3 screen 3. Static over main, as the other drivers
## are: it registers the page as a workspace tab (no domain row, like the audience: it is
## reached by a click on a card, never from the sidebar), and routes an inbox card's click.
##
## An inbox card that asks something of the player (an event, a request, a treaty, a vote, a
## bill) opens its file; any other card keeps the Dispatches window it always opened.

const Strings = preload("res://src/ui/strings.gd")
const DecisionView = preload("res://src/ui/decision_view.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")

const WINDOW := "file"

static var _views := {}


static func register(main) -> void:
	var view := DecisionView.new()
	main._windows.register(WINDOW, Strings.t("Decision"), view, KEY_NONE, main.ICONS + "mail.svg")
	view.attach(main)
	_views[main.get_instance_id()] = view


static func view_of(main):
	return _views.get(main.get_instance_id())


## A card was clicked: its file when it is one, else the Dispatches window.
static func activated(main, card_id: String) -> void:
	var view = view_of(main)
	if view != null and not InboxFiles.of(main._hud.inbox, card_id).is_empty():
		view.show_file(card_id)
		main._windows.open(WINDOW)
		return
	main._windows.open("events")
