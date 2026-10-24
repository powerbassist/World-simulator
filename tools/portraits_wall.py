"""V5.2a: the contact-sheet wall the author rejects from. Pages of 30 faces, id
under each, readable at full size (the V4.3 sheet put 1 595 faces on one
2160 px image and nobody could name a face on it).

  python tools/portraits_wall.py                 # every neutral face, by nation
  python tools/portraits_wall.py --kind executive  # one register kind
  python tools/portraits_wall.py --scenes        # the backdrops, 12 a page

Out (gitignored, under sources/portraits/wall/): page_NNN.png and wall.html,
a click-to-reject page whose "copy ids" button is the author's reply. The
screen's nominations (tools/portraits_screen.py) come first, on their own
pages, tagged with why.

Cells show the shipped WebP composited over its own mid-grey, as the game
draws it before a backdrop is chosen -- a failed matte shows as a failed matte."""

import html
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
PEOPLE = REPO / "data" / "people"
PORTRAITS = REPO / "assets" / "portraits" / "neutral"
SCENES = REPO / "assets" / "portrait_scenes"
SCREEN = REPO / "sources" / "portraits" / "screen.json"
OUT = REPO / "sources" / "portraits" / "wall"

COLS, ROWS = 6, 5
CELL_W, CELL_H, LABEL_H, HEAD_H = 216, 296, 34, 44
GROUND = (74, 78, 86)


def _font(size):
    for name in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _kinds():
    kinds = {}
    for path in sorted(PEOPLE.glob("*.json")):
        for person in json.loads(path.read_text(encoding="utf-8"))["people"]:
            kinds[person["id"]] = person.get("kind", "")
    return kinds


def _cell(path: Path, w: int, h: int) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    img.thumbnail((w, h), Image.LANCZOS)
    base = Image.new("RGB", img.size, GROUND)
    base.paste(img, mask=img.getchannel("A"))
    return base


def _pages(items, title, cols, rows, cell_w, cell_h):
    """items: [(id, path, note)] -> PNG pages, returns the written names."""
    per = cols * rows
    font, small, tiny = _font(18), _font(14), _font(11)
    names = []
    for start in range(0, len(items), per):
        chunk = items[start:start + per]
        page = Image.new("RGB", (cols * cell_w, HEAD_H + rows * (cell_h + LABEL_H)), (24, 28, 40))
        draw = ImageDraw.Draw(page)
        n = start // per + 1
        draw.text((10, 10), "%s  -  page %d of %d" % (title, n, (len(items) + per - 1) // per),
                  fill=(235, 235, 220), font=font)
        for i, (pid, path, note) in enumerate(chunk):
            x, y = (i % cols) * cell_w, HEAD_H + (i // cols) * (cell_h + LABEL_H)
            cell = _cell(path, cell_w - 6, cell_h - 4)
            page.paste(cell, (x + 3 + (cell_w - 6 - cell.width) // 2, y + 2))
            draw.text((x + 6, y + cell_h + 1), pid, fill=(235, 235, 200),
                      font=small if len(pid) <= 24 else tiny)
            if note:
                draw.text((x + 6, y + cell_h + 17), note, fill=(240, 170, 90), font=small)
        name = "%s_%03d.png" % (title.split()[0].lower().strip(":"), n)
        page.save(OUT / name)
        names.append(name)
    return names


def _page_html(title, cell_w, img_w, cells) -> str:
    """The click-to-reject page: a click toggles a red REJECT mark, the sticky
    button copies the marked ids -- the author's whole reply."""
    return (
        "<!doctype html><meta charset=utf-8><title>%s</title><style>"
        "body{background:#181c28;color:#eee;font:13px sans-serif;margin:12px}"
        ".g{display:grid;grid-template-columns:repeat(auto-fill,%dpx);gap:6px}"
        ".c{background:#4a4e56;cursor:pointer;border:3px solid transparent;position:relative}"
        ".c img{width:%dpx;display:block}.c span{display:block;background:#181c28;padding:2px}"
        ".c.x{border-color:#e33}.c.x::after{content:'REJECT';position:absolute;top:4px;left:4px;"
        "background:#e33;padding:1px 4px}"
        "button{position:sticky;top:0;font-size:15px;padding:6px 12px}</style>"
        "<button onclick=\"navigator.clipboard.writeText([...document.querySelectorAll('.x')]"
        ".map(e=>e.dataset.id).join(' '))\">copy rejected ids</button> "
        "<span id=n></span><div class=g>%s</div><script>document.querySelectorAll('.c').forEach("
        "c=>c.onclick=()=>{c.classList.toggle('x');n.textContent=document.querySelectorAll('.x').length"
        "+' rejected'})</script>" % (title, cell_w, img_w, cells))


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:]
    if "--scenes" in args:
        items = [(p.stem, p, "") for p in sorted(SCENES.glob("*.webp"))]
        if SCREEN.exists():
            streak = json.loads(SCREEN.read_text(encoding="utf-8"))["scene_streak"]
            items = sorted(items, key=lambda t: -streak.get(t[0], -9))
            items = [(i, p, "streak %.2f" % streak.get(i, 0)) for i, p, _ in items]
        print(len(_pages(items, "scenes", 4, 3, 360, 300)), "scene pages ->", OUT)
        cells = "".join(
            '<div class="c" data-id="%s"><img loading="lazy" src="../../../assets/portrait_scenes/%s.webp">'
            "<span>%s %s</span></div>" % (html.escape(i), html.escape(i), html.escape(i), html.escape(n))
            for i, _p, n in items)
        (OUT / "scene_wall.html").write_text(_page_html("backdrop wall", 230, 220, cells), encoding="utf-8")
        return 0
    kinds = _kinds()
    faces = {p.stem: p for p in sorted(PORTRAITS.glob("*.webp"))}
    if "--kind" in args:
        want = args[args.index("--kind") + 1]
        faces = {k: v for k, v in faces.items() if kinds.get(k) == want}
    suspects = []
    if SCREEN.exists():
        flags = json.loads(SCREEN.read_text(encoding="utf-8"))["face_flags"]
        suspects = [(pid, faces[pid], "; ".join(why)[:30]) for pid, why in flags.items() if pid in faces]
    written = []
    if suspects:
        written += _pages(suspects, "suspects", COLS, ROWS, CELL_W, CELL_H)
    rest = [(pid, p, "") for pid, p in sorted(faces.items())]
    written += _pages(rest, "faces", COLS, ROWS, CELL_W, CELL_H)
    rows = "".join(
        '<div class="c" data-id="%s"><img loading="lazy" src="../../../assets/portraits/neutral/%s.webp">'
        "<span>%s</span></div>" % (html.escape(pid), html.escape(pid), html.escape(pid))
        for pid, _p in sorted(faces.items()))
    (OUT / "wall.html").write_text(_page_html("portrait wall", 150, 144, rows), encoding="utf-8")
    print("%d faces -> %d pages + wall.html in %s" % (len(faces), len(written), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
