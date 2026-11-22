extends RefCounted

## What the bill's rail (finance_foot.gd) reads off the Finances page shown beside it -- moved out of the rail at G3 S4
## to keep that file under the size ratchet. Two reads, each over the open pages that do not hold the rail: whether
## the page shows a filled button of its own (one filled button a screen, the parent's ruling of 2026-11-22), and
## where the page's programme would land in the bill (Register's landing(), a dashed place in the rail).

const UiTheme = preload("res://src/ui/ui_theme.gd")


static func _pages(rail: Control) -> Array:
	var manager = rail.get_tree().get_first_node_in_group("window_manager") if rail.is_inside_tree() else null
	if manager == null:
		return []
	var out: Array = []
	for id in manager.open_ids():
		var page: Control = manager.content(id)
		if page != null and not page.is_ancestor_of(rail):
			out.append(page)
	return out


## Whether a page beside the rail shows an enabled PRIMARY button: a disabled one is not the next step (pass 2 T11
## on #443: Register's, with nothing placed).
static func leads(rail: Control) -> bool:
	for page in _pages(rail):
		for button in page.find_children("*", "Button", true, false):  # i18n: ok a class name
			if (button as Button).theme_type_variation == UiTheme.PRIMARY and (button as Button).is_visible_in_tree() and not (button as Button).disabled:
				return true
	return false


## The place the page's programme would take in the bill, {} when the page offers none.
static func landing(rail: Control) -> Dictionary:
	for page in _pages(rail):
		if page.has_method("landing") and page.is_visible_in_tree():
			return page.landing()
	return {}
