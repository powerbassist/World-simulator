"""V5.2a: the likeness sheet -- the four default leaders' busts beside the
photographs they were generated over, for the author to confirm the busts do
NOT resemble their sources (the 2026-10-19 call that lets them appear in the
affair and corruption content of V5.2c; docs/tiers/v5.md, V5.2 "c").

  python tools/portraits_likeness_sheet.py

Out: sources/portraits/likeness_sheet.png (gitignored -- the photographs are
real people and live only in sources/). One row per leader, left to right:
the source photograph, then the five moods of the bust, then the
attribution. A leader with no reference photograph (the bust came from the
text route alone) says so on its row. The leaders are read off the playable
nations' `leader.person`, never a list here. No real name is drawn: a row is
labelled with the register id only."""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
REF_DIR = REPO / "sources" / "portraits" / "reference"
SOURCES = REPO / "tools" / "portraits_photo_sources.json"
OUT = REPO / "sources" / "portraits" / "likeness_sheet.png"
EMOTIONS = ["neutral", "pleased", "stern", "worried", "weary"]
H = 520
GROUND = (74, 78, 86)


def _font(size):
    for name in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def default_leaders():
    leaders = []
    for path in sorted((REPO / "data" / "nations").glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        if d.get("playable") and isinstance(d.get("leader"), dict) and d["leader"].get("person"):
            leaders.append((path.stem, d["leader"]["person"]))
    return leaders


def fit(img: Image.Image) -> Image.Image:
    scale = H / img.height
    return img.resize((max(1, int(img.width * scale)), H), Image.LANCZOS)


def bust(pid: str, emotion: str):
    p = REPO / "assets" / "portraits" / emotion / (pid + ".webp")
    if not p.exists():
        return None
    rgba = fit(Image.open(p).convert("RGBA"))
    ground = Image.new("RGB", rgba.size, GROUND)
    ground.paste(rgba, mask=rgba.getchannel("A"))
    return ground


def main() -> int:
    sources = json.loads(SOURCES.read_text(encoding="utf-8")) if SOURCES.exists() else {}
    leaders = default_leaders()
    big, small = _font(22), _font(14)
    rows = []
    for nation, pid in leaders:
        ref = next((REF_DIR / (pid + e) for e in (".jpg", ".jpeg", ".png")
                    if (REF_DIR / (pid + e)).exists()), None)
        cells = [fit(Image.open(ref).convert("RGB")) if ref else None]
        cells += [bust(pid, e) for e in EMOTIONS]
        rows.append((nation, pid, ref, cells, sources.get(pid, {})))
    width = 20 + max(sum((c.width if c else 350) + 8 for c in cells) for *_x, cells, _s in rows)
    sheet = Image.new("RGB", (width, len(rows) * (H + 70) + 20), (24, 28, 40))
    draw = ImageDraw.Draw(sheet)
    y = 10
    for nation, pid, ref, cells, src in rows:
        draw.text((10, y), "%s  %s   |   LEFT: source photograph   RIGHT: the five moods of the bust"
                  % (nation, pid), fill=(235, 235, 200), font=big)
        x = 10
        for i, cell in enumerate(cells):
            if cell is None:
                draw.rectangle([x, y + 34, x + 340, y + 34 + H], outline=(120, 120, 120))
                draw.text((x + 14, y + 34 + H // 2), "no reference photograph:\ntext route only" if i == 0 else "missing",
                          fill=(240, 170, 90), font=big)
                x += 350
                continue
            sheet.paste(cell, (x, y + 34))
            x += cell.width + 8
        credit = ("%s, %s" % (src.get("artist", "?"), src.get("license", "?"))) if src else "no source recorded"
        draw.text((10, y + 34 + H + 4), "photo credit: " + credit[:160], fill=(180, 180, 170), font=small)
        y += H + 70
    sheet.save(OUT)
    print("likeness sheet: %d leaders (%s) -> %s" % (len(rows), ", ".join(p for _n, p in leaders), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
