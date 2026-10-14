"""V4.4 event art, generation half -- the V3.7 background recipe re-aimed.
Stdlib only (HTTP via comfy_client).

Renders the event plate library the game REUSES BY CATEGORY (CK3's `theme`
shape, docs/event-art-plan.md): one image per (category x severity band), not
per event, 2 seeded variants each -- 9 categories x 3 bands x 2 = 54 renders.
The variant a given event shows is picked at display time, stably, from its
own id (src/ui/event_art.gd) -- these files are the pool, not the assignment.

Every plate prompt carries the plan's mood grammar VERBATIM, and the grammar
is why this recipe does not share the background template's workflow file:
backdrops are photoreal and their negative prompt bans "illustration, painting"
-- exactly the look this library asks for. Same graph, same checkpoint, same
sampler and node ids (TEXT/SEED/IMAGE = 2/5/7); the latent is LANDSCAPE
(1216x832 -- the headers are 16:9) and the negative keeps the people/text bans
and adds the photographic ones instead.

--dry-run: print every prompt and seed, contact nothing. --only <category>
slices. Out: sources/event_art/raw/<category>_<band>_<n>.png; the Godot
post-pass (tools/event_art.gd) turns them into assets/event_art/.

Machine dependency, stated honestly: needs ComfyUI listening on 127.0.0.1:8188
(tools/comfy_client.py), with Juggernaut_X_RunDiffusion.safetensors on disk.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comfy_client as comfy  # noqa: E402

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
WORKFLOW = TOOLS / "event_art_workflow.json"
RAW_DIR = REPO / "sources" / "event_art" / "raw"

## Node ids in the template -- prompt in, seed in, image out. The background
## template's ids, kept: one shape across the recipe's three workflow files.
TEXT_NODE, SEED_NODE, IMAGE_NODE = "2", "5", "7"

VARIANTS = 2

## The plan's plate table, one dressing phrase per (category, band). Described
## scenes -- a leak is a file on a desk, not a named minister's office -- on
## the likeness policy the whole recipe runs under: moods and settings, never
## a real person, party, logo or masthead.
PROMPTS = {
    "scandal": {
        "minor": "a leaked dossier lying open on a dark wooden ministerial desk, papers fanned under a green desk lamp",
        "major": "a press scrum, a thicket of microphones and camera lenses before a lectern, frozen flash glare",
        "critical": "an empty resignation podium before a wall of microphones, one overhead light",
    },
    "fiscal": {
        "minor": "a leather-bound ledger and a desk calculator on a mahogany table, columns of blurred figures",
        "major": "a bond ticker board glowing over a deserted trading floor at dusk, figures blurred beyond reading",
        "critical": "an emergency cabinet table at night, chairs askew, abandoned papers, one lamp still burning",
    },
    "unrest": {
        "minor": "a small protest march seen from a distance, handmade placards blurred beyond reading, a wet street",
        "major": "a picket line outside a factory gate in winter, oil-drum braziers, breath haze, grey sleet",
        "critical": "the morning after a riot, broken glass and scorched rubble along an empty boulevard, smoke haze",
    },
    "personal": {
        "minor": "two chairs at a small round table, one empty, a cooling coffee cup",
        "major": "an unopened letter on a silver tray, wax seal unbroken, at the end of a dark hallway",
        "critical": "a celebration table split down the middle, one half cleared, chairs turned away",
    },
    "european": {
        "minor": "national flags on stands along a marble corridor, soft window light",
        "major": "a summit hall at night, a great round table under low lights, seats empty",
        "critical": "a lone empty seat at a long conference table, blank nameplate, cold morning light",
    },
    "foreign": {
        "minor": "a harbour at dusk, container cranes and a moored ferry, amber sky",
        "major": "an embassy gate, wrought iron and stone pillars, wet cobbles, a discreet plaque",
        "critical": "a black telephone lit by a single lamp in a dark room, the small hours",
    },
    "industrial": {
        "minor": "a quiet factory floor between shifts, an idle assembly line, dusty shafts of light",
        "major": "a plant gate closed with a heavy padlock and chain, grey rain",
        "critical": "a cooling tower venting steam at night, red emergency beacon light washing the buildings",
    },
    "commodity": {
        "minor": "a market stall with wooden crates of vegetables under an awning, morning light",
        "major": "a container yard at dusk, stacked containers and crane silhouettes",
        "critical": "empty supermarket shelves under a single fluorescent tube, bare metal",
    },
    "disaster": {
        "minor": "a swollen brown river surging beneath a stone bridge in heavy rain",
        "major": "a burnt hillside after a wildfire, blackened pines, ash drifts, smouldering stumps",
        "critical": "a flooded street at night, water up to the doorsteps, reflections of blue emergency lights",
    },
}

## The plan's mood grammar, VERBATIM on every prompt. "no people" keeps this
## category art rather than portraiture (the portraits own faces); "no readable
## text" keeps generated signage from inventing words the interface contradicts.
MOOD_GRAMMAR = ("no people, no readable text, painterly editorial illustration, "
                "muted palette, soft light from camera-left")

BANDS = ["minor", "major", "critical"]


def prompt_for(category: str, band: str, n: int):
    """The prompt for one plate. The seed is the hash of the plate id -- the
    portraits' determinism discipline: a re-run must ask the renderer for the
    same images, and plate id -> seed is pure (no random anywhere)."""
    plate = "%s_%s_%d" % (category, band, n)
    seed = comfy.djb2(plate)
    text = "%s, %s" % (PROMPTS[category][band], MOOD_GRAMMAR)
    return seed, text


def generate(category: str, band: str, n: int, seed: int, text: str) -> bytes:
    workflow = json.loads(comfy._confined(WORKFLOW, TOOLS).read_text(encoding="utf-8"))
    workflow[SEED_NODE]["inputs"]["seed"] = seed
    workflow[TEXT_NODE]["inputs"]["text"] = text
    prompt_id = comfy.queue(workflow)
    out = comfy.outputs(prompt_id, timeout_s=900)
    if not out.get(IMAGE_NODE):
        raise RuntimeError("no output at node %s for %s_%s_%d" % (IMAGE_NODE, category, band, n))
    return comfy.fetch(out[IMAGE_NODE][0])


def _args() -> set:
    """--only <category> (repeatable) slices the library."""
    only = set()
    args = sys.argv
    for i, a in enumerate(args):
        if a == "--only" and i + 1 < len(args):
            if args[i + 1] not in PROMPTS:
                raise RuntimeError("unknown category '%s' -- %s" % (args[i + 1], sorted(PROMPTS)))
            only.add(args[i + 1])
    return only


def _jobs(only):
    """The (category, band) work list, table order."""
    jobs = []
    for category in PROMPTS:
        if only and category not in only:
            continue
        for band in BANDS:
            jobs.append((category, band))
    return jobs


def main() -> int:
    only = _args()
    if "--dry-run" in sys.argv:
        count = 0
        for category, band in _jobs(only):
            for n in range(VARIANTS):
                seed, text = prompt_for(category, band, n)
                print("%s_%s_%d (seed %d)\n  %s" % (category, band, n, seed, text))
                count += 1
        print("%d plates in the dry-run, nothing contacted" % count)
        return 0

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    todo = []
    for category, band in _jobs(only):
        for n in range(VARIANTS):
            if not (RAW_DIR / ("%s_%s_%d.png" % (category, band, n))).exists():
                todo.append((category, band, n))
    print("%d event plates to generate" % len(todo))
    for i, (category, band, n) in enumerate(todo):
        seed, text = prompt_for(category, band, n)
        try:
            out = comfy._confined(RAW_DIR / ("%s_%s_%d.png" % (category, band, n)), RAW_DIR)
            out.write_bytes(generate(category, band, n, seed, text))
        except Exception as err:
            print("FAIL on %s_%s_%d: %s" % (category, band, n, err))
            print("ComfyUI is unreachable or errored -- start it (F:/ComfyUI_windows_portable, "
                  "run_nvidia_gpu.bat) so it listens on 127.0.0.1:8188, then re-run this script; "
                  "finished plates are skipped on re-run.")
            return 1
        print("  [%d/%d] %s_%s_%d (seed %d)" % (i + 1, len(todo), category, band, n, seed))
    print("done: plates under sources/event_art/raw")
    return 0


if __name__ == "__main__":
    sys.exit(main())
