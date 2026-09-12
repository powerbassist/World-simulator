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
Out: sources/backgrounds/raw/<scene>_<n>.png; the Godot post-pass
(tools/portraits.gd) turns them into assets/portrait_scenes/.

--dry-run: print all 42 prompts, contact nothing.

Machine dependency, stated honestly: needs ComfyUI listening on
127.0.0.1:8188 (tools/comfy_client.py), with
Juggernaut_X_RunDiffusion.safetensors on disk -- the non-Hyper checkpoint,
which the machine already carries beside the Hyper one the portraits use.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comfy_client as comfy  # noqa: E402

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
WORKFLOW = TOOLS / "portraits_background_workflow.json"
RAW_DIR = REPO / "sources" / "backgrounds" / "raw"

## Node ids in the background template -- prompt in, seed in, image out.
TEXT_NODE, SEED_NODE, IMAGE_NODE = "2", "5", "7"

VARIANTS = 3

## 14 scenes, the vocabulary portrait.gd's Scene enum mirrors. Described
## settings, no nations: one library serves every country's offices.
SCENES = {
    "office": "ministerial private office, dark wood desk, bookshelves, flag stand at one side",
    "office_night": "ministerial office at night, warm desk lamp, city lights blurred through the window behind",
    "cabinet_room": "cabinet room, long polished table, leather chairs, wood panelling",
    "parliament_chamber": "parliamentary debating chamber, curved rows of dark wood benches, empty",
    "press_room": "press room, lectern with microphones, neutral backdrop, soft TV lights",
    "tv_studio": "television studio set, soft blue lighting, cameras out of focus at the edges",
    "corridor": "ministerial corridor, marble floor, wall sconces, tall doors",
    "podium_flags": "speech podium with a row of national flags behind it",
    "summit_hall": "international summit hall, large round table, national flags, delegates' nameplates",
    "state_dinner": "state banquet hall, candelabra, crystal glassware, warm candlelight",
    "street_city": "European city street, blurred traffic and stone facades",
    "plaza_crowd": "public square, distant blurred crowd silhouettes, barriers in the foreground",
    "garden_park": "formal garden, gravel path, trimmed hedges, soft daylight",
    "airport_tarmac": "airport tarmac at dusk, airliner stairs, red carpet",
}

## The three composite constraints, verbatim on every prompt. "no discernible
## faces" (not "no people") is deliberate: a blurred square IS people at a
## rally -- what the composite cannot survive is a competing sharp face.
CONSTRAINTS = ("shallow depth of field, strong bokeh, no people, no discernible faces, "
               "soft light from camera-left, photorealistic, 35mm lens")


def prompt_for(scene: str, n: int):
    seed = comfy.djb2(scene + ":" + str(n))
    text = "%s, %s" % (SCENES[scene], CONSTRAINTS)
    return seed, text


def generate(scene: str, n: int, seed: int, text: str) -> bytes:
    workflow = json.loads(comfy._confined(WORKFLOW, TOOLS).read_text(encoding="utf-8"))
    workflow[SEED_NODE]["inputs"]["seed"] = seed
    workflow[TEXT_NODE]["inputs"]["text"] = text
    prompt_id = comfy.queue(workflow)
    out = comfy.outputs(prompt_id, timeout_s=900)
    if not out.get(IMAGE_NODE):
        raise RuntimeError("no output at node %s for %s_%d" % (IMAGE_NODE, scene, n))
    return comfy.fetch(out[IMAGE_NODE][0])


def main() -> int:
    if "--dry-run" in sys.argv:
        for scene in SCENES:
            for n in range(VARIANTS):
                seed, text = prompt_for(scene, n)
                print("%s_%d (seed %d)\n  %s" % (scene, n, seed, text))
        print("dry-run: %d backdrops, nothing contacted" % (len(SCENES) * VARIANTS))
        return 0

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    todo = [(scene, n) for scene in SCENES for n in range(VARIANTS)
            if not (RAW_DIR / ("%s_%d.png" % (scene, n))).exists()]
    print("%d backdrops exist, %d to generate"
          % (len(SCENES) * VARIANTS - len(todo), len(todo)))
    for i, (scene, n) in enumerate(todo):
        seed, text = prompt_for(scene, n)
        out = comfy._confined(RAW_DIR / ("%s_%d.png" % (scene, n)), RAW_DIR)
        out.write_bytes(generate(scene, n, seed, text))
        print("  [%d/%d] %s_%d (seed %d)" % (i + 1, len(todo), scene, n, seed))
    print("done: backdrops under sources/backgrounds/raw")
    return 0


if __name__ == "__main__":
    sys.exit(main())
