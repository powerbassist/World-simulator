"""V3.7 portrait recipe, background half. Stdlib only (HTTP via comfy_client).

Renders the situational backdrop library the game composites BEHIND the alpha
cut-out busts (src/ui/portrait.gd): 14 scenes x 3 seeded variants = 42
backdrops, so the same office is not behind every minister. The variant a
person sees is picked at display time, stably, from their own id -- these
files are the pool, not the assignment.

Every scene prompt carries the same three constraints, and they are what make
the composite work: shallow depth of field / strong bokeh, no people, and
soft light from camera-left matching the portrait key -- a room lit from the
other side is a head pasted on a poster.

Backdrops are rendered 42 times, not 1065, so they can afford quality: the
non-Hyper Juggernaut at 25 steps through tools/portraits_background_workflow.json.
Out: sources/backgrounds/raw/<scene>_<n>.png, plus per-nation flag variants
<scene>_<NATION>_<n>.png for the flag-bearing scenes (--nation); the Godot
post-pass (tools/portraits.gd) turns them into assets/portrait_scenes/.

--dry-run: print every prompt, contact nothing. --only <scene> slices;
--nation <CODE> adds the flag variants.

Machine dependency, stated honestly: needs ComfyUI listening on
127.0.0.1:8188 (tools/comfy_client.py), with
Juggernaut_X_RunDiffusion.safetensors on disk -- the non-Hyper checkpoint,
which the machine already carries beside the Hyper one the portraits use.
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comfy_client as comfy  # noqa: E402

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
WORKFLOW = TOOLS / "portraits_background_workflow.json"
RAW_DIR = REPO / "sources" / "backgrounds" / "raw"
WIDE_DIR = REPO / "sources" / "backgrounds" / "wide"

## Node ids in the background template -- prompt in, seed in, image out.
TEXT_NODE, SEED_NODE, IMAGE_NODE = "2", "5", "7"
LATENT_NODE = "4"

## V5.2a: the audience scene is a window over the map (layout B), 16:9, not
## the portrait crop the busts sit in. --wide renders the scenes below at
## 1344x768 (SDXL's own 16:9 bucket, a multiple of 64, fits the 8 GB card);
## tools/portraits.gd resizes to 1280x720 and ships them under
## assets/portrait_scenes_wide/ -- a separate directory, because
## assets/portrait_scenes/ is the 432x632 library the bust display and its
## tests own. Only the rooms an audience, a call or a summit scene is held in.
WIDE_SIZE = (1344, 768)
WIDE_SCENES = ["office", "office_night", "cabinet_room", "corridor", "press_room",
               "tv_studio", "podium_flags", "summit_hall", "state_dinner",
               "parliament_chamber"]

VARIANTS = 3

## 14 scenes, the vocabulary portrait.gd's Scene enum mirrors. Described
## settings, no nations -- EXCEPT through --nation (below): a shared library
## cannot carry one country's flag, so the generic scenes are flag-free and
## the flag-bearing rooms are per-nation variants the display picks first
## (assets/portrait_scenes/<scene>_<NATION>_<n>.webp).
SCENES = {
    "office": "ministerial private office, dark wood desk, bookshelves, heavy curtains",
    "office_night": "ministerial office at night, warm desk lamp, city lights blurred through the window behind",
    "cabinet_room": "cabinet room, long polished table, leather chairs, wood panelling",
    "parliament_chamber": "parliamentary debating chamber, curved rows of dark wood benches, empty",
    "press_room": "press room, lectern with microphones, neutral backdrop, soft TV lights",
    "tv_studio": "television studio set, soft blue lighting, cameras out of focus at the edges",
    "corridor": "ministerial corridor, marble floor, wall sconces, tall doors",
    "podium_flags": "speech podium, ceremonial backdrop, soft TV lights",
    "summit_hall": "international summit hall, large round table, a row of many different national flags, delegates' nameplates",
    "state_dinner": "state banquet hall, candelabra, crystal glassware, warm candlelight",
    "street_city": "European city street, blurred traffic and stone facades",
    "plaza_crowd": "public square, distant blurred crowd silhouettes, barriers in the foreground",
    "garden_park": "formal garden, gravel path, trimmed hedges, soft daylight",
    "airport_tarmac": "airport tarmac at dusk, airliner stairs, red carpet",
}

## The scenes a nation's own dressing belongs in, and the only ones --nation
## accepts. office: flag stand AND the capital's skyline through the window;
## office_night: the capital's night view (no flag -- night offices read the
## city, not the colours); podium_flags: the flag row. summit_hall stays out:
## a bilateral summit carries TWO nations' flags and one backdrop cannot know
## the pair.
NATION_SCENES = ["office", "office_night", "podium_flags"]

## The flag as the prompt says it -- the game's nations are real countries
## (docs/fictionalization.md fictionalizes people and parties, not flags;
## the card already draws real tricolours). One line each, 29 nations.
NATION_FLAG = {
    "AUT": "red-white-red Austrian flags",
    "BEL": "black-yellow-red Belgian flags",
    "BGR": "white-green-red Bulgarian flags",
    "CHE": "Swiss flags, red with a white cross",
    "CYP": "Cypriot flags, white with a copper island and olive branches",
    "CZE": "Czech flags, white and red with a blue triangle",
    "DEU": "black-red-gold German flags",
    "DNK": "Dannebrog, Danish flags red with a white nordic cross",
    "ESP": "red-yellow-red Spanish flags",
    "EST": "blue-black-white Estonian flags",
    "FIN": "Finnish flags, white with a blue nordic cross",
    "FRA": "French tricolour flags, blue white and red",
    "GBR": "Union Jack flags",
    "GRC": "Greek flags, blue and white stripes with a cross",
    "HRV": "Croatian flags, red-white-blue with a checkerboard crest",
    "HUN": "red-white-green Hungarian flags",
    "IRL": "green-white-orange Irish tricolours",
    "ITA": "green-white-red Italian tricolours",
    "LTU": "yellow-green-red Lithuanian flags",
    "LUX": "red-white-lightblue Luxembourgish flags",
    "LVA": "carmine-white-carmine Latvian flags",
    "MLT": "Maltese flags, white and red with a cross",
    "NLD": "red-white-blue Dutch flags",
    "POL": "Polish flags, white over red",
    "PRT": "green and red Portuguese flags",
    "ROU": "blue-yellow-red Romanian tricolours",
    "SVK": "white-blue-red Slovak flags with a shield",
    "SVN": "white-blue-red Slovenian flags with a crest",
    "SWE": "Swedish flags, blue with a yellow nordic cross",
}

## The view from the window, as the prompt says it -- the capital, named so
## the model reaches for its real skyline. Places are real in this game
## (docs/fictionalization.md fictionalizes people and parties, not geography);
## the register's map is real Europe and these are its skylines.
NATION_VIEW = {
    "AUT": "the Vienna skyline with St. Stephen's Cathedral",
    "BEL": "the Brussels skyline with the Atomium in the distance",
    "BGR": "the Sofia skyline with the Nevski Cathedral",
    "CHE": "the Bern old town with the Alps beyond",
    "CYP": "the Nicosia old city under bright sky",
    "CZE": "the Prague skyline with the castle and Charles Bridge",
    "DEU": "the Berlin skyline with the Brandenburg Gate",
    "DNK": "the Copenhagen waterfront with its coloured townhouses",
    "ESP": "the Madrid skyline with the Royal Palace",
    "EST": "the Tallinn old town walls and spires",
    "FIN": "the Helsinki waterfront with its cathedral",
    "FRA": "the Paris skyline with the Eiffel Tower",
    "GBR": "the London skyline with Big Ben and the Thames",
    "GRC": "the Athens skyline with the Acropolis",
    "HRV": "the Zagreb skyline with its cathedral twin spires",
    "HUN": "the Budapest skyline with the Parliament dome",
    "IRL": "the Dublin docks and their red lifting cranes",
    "ITA": "the Rome skyline with St. Peter's dome",
    "LTU": "the Vilnius skyline with the Gediminas Tower",
    "LUX": "the Luxembourg old town with the Adolphe Bridge",
    "LVA": "the Riga old town with its church spires",
    "MLT": "Valletta's harbour fortifications in warm stone",
    "NLD": "the Hague skyline with the Binnenhof towers",
    "POL": "the Warsaw skyline with the Palace of Culture",
    "PRT": "the Lisbon hills with the yellow tram and the river",
    "ROU": "the Bucharest skyline with the grand palace",
    "SVK": "the Bratislava castle above the Danube",
    "SVN": "the Ljubljana skyline with its castle hill",
    "SWE": "the Stockholm waterfront with its old town",
}

## The three composite constraints, verbatim on every prompt. "no discernible
## faces" (not "no people") is deliberate: a blurred square IS people at a
## rally -- what the composite cannot survive is a competing sharp face.
CONSTRAINTS = ("shallow depth of field, strong bokeh, no people, no discernible faces, "
               "soft light from camera-left, photorealistic, 35mm lens")


def prompt_for(scene: str, n: int, nation: str = "", wide: bool = False):
    """The prompt for one backdrop. With `nation` set (nation scenes only),
    the file becomes <scene>_<NATION>_<n> and the room carries what the
    generic library cannot: the flag the person actually serves and the view
    from the actual capital's window."""
    key = scene + (":" + nation if nation else "") + ":" + str(n)
    # The wide set is its own library: its own seeds, so a 16:9 room is not a
    # re-crop of the portrait one. A reroll (salt) moves only that file.
    seed_key = ("wide:" if wide else "") + key
    stem = scene + ("_" + nation if nation else "") + "_" + str(n)
    salt = int(comfy.load_salts().get(("wide:" if wide else "scene:") + stem, 0))
    seed = comfy.djb2(seed_key + ":r%d" % salt if salt > 0 else seed_key)
    dressing = SCENES[scene]
    if nation:
        dressing = _nation_dressing(scene, nation)
    text = "%s, %s" % (dressing, CONSTRAINTS)
    return seed, text


def _nation_dressing(scene: str, nation: str) -> str:
    flag = NATION_FLAG[nation]
    view = NATION_VIEW[nation]
    if scene == "office":
        return ("ministerial private office, dark wood desk, bookshelves, %s on a flag stand, "
                "tall window behind the desk with %s visible beyond" % (flag, view))
    if scene == "office_night":
        return ("ministerial office at night, warm desk lamp, %s blurred through the window behind"
                % view)
    if scene == "podium_flags":
        return "speech podium, a row of %s behind it, soft TV lights" % flag
    raise RuntimeError("scene '%s' carries no nation variant" % scene)


def generate(scene: str, n: int, seed: int, text: str, wide: bool = False) -> bytes:
    workflow = json.loads(comfy._confined(WORKFLOW, TOOLS).read_text(encoding="utf-8"))
    if wide:
        workflow[LATENT_NODE]["inputs"]["width"], workflow[LATENT_NODE]["inputs"]["height"] = WIDE_SIZE
    workflow[SEED_NODE]["inputs"]["seed"] = seed
    workflow[TEXT_NODE]["inputs"]["text"] = text
    prompt_id = comfy.queue(workflow)
    out = comfy.outputs(prompt_id, timeout_s=900)
    if not out.get(IMAGE_NODE):
        raise RuntimeError("no output at node %s for %s_%d" % (IMAGE_NODE, scene, n))
    return comfy.fetch(out[IMAGE_NODE][0])


def _args() -> tuple:
    """--only <scene> (repeatable) slices the library; --nation <CODE>
    (repeatable) renders the flag-bearing per-nation variants of FLAG_SCENES."""
    only, nations = set(), set()
    args = sys.argv
    for i, a in enumerate(args):
        if a == "--only" and i + 1 < len(args):
            if args[i + 1] not in SCENES:
                raise RuntimeError("unknown scene '%s' -- %s" % (args[i + 1], sorted(SCENES)))
            only.add(args[i + 1])
        elif a == "--nation" and i + 1 < len(args):
            code = args[i + 1].upper()
            if code not in NATION_FLAG or code not in NATION_VIEW:
                raise RuntimeError("unknown nation '%s' -- no flag or view description" % code)
            nations.add(code)
    return only, nations


def reroll(stems, wide: bool) -> int:
    """--reroll <scene[_NATION]_n> (repeatable), with --wide for the 16:9
    library: bump that file's salt and delete its raw and shipped WebP, so the
    next pass draws a new backdrop (the streaked ones the author rejects)."""
    prefix = "wide:" if wide else "scene:"
    raw_dir = WIDE_DIR if wide else RAW_DIR
    out_dir = REPO / "assets" / ("portrait_scenes_wide" if wide else "portrait_scenes")
    for stem in stems:
        if not re.fullmatch(r"[a-z_]+(_[A-Z]{3})?_[0-9]", stem):
            raise RuntimeError("'%s' is not a <scene>[_NATION]_<n> backdrop name" % stem)
        salt = comfy.bump_salt(prefix + stem)
        gone = 0
        for path in (raw_dir / (stem + ".png"), out_dir / (stem + ".webp")):
            if path.exists():
                comfy._confined(path, REPO).unlink()
                gone += 1
        print("reroll %s%s: salt %d, %d files cleared" % (prefix, stem, salt, gone))
    return 0


def main() -> int:
    only, nations = _args()
    wide = "--wide" in sys.argv
    if "--reroll" in sys.argv:
        return reroll([a for i, a in enumerate(sys.argv[1:], 1) if sys.argv[i - 1] == "--reroll"], wide)
    if "--dry-run" in sys.argv:
        for scene, nation in _jobs(only, nations, wide):
            for n in range(VARIANTS):
                seed, text = prompt_for(scene, n, nation, wide)
                label = "%s_%s" % (scene, nation) if nation else scene
                print("%s_%d (seed %d)\n  %s" % (label, n, seed, text))
        print("dry-run, nothing contacted")
        return 0

    raw_dir = WIDE_DIR if wide else RAW_DIR
    raw_dir.mkdir(parents=True, exist_ok=True)
    todo = []
    for scene, nation in _jobs(only, nations, wide):
        for n in range(VARIANTS):
            label = "%s_%s" % (scene, nation) if nation else scene
            if not (raw_dir / ("%s_%d.png" % (label, n))).exists():
                todo.append((scene, nation, n, label))
    print("%d backdrops to generate" % len(todo))
    for i, (scene, nation, n, label) in enumerate(todo):
        seed, text = prompt_for(scene, n, nation, wide)
        out = comfy._confined(raw_dir / ("%s_%d.png" % (label, n)), raw_dir)
        out.write_bytes(generate(scene, n, seed, text, wide))
        print("  [%d/%d] %s_%d (seed %d)" % (i + 1, len(todo), label, n, seed))
    print("done: backdrops under sources/backgrounds/%s" % ("wide" if wide else "raw"))
    return 0


def _jobs(only, nations, wide: bool = False):
    """The (scene, nation) work list: the generic library (nation="") plus one
    nation-dressed entry per --nation for each scene in NATION_SCENES. --wide
    keeps to WIDE_SCENES."""
    jobs = [(s, "") for s in SCENES if (not only or s in only) and (not wide or s in WIDE_SCENES)]
    for nation in sorted(nations):
        for scene in NATION_SCENES:
            if not only or scene in only:
                jobs.append((scene, nation))
    return jobs


if __name__ == "__main__":
    sys.exit(main())
