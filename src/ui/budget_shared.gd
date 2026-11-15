extends RefCounted

## The Budget tab's seam to the Books page's ONE draft (finance_draft.gd) -- V5.3 Finances slice 2. The Budget
## keeps its levers (the sector tiles hang from them until the Sectors screen takes those) but no longer owns what
## they say: a lever moved here is a row of the shared draft, a row moved on the Books page moves its lever here,
## Commit tables the one draft's bill, and Revert drops it. With no draft wired (a test building the panel alone)
## every call is the Budget's own old behaviour. The Budget's slider math stays in budget_panel.gd; this is only
## the glue, in its own file because that one is at its size ceiling.

const FinanceBill = preload("res://src/sim/finance_bill.gd")
const Strings = preload("res://src/ui/strings.gd")

const CHANNEL := "spending_pct_gdp"


## Whether a line is a row of the finance bill before the Assembly: locked, as on the Books page, until the bill is
## withdrawn (a newer delta would REPLACE the tabled one when the draft is tabled as an amendment).
static func locked(panel, key: String) -> bool:
	return (panel._state.player().tabled_bill.get("finance", {}).get(CHANNEL, {}) as Dictionary).has(key)


## A lever the player moved here, into the shared draft; a locked line takes nothing (the next pull puts the lever back).
static func write(panel, key: String, value: float) -> void:
	if panel.shared != null and not locked(panel, key):
		panel.shared.set_value(CHANNEL, key, value)


## The bill Commit tables: the shared draft's, else the panel's own pending.
static func bill(panel) -> Dictionary:
	if panel.shared != null:
		return panel.shared.bill()
	return FinanceBill.from_pending(panel._state.player(), panel._pending)


## Revert (and a commit's clean-up): the shared draft is dropped with the levers.
static func revert(panel) -> void:
	if panel.shared != null:
		panel.shared.revert()


## The levers take what the shared draft says: a row moved on the Books page shows here, and a lever the draft does
## not hold is the player's no more. Never writes the draft.
static func pull(panel) -> void:
	if panel.shared == null or panel._sliders.is_empty() or panel._state == null or panel._state.player() == null:
		return
	for key in panel._lever_keys():
		var held := locked(panel, String(key))
		panel._sliders[key].editable = not held
		panel._sliders[key].tooltip_text = Strings.t("At vote: withdraw the bill to change it.") if held else ""
		var value: float = panel.shared.value(CHANNEL, String(key))
		if not is_equal_approx(value, panel._pending_value(String(key))):
			panel._pending[CHANNEL][key] = value
			panel._set_lever(String(key), value, false)
		if panel.shared.is_moved(CHANNEL, String(key)):
			panel._edited_keys[key] = true
		else:
			panel._edited_keys.erase(key)
