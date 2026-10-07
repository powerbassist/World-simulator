extends SceneTree

## V4.4 event art, Godot half -- the V3.7 post-pass (tools/portraits.gd's
## shape) re-aimed at the event plate library. Run headless from the repo root:
##
##   godot --headless --script res://tools/event_art.gd
##
## Reads the raw generations (tools/event_art_generate.py, against a running
## ComfyUI), centre-crops each to 16:9 -- the shape every surface that shows a
## plate asks for -- and writes the committed assets:
##
##   assets/event_art/<category>_<band>_<n>.webp   432x243
##
## each with a committed .import carrying importer="keep" -- the Blue Marble's
## rule, so the editor never spends an import pass on files nothing load()s.
## WebP q90 LOSSY: save_webp's second argument is LOSSY (the V3.7 lesson --
## false encodes lossless and ignores quality, pinned there by size
## comparison).
##
## The raw frames arrive 1216x832 (the workflow's landscape latent). The crop
## takes the central 1216x684 -- 16:9's aspect -- discarding 74px top and
## bottom, then resizes to 432x243, the portrait assets' own 432px width
## discipline. A source that is not the workflow's frame still gets the same
## centre-crop, so a re-render at another latent size needs no edit here.
##
## A raw whose name does not parse as <category>_<band>_<n> over the plate
## table is REFUSED, not ignored -- stale art nobody references is the orphan
## precedent pointed at sources/, the same refusal tools/portraits.gd makes
## for a portrait belonging to no person.
##
## --help prints the plate registry and exits; any other flag is an error.

const RAW_DIR := "res://sources/event_art/raw"
const OUT_DIR := "res://assets/event_art"

## The plate table, mirrored for name-checking -- tools/event_art_generate.py
## owns the prompts, src/ui/event_art.gd owns the display read, and
## tests/test_event_art.gd pins the three lists equal. A category added to the
## generator without this table dies here at the post-pass, loudly.
const CATEGORIES := ["scandal", "fiscal", "unrest", "personal", "european",
                     "foreign", "industrial", "commodity", "disaster"]
const BANDS := ["minor", "major", "critical"]
const VARIANTS := 2

const OUT_W := 432
const OUT_H := 243  # 16:9, the header shape every caller asks for


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--help":
			_print_registry()
			quit(0)
			return
		push_error("event_art: unknown flag '%s' -- see the header comment; --help prints the registry" % args[i])
		quit(1)
		return

	var written := 0
	var bytes_total := 0
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if not DirAccess.dir_exists_absolute(RAW_DIR):
		print("event_art: no raws under %s -- run tools/event_art_generate.py first" % RAW_DIR)
		quit(0)
		return
	for f in DirAccess.get_files_at(RAW_DIR):
		if not f.ends_with(".png"):
			continue
		if not _is_known_plate(f.get_basename()):
			printerr("FAIL: raw '%s' matches no plate in the registry -- stale art nobody references" % f)
			quit(1)
			return
		var img := _load_raw(RAW_DIR.path_join(f))
		if img == null:
			quit(1)
			return
		var plate := _centre_crop_16x9(img)
		plate.resize(OUT_W, OUT_H, Image.INTERPOLATE_LANCZOS)
		var out_path := OUT_DIR.path_join(f.get_basename() + ".webp")
		# lossy=TRUE is the lossy encoder; false encodes lossless and ignores
		# quality -- the V3.7 pin, kept verbatim so it cannot be re-inverted.
		if plate.save_webp(out_path, true, 0.90) != OK:
			printerr("FAIL: could not write %s" % out_path)
			quit(1)
			return
		_write_keep_import(out_path)
		written += 1
		bytes_total += FileAccess.get_file_as_bytes(out_path).size()
	print("event_art: %d plates (%.1f MB total) under %s" % [written, bytes_total / 1048576.0, OUT_DIR])
	quit(0)


func _is_known_plate(plate_id: String) -> bool:
	var parts := plate_id.split("_")
	if parts.size() != 3:
		return false
	if not CATEGORIES.has(parts[0]) or not BANDS.has(parts[1]):
		return false
	return parts[2].is_valid_int() and int(parts[2]) < VARIANTS


func _load_raw(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		printerr("FAIL: could not read %s" % path)
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		printerr("FAIL: %s is not a decodable PNG" % path)
		return null
	return img


## The central 16:9 rectangle of whatever frame arrives: the shorter of the
## width a 16:9 of this height allows and the height a 16:9 of this width
## allows, centred both ways.
func _centre_crop_16x9(img: Image) -> Image:
	var aspect := float(OUT_W) / float(OUT_H)
	var w := img.get_width()
	var h := img.get_height()
	var cw := mini(w, int(h * aspect))
	var ch := mini(h, int(w / aspect))
	var cx := (w - cw) / 2
	var cy := (h - ch) / 2
	return img.get_region(Rect2i(cx, cy, cw, ch))


func _write_keep_import(asset_path: String) -> void:
	var import_path := asset_path + ".import"
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	file.store_string("[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nsource_file=\"%s\"\n" % asset_path)
	file.close()


func _print_registry() -> void:
	print("event_art -- the plate registry (category x band x %d variants)" % VARIANTS)
	print("  assets: %s/<category>_<band>_<n>.webp (%dx%d, 16:9)" % [OUT_DIR, OUT_W, OUT_H])
	print("  raws:   %s/<category>_<band>_<n>.png" % RAW_DIR)
	for category in CATEGORIES:
		for band in BANDS:
			for n in VARIANTS:
				print("  %s_%s_%d" % [category, band, n])
	print("  usage: godot --headless --script res://tools/event_art.gd  (post-pass)")
	print("         python tools/event_art_generate.py [--dry-run] [--only <category>]  (render)")
