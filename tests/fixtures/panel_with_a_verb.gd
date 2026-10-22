extends VBoxContainer

## The smallest thing that satisfies V2.1a's fold contract: a Control that names
## the one control the player came to press. tests/test_workspace.gd uses it
## to check the frame's machinery without building the whole game.
##
## tab_page.gd asks through has_method(), so this is the entire interface --
## there is no base class and no registry of which panels have verbs.

var primary: Control


func primary_action() -> Control:
	return primary
