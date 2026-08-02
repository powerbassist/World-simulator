extends RefCounted

## Loads an at-icons SVG and rasterises it, tinted, at a given pixel size -- U5a.
##
## Deliberately **not** load("res://addons/.../x.svg"). That path returns the
## editor's imported CompressedTexture2D, which lives in .godot/ -- gitignored,
## and absent on a fresh clone until the editor has opened the project once.
## tools/run_tests.sh runs headless straight from the repo, so an icon loaded
## that way would be a hard failure in exactly the situation the .gitignore's
## at-icons exception exists to prevent. Reading the file as text and calling
## Image.load_svg_from_string() sidesteps the import system entirely.
##
## Rasterising at the size it will be drawn, rather than scaling a 16px texture
## up, is the other reason: these are 16x16 source files and the bottom bar
## wants them at 22.
##
## The at-icons set ships one colour per editor category (this game uses the
## `control` variant, which is green). Recolouring is a string replace on the
## SVG's own fill before it is ever rasterised -- cheaper and sharper than
## modulating a green texture toward brass.

const SOURCE_FILL := "#8eef97"


static func load_icon(path: String, tint: Color, px: int) -> ImageTexture:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var svg := file.get_as_text()
	file.close()

	svg = svg.replace(SOURCE_FILL, "#" + tint.to_html(false))

	var image := Image.new()
	# The source viewBox is 16 units wide; scale is a multiplier, not a size.
	if image.load_svg_from_string(svg, float(px) / 16.0) != OK:
		return null
	return ImageTexture.create_from_image(image)
