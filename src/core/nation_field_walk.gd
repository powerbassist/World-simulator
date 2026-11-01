extends RefCounted

## NationState's three walks over its ONE FIELD TABLE (src/core/nation_fields.gd):
## duplicate_state(), to_dict() and from_dict() each run one loop over F.FIELDS.
## Moved out of nation_fields.gd at V5.3 a, unchanged, because the table had
## reached the size ratchet's 300 code lines with the walks in it; the table stays
## where AGENTS.md and the tests name it. Dependencies run one way: nation_state.gd
## -> this file -> the table and the readers.

const F = preload("res://src/core/nation_fields.gd")
const Readers = preload("res://src/core/nation_field_readers.gd")


## `dst` is a fresh NationState; every copied container is its own.
static func copy_into(src, dst) -> void:
	for row in F.FIELDS:
		match row[F.COL_COPY]:
			F.SCALAR:
				dst.set(row[F.COL_NAME], src.get(row[F.COL_NAME]))
			F.DEEP:
				dst.set(row[F.COL_NAME], src.get(row[F.COL_NAME]).duplicate(true))


## The values ARE the live fields, as they always were: the save path stringifies
## at once, and every reader below rebuilds rather than assigns, so the sharing
## never reaches a loaded state.
static func to_dict(src) -> Dictionary:
	var out := {}
	for row in F.FIELDS:
		if row[F.COL_READ] != F.NOT_SAVED:
			out[row[F.COL_NAME]] = src.get(row[F.COL_NAME])
	return out


## `dst` is a fresh NationState. An absent key leaves new()'s declared default.
static func read_into(dst, d: Dictionary) -> void:
	for row in F.FIELDS:
		var name: String = row[F.COL_NAME]
		if row[F.COL_READ] == F.NOT_SAVED or not d.has(name):
			continue
		dst.set(name, read_value(row[F.COL_READ], d[name], row[F.COL_DEFAULT]))


static func read_value(read: int, raw, declared):
	match read:
		F.VALUE:
			match typeof(declared):
				TYPE_INT: return int(raw)
				TYPE_FLOAT: return float(raw)
				TYPE_BOOL: return bool(raw)
				_: return String(raw)
		F.COPIED: return raw.duplicate(true)
		F.FLOAT_MAP: return Readers.float_map(raw)
		F.INT_MAP: return Readers.int_map(raw)
		F.STRING_MAP: return Readers.string_map(raw)
		F.SORTED_STRINGS: return Readers.sorted_strings(raw)
		F.ROWS: return Readers.rows(raw)
		F.FLOAT_MAP_TYPED: return Readers.float_map_typed(raw)
		F.STRING_MAP_TYPED: return Readers.string_map_typed(raw)
		F.BOOL_MAP_TYPED: return Readers.bool_map_typed(raw)
		F.PLEDGES: return Readers.pledges(raw)
		F.PROGRAMME: return Readers.programme(raw)
		F.COMMODITY_STATE: return Readers.commodity_state(raw)
		F.LAW_LEDGER: return Readers.law_ledger(raw)
		F.DRAFT_BILLS: return Readers.draft_bills(raw)
		F.CUSTOM_TAXES: return Readers.custom_taxes(raw)
		F.POLL_PURCHASES: return Readers.poll_purchases(raw)
		F.ASSEMBLY_BILLS: return Readers.assembly_bills(raw)
		F.HELD_BILLS: return Readers.held_bills(raw)
	push_error("nation_field_walk: unknown read kind %d" % read)
	return declared
