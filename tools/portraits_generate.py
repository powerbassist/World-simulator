"""V2.3 portrait recipe, generation half. Stdlib only.

Sweeps data/people/*.json (the register IS the roster -- nothing here is a
hand-written list of people), derives one prompt per person, and drives a
running ComfyUI over its HTTP API using tools/portraits_workflow.json as the
template -- API format, so every key in that file is a node the server must
know: a "_comment" key at the top level is a 500 on current ComfyUI, which is
why the recipe's notes live here instead. The workflow is one fixed framing,
background and lighting (Juggernaut X Hyper, 832x1216, 8 steps) so the duotone
pass in tools/portraits.gd is what unifies the wall -- "one crop, one eyeline"
starts here.

Likeness policy, fixed at plan time: a portrait EVOKES the real politician its
fictional name plays on, it does not depict them. The prompt is built from a
described archetype (age band, hair, glasses, demeanour) and never contains a
real person's name. Someone not in ARCHETYPES falls back to a generic archetype
for their gender and a seed-chosen age -- the pipeline never gates the register.

Person 72: add them to data/people/, optionally one ARCHETYPES line, run this
script (only missing ids are generated), then run tools/portraits.gd. The
committed PNGs are canonical; a ComfyUI or checkpoint drift changes what a
regeneration would produce, never what is shipped.

Machine dependency, stated honestly: needs ComfyUI_windows_portable at
F:/ComfyUI_windows_portable with Juggernaut_X_RunDiffusion_Hyper.safetensors
(RunDiffusion's Juggernaut X, CivitAI) listening on 127.0.0.1:8188. Start it
with run_nvidia_gpu.bat from that directory first.
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOST = "127.0.0.1"
PORT = 8188
ALLOWED_HOSTS = ("127.0.0.1", "localhost")

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
WORKFLOW = TOOLS / "portraits_workflow.json"
PEOPLE_DIR = REPO / "data" / "people"
RAW_DIR = REPO / "sources" / "portraits" / "raw"


def _confined(path, root):
    """Every filesystem path this script touches is normalized here and proven
    to resolve inside its declared root, so no joined or discovered path can
    walk out of the directories this recipe owns."""
    resolved = Path(path).resolve()
    base = Path(root).resolve()
    if base not in resolved.parents and resolved != base:
        raise RuntimeError("path '%s' escapes its allowed root '%s'" % (path, root))
    return resolved


## The loader's own namespacing rule (tests/test_people.gd checks the same
## thing): a person id is <NATION>_<surname>. Every output filename this script
## builds starts from a person id read out of a JSON file, so the ids are
## validated against the scheme before they are joined -- the register is
## trusted content, but a path is not the place to find out.
ID_SCHEME = re.compile(r"^[A-Z]{3}_[a-z][a-z0-9_]*$")


def _checked_id(person_id):
    if not ID_SCHEME.match(person_id):
        raise RuntimeError("person id '%s' does not match the register's <NATION>_<surname> scheme" % person_id)
    return person_id


def _raw_path(person_id):
    return _confined(RAW_DIR / (_checked_id(person_id) + ".png"), RAW_DIR)


## Anything that reaches a URL path or query -- the server-issued prompt id, a
## returned filename -- passes through here first: no parent-directory walks,
## no drive letters, no backslashes, no leading slash. ComfyUI subfolders may
## contain "/" (they are relative paths), everything else may not.
def _safe_segment(value, what, allow_slash=False):
    if value is None:
        raise RuntimeError("unsafe %s from the API: %r" % (what, value))
    text = str(value)
    if text == "":
        return text  # the API's "no subfolder" -- empty cannot traverse
    if text.startswith(("/", "\\")) or ":" in text or "\\" in text or ".." in text:
        raise RuntimeError("unsafe %s from the API: %r" % (what, text))
    if "/" in text and not allow_slash:
        raise RuntimeError("unsafe %s from the API: %r" % (what, text))
    return text


## The frame constants, and nothing about the person: suit, camera, background,
## lighting. The expression moved out of here into EXPRESSION below -- it was
## pinned here when only the seed varied, which is half of why the first wall
## read as siblings.
STYLE = (
    "formal dark suit, looking directly at the camera, head and shoulders "
    "framing, plain dark grey background, soft directional studio lighting, "
    "sharp focus, photorealistic, 85mm lens"
)

## person id -> the described archetype that replaces "a man in his 50s". Filled
## from the author's counterpart notes; extends one line at a time and unknown
## ids fall back below, so this is art direction rather than a roster the
## pipeline depends on. Described traits only -- a real name in here would be a
## likeness, which is exactly what the policy above refuses.
ARCHETYPES = {}

## First names occurring in the register, mapped to gender for the fallback
## archetype's wording. Same discipline as ARCHETYPES: a vocabulary that
## extends for free, unknown names fall back with a logged note.
GENDER = {
    "female": """
        Ingrid Theresa Elisabeth Naima Lore Celine Andrea Livia Katrin Annika
        Marlene Rocio Nuria Helene Camille Nadia Cecile Caroline Miriam Rhona
        Chiara Serena Nathalie Anouk Ellen Marijke Fenna
    """,
    "male": """
        Bernhard Wolfgang Lukas Rudolf Joris Bram Pieter Tom Baudouin Reto
        Markus Fabio Ulrich Matthias Jens Dietrich Friedrich Alvaro Mateo Iker
        Alfonso Daniel Bruno Gilles Charles Edward Adrian Duncan Robert Lorenzo
        Piergiorgio Vittorio Enzo Umberto Carlo Marc Serge Jean-Paul Adolphe
        Sander Willem Ruben Maurits
    """,
}


## Per-person trait vocabulary. "One crop, one eyeline" constrains the FRAME;
## the FACE is where variety lives, and a fixed prompt with only the seed
## varying made the first wall of 71 read as siblings -- the author's judgement
## on the contact sheet, not a hypothesis. Each category is picked by its own
## hash of the person id, so traits are decorrelated (hair does not predict
## glasses) and the whole thing stays deterministic per person. Described
## archetypes in ARCHETYPES above bypass all of this for the people the author
## has notes on.
HAIR = {
    "male": [
        "short neat hair", "receding hairline", "closely cropped hair",
        "thick silver hair", "swept-back grey hair", "bald head",
        "wavy dark hair", "short curly greying hair", "flat, severely parted hair",
    ],
    "female": [
        "shoulder-length hair", "short bob", "long straight hair",
        "grey hair in a low bun", "chin-length greying hair",
        "dark hair pulled back tightly", "layered mid-length hair",
        "short silver pixie cut",
    ],
}
FACIAL_HAIR = [
    "clean-shaven", "clean-shaven", "clean-shaven",  # weighted: most statesmen
    "neat stubble", "trimmed grey moustache", "short full beard",
    "salt-and-pepper beard",
]
GLASSES = [
    "no glasses", "no glasses", "no glasses",  # likewise
    "thin rectangular glasses", "round wire-frame glasses", "dark-framed glasses",
]
EXPRESSION = [
    "calm, composed expression", "serious, thoughtful expression",
    "faint reserved smile", "stern, determined expression",
    "weary but alert expression", "quietly amused expression",
]
FACE = [
    "broad face with a strong jaw", "narrow, angular face",
    "round, soft-featured face", "long face with a high forehead",
    "square face with heavy brows",
]
QUIRK = [
    "prominent nose", "deep-set eyes", "high cheekbones",
    "strong brow ridge", "thin lips", "weathered, lined skin",
    "widow's peak", "heavy eyelids",
]
AGES = ["mid 40s", "late 40s", "early 50s", "mid 50s", "late 50s", "60s", "mid 60s", "70s"]


def _pick(person_id: str, category: str, options) -> str:
    """One decorrelated pick per category: hash the id WITH the category name,
    so two categories never read the same slice of the seed."""
    return options[djb2(person_id + ":" + category) % len(options)]


def _strip_accents(s):
    swaps = {
        "á": "a", "é": "e", "è": "e", "ê": "e", "í": "i", "ó": "o", "ú": "u",
        "ñ": "n", "ç": "c", "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ú": "U",
    }
    return "".join(swaps.get(c, c) for c in s)


def _open(path, data=None, headers=None, timeout=90):
    """Every request this script makes goes through here, and here is where the
    one allowed destination is enforced: plain http to the local ComfyUI and
    nothing else, ever."""
    url = urllib.parse.urlunparse(("http", "%s:%d" % (HOST, PORT), path, "", "", ""))
    parts = urllib.parse.urlparse(url)
    if parts.scheme != "http" or parts.hostname not in ALLOWED_HOSTS:
        raise RuntimeError("refusing non-local API URL: %s" % url)
    req = urllib.request.Request(url, data=data, headers=headers or {})
    return urllib.request.urlopen(req, timeout=timeout)


def djb2(s):
    """Stable across languages and engine versions -- String.hash() is neither
    guaranteed across Godot bumps nor matching Python. The seed must survive
    re-runs, so it gets its own five lines."""
    h = 5381
    for c in s.encode("utf-8"):
        h = ((h * 33) + c) & 0xFFFFFFFF
    return h


def prompt_for(person_id, name):
    seed = djb2(person_id)
    notes = []
    if person_id in ARCHETYPES:
        subject = ARCHETYPES[person_id]
    else:
        first = _strip_accents(name.split()[0]).lower()
        gender = None
        for candidate, blob in GENDER.items():
            if first in blob.lower().split():
                gender = candidate
                break
        if gender is None:
            gender = "male"
            notes.append("first name '%s' not in the gender table, defaulting to male" % name.split()[0])
        female = gender == "female"
        noun = "woman" if female else "man"
        poss = "her" if female else "his"
        age = _pick(person_id, "age", AGES)
        parts = [
            "a %s in %s %s" % (noun, poss, age),
            _pick(person_id, "face", FACE),
            _pick(person_id, "hair", HAIR["female" if female else "male"]),
            _pick(person_id, "expression", EXPRESSION),
            _pick(person_id, "quirk", QUIRK),
        ]
        if not female:
            parts.append(_pick(person_id, "facial", FACIAL_HAIR))
        parts.append(_pick(person_id, "glasses", GLASSES))
        subject = ", ".join(parts)
    text = "professional studio headshot portrait photograph of %s, %s" % (subject, STYLE)
    return seed, text, notes


def generate(person_id, seed, text):
    workflow = json.loads(_confined(WORKFLOW, TOOLS).read_text(encoding="utf-8"))
    workflow["3"]["inputs"]["seed"] = seed
    workflow["6"]["inputs"]["text"] = text
    payload = json.dumps({"prompt": workflow, "client_id": "ws-portraits"}).encode()
    prompt_id = json.load(_open("/prompt", data=payload,
                                headers={"Content-Type": "application/json"}))["prompt_id"]
    prompt_id = _safe_segment(prompt_id, "prompt id")
    for _ in range(120):
        time.sleep(2)
        history = json.loads(_open("/history/" + prompt_id).read())
        if prompt_id not in history:
            continue
        entry = history[prompt_id]
        status = entry.get("status", {})
        if status.get("status_str") == "error":
            raise RuntimeError("ComfyUI error for %s" % person_id)
        if not status.get("completed"):
            continue
        for node in entry["outputs"].values():
            for image in node.get("images", []):
                query = urllib.parse.urlencode({
                    "filename": _safe_segment(image["filename"], "image filename"),
                    "subfolder": _safe_segment(image.get("subfolder", ""), "image subfolder", allow_slash=True),
                    "type": _safe_segment(image["type"], "image type")})
                return _open("/view?" + query).read()
    raise RuntimeError("timed out waiting for %s" % person_id)


def main():
    people = []
    for path in sorted(PEOPLE_DIR.glob("*.json")):
        data = json.loads(_confined(path, REPO).read_text(encoding="utf-8"))
        for person in data["people"]:
            people.append((_checked_id(person["id"]), person["name"]))

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    todo = [(pid, name) for pid, name in people if not _raw_path(pid).exists()]

    print("register holds %d people (%d with an authored archetype); "
          "%d already have raw output, %d to generate"
          % (len(people), sum(1 for pid, _ in people if pid in ARCHETYPES),
             len(people) - len(todo), len(todo)))
    for i, (person_id, name) in enumerate(todo):
        seed, text, notes = prompt_for(person_id, name)
        for note in notes:
            print("  note: %s" % note)
        out = _raw_path(person_id)
        out.write_bytes(generate(person_id, seed, text))
        print("  [%d/%d] %s (seed %d)" % (i + 1, len(todo), person_id, seed))
    print("done: %d raw portraits under sources/portraits/raw" % len(people))
    return 0


if __name__ == "__main__":
    sys.exit(main())
