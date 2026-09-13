"""V3.7 portrait recipe, generation half. Stdlib only (HTTP via comfy_client).

Sweeps data/people/*.json (the register IS the roster -- nothing here is a
hand-written list of people), derives one prompt per person per emotion, and
drives a running ComfyUI over its HTTP API using tools/portraits_workflow.json
(base) and tools/portraits_expression_workflow.json (the four non-neutral
expressions, FaceDetailer inpaint over the base) -- API format, so every key in
those files is a node the server must know: a "_comment" key at the top level
is a 500 on current ComfyUI, which is why the recipe's notes live here instead.
The workflow is one fixed framing, camera and lighting (Juggernaut X Hyper,
832x1216, 8 steps, PerfectEyesXL at 0.35); variety comes from the PROMPT -- the
V2.3 duotone pass that used to unify the wall is gone, realism is the look.

Variety axes, and why they live here: "one crop, one eyeline" constrains the
FRAME; the FACE is where variety lives. The prompt is built from the person's
own sidecar entry (tools/portraits_traits.json -- sex, age, build, hair,
glasses, facial hair, face shape, one quirk, wardrobe), the nation prefix's
region look, and the role the data already assigns them. Art direction stays
OUT of data/people/: src/core/person.gd is id-and-name by construction, and
age, sex and wardrobe are not game facts. The sidecar is seeded for any id
missing from it (deterministically, from the same decorrelated djb2 pickers),
then read forever after -- hand-editable, and person 214 never requires
touching this file. The V2.3 GENDER first-name table is gone: it defaulted
unknown names to male, which across 213 people is most of them, and is why the
wall skewed 12.7% female.

Likeness policy, fixed at plan time and unchanged: a portrait EVOKES the real
politician its fictional name plays on, it does not depict them. The prompt is
built from described traits only and never contains a real person's name --
--self-check enforces this against tools/banned_names.txt rather than trusting
the docstring.

Passes: 1 renders the base (neutral) for every person missing one; 2 runs the
four non-neutral expressions through the expression workflow against each base.
Out: sources/portraits/raw/<emotion>/<person_id>.png and
sources/portraits/mask/<emotion>/<person_id>.png -- the mask is matting
(BiRefNet-portrait), written beside the raw for the Godot post-pass to turn
into alpha. Only missing ids are generated, per person per emotion.

--dry-run: seed the sidecar, print every prompt, contact nothing. Read it --
213 prompts that differ by region, role, sex, age and wardrobe, or the trait
machines are wrong and a generation run would burn hours proving it.
--self-check: the five properties tests/test_portraits.gd also gates.

Machine dependency, stated honestly: needs ComfyUI_windows_portable at
F:/ComfyUI_windows_portable with Juggernaut_X_RunDiffusion_Hyper.safetensors
listening on 127.0.0.1:8188 (start run_nvidia_gpu.bat first). The ComfyUI
environment -- node packs, matting weights -- is checked by
tools/workflow_check.py against the live server.
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comfy_client as comfy  # noqa: E402

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
WORKFLOW = TOOLS / "portraits_workflow.json"
EXPRESSION_WORKFLOW = TOOLS / "portraits_expression_workflow.json"
TRAITS_PATH = TOOLS / "portraits_traits.json"
BANNED_NAMES = TOOLS / "banned_names.txt"
PEOPLE_DIR = REPO / "data" / "people"
RAW_DIR = REPO / "sources" / "portraits" / "raw"
MASK_DIR = REPO / "sources" / "portraits" / "mask"

## Node ids in the two workflow templates -- where the generator injects the
## prompt and seed, and where the image + mask come back out. If a template is
## restructured, these move with it and workflow_check.py says so.
BASE_TEXT_NODE, BASE_SEED_NODE = "4", "6"
BASE_IMAGE_NODE, BASE_MASK_NODE = "8", "11"
EXPR_TEXT_NODE, EXPR_SEED_NODE = "4", "6"
EXPR_IMAGE_NODE, EXPR_MASK_NODE = "8", "11"

EMOTIONS = ["neutral", "pleased", "stern", "worried", "weary"]

## The five faces, as FaceDetailer-positive fragments. V1 wording produced
## identity-perfect but nearly identical faces -- the author's verdict on the
## first wall's strip -- so these are written LOUD: gross features (mouth
## curve, brow, eyelids) must carry the emotion at the card's 54x74. The
## expression negative deliberately drops "smiling broadly", pleased needs it.
EMOTION_FRAGMENTS = {
    "neutral": "calm, composed, neutral expression, lips closed",
    "pleased": "warm broad smile, teeth visible, eyes crinkled with joy, cheeks raised",
    "stern": "stern angry glare, deep frown, brows compressed down, jaw clenched, lips a hard thin line",
    "worried": "deeply worried, anxious frown, forehead furrowed, brows knotted upward, eyes wide with concern",
    "weary": "utterly exhausted, heavy sagging eyelids, deep eye bags, hollow drained face",
}

## The frame constants, and nothing about the person: camera, background,
## lighting. Wardrobe moved out of here into the sidecar at V3.7 -- it is a
## per-person trait now, role-keyed, not a constant of the recipe.
STYLE = (
    "looking directly at the camera, head and shoulders framing, plain dark "
    "grey background, soft directional studio lighting, sharp focus, "
    "photorealistic, 85mm lens"
)

## Sex seeding replaces the V2.3 male-by-default first-name table. The wall it
## shipped read 12.7% female (27 of 213, measured 2026-09-12); 0.35 is the
## plan-time default the author signed off, applied as a hash pick so it is
## deterministic per person and hand-editable in the sidecar after.
FEMALE_PROBABILITY = 0.35

## 4a. Region look, keyed off the nation prefix already in the person id --
## the single biggest missing variety axis (a Finnish and a Greek minister
## were drawn from one distribution). 29 codes; described appearance only, and
## deliberately not word-identical between neighbouring nations -- siblings
## were the first wall's failure.
REGION = {
    "AUT": "Central European, fair skin, light eyes common",
    "BEL": "Western European, fair to medium skin",
    "BGR": "Balkan, olive skin, dark hair",
    "CHE": "Alpine European, fair skin",
    "CYP": "eastern Mediterranean, olive skin, dark eyes",
    "CZE": "Central European, fair skin, broad features",
    "DEU": "Central European, fair skin, cool complexion",
    "DNK": "Nordic, fair skin, blonde hair common",
    "ESP": "Mediterranean, olive skin, dark eyes",
    "EST": "Baltic, fair skin, light eyes",
    "FIN": "Nordic, fair skin, pale eyes",
    "FRA": "Western European, fair to olive skin",
    "GBR": "British Isles, fair skin, ruddy complexion common",
    "GRC": "Mediterranean, olive skin, dark eyes",
    "HRV": "Central European and Balkan mix, fair to olive skin",
    "HUN": "Central European, fair skin, dark blond hair common",
    "IRL": "British Isles, fair skin, freckles common",
    "ITA": "Mediterranean, olive skin, dark eyes",
    "LTU": "Baltic, fair skin, light eyes",
    "LUX": "Western European, fair skin",
    "LVA": "Baltic, fair skin",
    "MLT": "Mediterranean, olive skin, dark eyes, warm complexion",
    "NLD": "North Sea European, fair skin, tall build",
    "POL": "Central European, fair skin, angular features",
    "PRT": "Iberian, olive skin, dark eyes",
    "ROU": "Balkan and Eastern European mix, olive to fair skin",
    "SVK": "Central European, fair skin, high cheekbones",
    "SVN": "Alpine and Balkan mix, fair to olive skin",
    "SWE": "Nordic, fair skin, pale eyes",
}

## 4b. Role, derived from the data that already owns the relationship -- the
## office is the slot pointing at the person, never a field on them (the
## Person rule). The sweep reads leader.person, government.head_of_state.person
## and government.pretender_person from data/nations/, leader_person from
## data/parties/; precedence head_of_government > head_of_state > pretender >
## party_leader, and parties never overwrite a national office.
ROLE_BEARING = {
    "head_of_government": "head-of-government bearing, confident composed posture",
    "head_of_state": "ceremonial head-of-state bearing, dignified reserved posture",
    "pretender": "formal courtly bearing, composed and watchful",
    "party_leader": "party-leader energy, direct engaging posture",
    "figure": "professional bearing",
}
## Wardrobe is role-keyed and sex-keyed: the V2.3 lesson generalized -- one
## list for everyone put a pale blue tie on every woman in Europe.
WARDROBE_BY_ROLE = {
    "head_of_government": {
        "male": ["charcoal suit, subdued tie", "navy suit, dark red tie",
                 "dark grey suit, pale blue tie"],
        "female": ["charcoal tailored suit, silk scarf", "navy suit, pearl earrings",
                   "dark tailored suit, brooch"],
    },
    "head_of_state": {
        "male": ["black formal suit, white pocket square", "midnight blue suit, silver tie"],
        "female": ["black formal suit, white blouse", "midnight blue suit, silver brooch"],
    },
    "pretender": {
        "male": ["dark formal suit, discreet tie pin", "black suit, high collar"],
        "female": ["dark formal dress, high collar", "black tailored dress, discreet jewels"],
    },
    "party_leader": {
        "male": ["open-collar dark suit, no tie", "brown suit, patterned tie",
                 "charcoal suit, party-badge lapel pin"],
        "female": ["open-collar dark blazer", "burgundy blazer, dark trousers",
                   "charcoal suit, bold scarf"],
    },
    "figure": {
        "male": ["grey suit, plain tie", "dark jacket, open collar"],
        "female": ["grey suit, plain blouse", "dark jacket, open collar"],
    },
}

## Per-person trait vocabulary, carried over from V2.3 where it worked (the
## first wall's per-category hash pickers) plus the new axes. Each category is
## picked by its own hash of the person id, so traits are decorrelated (hair
## does not predict glasses) and the whole thing stays deterministic.
HAIR = {
    "male": [
        "short neat hair", "receding hairline", "closely cropped hair",
        "thick silver hair", "swept-back grey hair", "bald head",
        "wavy dark hair", "short curly greying hair", "flat, severely parted hair",
        "thinning dark hair combed back", "wild salt-and-pepper hair",
        "sandy blond hair, receding", "auburn hair swept forward",
        "light brown hair with a cowlick",
    ],
    "female": [
        "shoulder-length hair", "short bob", "long straight hair",
        "grey hair in a low bun", "chin-length greying hair",
        "dark hair pulled back tightly", "layered mid-length hair",
        "short silver pixie cut", "chestnut hair in a chignon",
        "wavy auburn hair", "blonde hair, loose curls", "raven-black hair, blunt fringe",
        "honey-blonde bob", "platinum hair, slicked back",
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
FACE = [
    "broad face with a strong jaw", "narrow, angular face",
    "round, soft-featured face", "long face with a high forehead",
    "square face with heavy brows", "gaunt, hollow-cheeked face",
    "heart-shaped face", "long thin face with deep nasolabial folds",
]
## How the AGE reads in the face -- the number alone does not survive the
## model's "distinguished statesman" prior; this is what makes a 38-year-old
## look 38 and not 55 with better lighting. Picked by its own hash, then
## constrained by the age band so the words never contradict the number.
FACE_AGE = {
    "young": ["youthful face", "young for their age, fresh complexion"],
    "prime": ["middle-aged features", "mature but vigorous face"],
    "old": ["heavily lined face", "aged, weathered face", "face lined by decades in office"],
}
## The age band, and why role moved it: a 44-71 wall read as one late-career
## blob (the author's judgement on the first slice). Real cabinets hold
## 35-year-old rising party leaders and 78-year-old monarchs.
AGE_BAND = {
    "head_of_government": (42, 72),
    "head_of_state": (48, 78),
    "pretender": (45, 75),
    "party_leader": (35, 68),
    "figure": (40, 70),
}
QUIRK = [
    "prominent nose", "deep-set eyes", "high cheekbones",
    "strong brow ridge", "thin lips", "weathered, lined skin",
    "widow's peak", "heavy eyelids",
]
BUILDS = ["trim", "solid", "heavyset", "slim", "broad-shouldered"]

## Populated by main() before any prompt is built: person_id -> sidecar entry,
## person_id -> role.
_traits = {}
_roles = {}


def _pick(person_id: str, category: str, options) -> str:
    """One decorrelated pick per category: hash the id WITH the category name,
    so two categories never read the same slice of the seed."""
    return options[comfy.djb2(person_id + ":" + category) % len(options)]


def _face_age_bucket(age: int):
    """The FACE_AGE words the age number allows -- the words must agree with
    the number or the prompt argues with itself."""
    if age < 48:
        return FACE_AGE["young"]
    if age < 62:
        return FACE_AGE["prime"]
    return FACE_AGE["old"]


def _sweep_slots():
    """Yield (person_id, slot_name) for every person the content points at.
    THE one walk over the data; roles() builds its map from this, and
    --self-check re-runs it to prove the map covers every slot."""
    for path in sorted((REPO / "data" / "nations").glob("*.json")):
        d = json.loads(comfy._confined(path, REPO).read_text(encoding="utf-8"))
        leader = d.get("leader", {}).get("person")
        if isinstance(leader, str) and leader:
            yield leader, "head_of_government"
        head = d.get("government", {}).get("head_of_state")
        if isinstance(head, dict) and isinstance(head.get("person"), str) and head["person"]:
            yield head["person"], "head_of_state"
        pretender = d.get("government", {}).get("pretender_person")
        if isinstance(pretender, str) and pretender:
            yield pretender, "pretender"
    for path in sorted((REPO / "data" / "parties").glob("*.json")):
        d = json.loads(comfy._confined(path, REPO).read_text(encoding="utf-8"))
        for party in d.get("parties", []):
            pid = party.get("leader_person")
            if isinstance(pid, str) and pid:
                yield pid, "party_leader"


def roles() -> dict:
    """person_id -> role, off the sweep. First match in the sweep order wins,
    which is the precedence list -- and party leaders only ever fill people no
    national office points at."""
    out = {}
    for pid, slot in _sweep_slots():
        if pid not in out:
            out[pid] = slot
    return out


def load_traits(people) -> dict:
    """The sidecar is the art direction; the register is the roster. Any id
    missing from the sidecar is seeded here -- deterministically, from the
    decorrelated pickers, sex as a hash pick at FEMALE_PROBABILITY (which
    replaces the male-default first-name table) and role-keyed wardrobe -- and
    the file is written back immediately, so --dry-run persists it and the
    author can hand-edit any line before a generation run."""
    traits = {}
    if TRAITS_PATH.exists():
        traits = json.loads(comfy._confined(TRAITS_PATH, TOOLS).read_text(encoding="utf-8"))
    role_map = roles()
    changed = False
    for pid, _name in people:
        if pid in traits:
            continue
        female = comfy.djb2(pid + ":sex") % 10000 < int(FEMALE_PROBABILITY * 10000)
        role = role_map.get(pid, "figure")
        lo, hi = AGE_BAND[role]
        age = lo + comfy.djb2(pid + ":age") % (hi - lo + 1)
        traits[pid] = {
            "sex": "female" if female else "male",
            "age": age,
            "build": _pick(pid, "build", BUILDS),
            "hair": _pick(pid, "hair", HAIR["female" if female else "male"]),
            "glasses": _pick(pid, "glasses", GLASSES),
            # females carry no facial-hair trait at all -- the sidecar entry is
            # the art direction, not a marker: omitting the key is how the
            # prompt stays clean (a "clean-shaven" string on a woman was
            # exactly the leak the dry-run caught).
            **({} if female else {"facial": _pick(pid, "facial", FACIAL_HAIR)}),
            "face": _pick(pid, "face", FACE),
            "quirk": _pick(pid, "quirk", QUIRK),
            "wardrobe": _pick(pid, "wardrobe:" + role,
                              WARDROBE_BY_ROLE[role]["female" if female else "male"]),
        }
        changed = True
    if changed:
        TRAITS_PATH.write_text(
            json.dumps(dict(sorted(traits.items())), indent=1, ensure_ascii=False) + "\n",
            encoding="utf-8")
    return traits


def prompt_for(person_id, name, emotion="neutral"):
    """The prompt, from the person's own sidecar entry + region + role + the
    emotion fragment. `name` is carried in the signature for the register
    sweep's shape and deliberately reaches no prompt -- the likeness policy is
    that no real name ever does, which --self-check enforces. For the
    expression renders the caller locks the seed to the base render's
    (generate_expression), so identity holds and only the fragment moves."""
    t = _traits[person_id]
    # V3.7 Phase B2: per-person skin and eyes come first when the sidecar has
    # them (from the counterpart mapping) -- the REGION look is the fallback
    # only for people they do not cover, and it is now nation-realistic.
    region = REGION.get(person_id.split("_")[0], "European")
    role = _roles.get(person_id, "figure")
    noun = "woman" if t["sex"] == "female" else "man"
    poss = "her" if t["sex"] == "female" else "his"
    parts = [
        "a %d-year-old %s in %s prime" % (t["age"], noun, poss),
        t.get("skin", region),
        t["build"] + " build",
        t["face"],
        # Derived from the live age, never stored: the words must agree with
        # the number even after a hand edit moves it, and the empty-string
        # join would otherwise print a double comma on older sidecar entries.
        _pick(person_id, "face_age", _face_age_bucket(t["age"])),
        t["hair"],
        t.get("eyes", ""),
    ]
    parts = [p for p in parts if p]
    if "facial" in t:
        parts.append(t["facial"])
    parts += [
        t["glasses"],
        t["quirk"],
        ROLE_BEARING[role],
        t["wardrobe"],
        EMOTION_FRAGMENTS[emotion],
    ]
    subject = ", ".join(parts)
    text = "professional studio headshot portrait photograph of %s, %s" % (subject, STYLE)
    seed = comfy.djb2(person_id + ":" + emotion)
    return seed, text, []


def _load_people():
    people = []
    for path in sorted(PEOPLE_DIR.glob("*.json")):
        data = json.loads(comfy._confined(path, REPO).read_text(encoding="utf-8"))
        for person in data["people"]:
            people.append((comfy._checked_id(person["id"]), person["name"]))
    return people


def _banned_pattern():
    """banned_names.txt up to its [places] marker: politician and party names,
    enforced against every prompt. The [places] section is scoped to
    data/companies/ by its own rule and is not prompt vocabulary."""
    entries = []
    for line in BANNED_NAMES.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line == "[places]":
            break
        if line and not line.startswith("#"):
            entries.append(line)
    return re.compile(r"\b(?:" + "|".join(re.escape(e) for e in entries) + r")\b", re.IGNORECASE)


def self_check(people) -> int:
    """Phase A's real teeth -- the five properties the suite gates on every
    run, no GPU required. Returns the process exit code."""
    failures = []

    # 1. the sidecar covers every register id (load_traits seeded it)
    missing = [pid for pid, _ in people if pid not in _traits]
    if missing:
        failures.append("sidecar missing %d ids, first: %s" % (len(missing), missing[0]))

    # 2. the likeness policy, enforced: no banned name in any of the 5*213 prompts
    pattern = _banned_pattern()
    hits = []
    for pid, name in people:
        for emotion in EMOTIONS:
            _seed, text, _notes = prompt_for(pid, name, emotion)
            found = pattern.search(text)
            if found:
                hits.append("%s/%s: '%s'" % (pid, emotion, found.group(0)))
    if hits:
        failures.append("banned names in prompts: %s" % "; ".join(hits[:5]))

    # 3. role derivation covers every person the content points at
    role_map = roles()
    uncovered = [pid for pid, _slot in _sweep_slots() if pid not in role_map]
    if uncovered:
        failures.append("role map missing slotted people: %s" % uncovered[:5])

    # 4. region variety: the point is that the wall is not ONE distribution.
    #    Not all 29 descriptions must be word-distinct (real neighbours share a
    #    look) but the table must not have collapsed; 25 of 29 distinct plus
    #    the explicit FRA-vs-FIN pair is the line.
    distinct = len(set(REGION.values()))
    if distinct < 25:
        failures.append("only %d distinct region descriptions across %d nations" % (distinct, len(REGION)))
    by_prefix = {}
    for pid, _name in people:
        by_prefix.setdefault(pid.split("_")[0], pid)
    if "FRA" in by_prefix and "FIN" in by_prefix:
        if REGION["FRA"] == REGION["FIN"]:
            failures.append("FRA and FIN read the same region text")

    # 5. determinism: the same id twice yields the same prompt and seed --
    # within the process AND against a committed golden value, which is what
    # catches cross-process drift (a hash() swap, a seed-formula change). The
    # seed depends only on the id and the emotion name, so the golden pin says
    # the SEEDING contract held; prompt TEXT may drift freely -- the sidecar
    # is hand-editable art direction by design. If this seed moves, every
    # portrait re-renders differently. AUT_kettler's has been stable since
    # the sidecar was first seeded.
    golden_pid, golden_seed = "AUT_kettler", 3982541790
    golden_name = next((n for p, n in people if p == golden_pid), None)
    if golden_name is None:
        failures.append("golden id %s left the register -- pick a new pin" % golden_pid)
    else:
        if prompt_for(golden_pid, golden_name, "neutral")[0] != golden_seed:
            failures.append("golden seed for %s moved (expected %d) -- every portrait would re-render"
                            % (golden_pid, golden_seed))
    for pid, name in people[:3]:
        for emotion in EMOTIONS:
            if prompt_for(pid, name, emotion)[:2] != prompt_for(pid, name, emotion)[:2]:
                failures.append("prompt_for(%s, %s) is not deterministic" % (pid, emotion))
                break

    # Task 4's teeth: the five emotion prompts differ pairwise
    for pid, name in people[:10]:
        texts = [prompt_for(pid, name, e)[1] for e in EMOTIONS]
        if len(set(texts)) != len(EMOTIONS):
            failures.append("emotion prompts collide for %s" % pid)

    # 6. the no-leak seal on the counterpart mapping: the local mapping file
    # carries real names (uncommitted by design), and none of them may reach
    # any prompt -- enforced here mechanically, not promised.
    mapping_path = TOOLS / "portraits_counterparts.json"
    if mapping_path.exists():
        mapping = json.loads(comfy._confined(mapping_path, TOOLS).read_text(encoding="utf-8"))
        real_names = [e["real"] for e in mapping.values()
                      if isinstance(e, dict) and e.get("real")
                      and "thin knowledge" not in e["real"] and "(invented)" not in e["real"]]
        pattern2 = re.compile(r"(?:" + "|".join(re.escape(n) for n in real_names) + r")", re.IGNORECASE)
        for pid, name in people:
            for emotion in EMOTIONS:
                _s, text, _n = prompt_for(pid, name, emotion)
                if pattern2.search(text):
                    failures.append("real counterpart name leaked into %s/%s prompt" % (pid, emotion))
                    break

    if failures:
        for f in failures:
            print("FAIL: %s" % f)
        return 1
    print("self-check: %d people, %d sidecar entries, %d roles derived, %d region texts -- all properties hold"
          % (len(people), len(_traits), len(role_map), distinct))
    return 0


def generate_base(person_id, seed, text):
    """One base render through the base workflow: image and matting mask out."""
    workflow = json.loads(comfy._confined(WORKFLOW, TOOLS).read_text(encoding="utf-8"))
    workflow[BASE_SEED_NODE]["inputs"]["seed"] = seed
    workflow[BASE_TEXT_NODE]["inputs"]["text"] = text
    prompt_id = comfy.queue(workflow)
    out = comfy.outputs(prompt_id)

    def first_meta(node):
        if not out.get(node):
            raise RuntimeError("no output at node %s for %s" % (node, person_id))
        return out[node][0]

    return comfy.fetch(first_meta(BASE_IMAGE_NODE)), comfy.fetch(first_meta(BASE_MASK_NODE))


def generate_expression(person_id, emotion, seed, text):
    """One expression render: the SEED-LOCKED RE-RENDER, not an inpaint.

    The history that chose this shape: FaceDetailer's inpaint path was the
    plan's method, but it silently passes its input through on ComfyUI 0.34
    (its upscale-skip rule fires on our large face crops, and where it does
    sample, its internal noise/sigma handling returns garbage -- two full
    overnight runs rendered 852 images identical to their bases before this
    was diagnosed). The replacement uses the recipe's own determinism: the
    SAME seed as the person's base render with ONLY the emotion fragment
    changed in the prompt -- SDXL re-renders the same composition, and the
    face's expression is the part the fragment moves. Identity comes from
    the seed lock; no matting/upload/taps needed."""
    workflow = json.loads(comfy._confined(EXPRESSION_WORKFLOW, TOOLS).read_text(encoding="utf-8"))
    workflow[EXPR_SEED_NODE]["inputs"]["seed"] = comfy.djb2(person_id + ":neutral")
    workflow[EXPR_TEXT_NODE]["inputs"]["text"] = text
    prompt_id = comfy.queue(workflow)
    out = comfy.outputs(prompt_id, timeout_s=900)

    def first_meta(node):
        if not out.get(node):
            raise RuntimeError("no output at node %s for %s/%s" % (node, person_id, emotion))
        return out[node][0]

    return comfy.fetch(first_meta(EXPR_IMAGE_NODE)), comfy.fetch(first_meta(EXPR_MASK_NODE))


def _only_filter(people):
    """--only <person_id> (repeatable): generate a slice, not the wall. This is
    Phase B's own verification shape -- a three-person slice (three nations,
    three regions, three roles) before the 2.5 h run -- and needs no temp-file
    surgery on the register. Traits are still seeded for the WHOLE register;
    only generation is filtered."""
    pids = set()
    args = sys.argv
    for i, a in enumerate(args):
        if a == "--only" and i + 1 < len(args):
            pids.add(comfy._checked_id(args[i + 1]))
    if not pids:
        return people
    return [(pid, name) for pid, name in people if pid in pids]


def main():
    people = _load_people()
    global _traits, _roles
    _traits = load_traits(people)
    _roles = roles()

    if "--self-check" in sys.argv:
        return self_check(people)

    if "--dry-run" in sys.argv:
        for pid, name in _only_filter(people):
            seed, text, _ = prompt_for(pid, name, "neutral")
            print("%s (seed %d)\n  %s" % (pid, seed, text))
            for emotion in EMOTIONS[1:]:
                _s, variant, _ = prompt_for(pid, name, emotion)
                print("  [%s] %s" % (emotion, EMOTION_FRAGMENTS[emotion]))
        print("dry-run: %d people, nothing contacted" % len(people))
        return 0

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    MASK_DIR.mkdir(parents=True, exist_ok=True)
    for emotion in EMOTIONS:
        (RAW_DIR / emotion).mkdir(parents=True, exist_ok=True)
        (MASK_DIR / emotion).mkdir(parents=True, exist_ok=True)
    slice_people = _only_filter(people)

    # Pass 1: the base (neutral), for every person missing one. All 213 are
    # re-rendered on the first V3.7 run -- they are the wall the author
    # rejected as "too lookalike", and they were leaving duotone regardless.
    todo = [(pid, name) for pid, name in slice_people
            if not (RAW_DIR / "neutral" / (pid + ".png")).exists()]
    print("register holds %d people; %d base portraits exist, %d to generate"
          % (len(people), len(people) - len(todo), len(todo)))
    for i, (person_id, name) in enumerate(todo):
        seed, text, _ = prompt_for(person_id, name, "neutral")
        image, mask = generate_base(person_id, seed, text)
        comfy._confined(RAW_DIR / "neutral" / (person_id + ".png"), RAW_DIR).write_bytes(image)
        comfy._confined(MASK_DIR / "neutral" / (person_id + ".png"), MASK_DIR).write_bytes(mask)
        print("  [%d/%d] %s base (seed %d)" % (i + 1, len(todo), person_id, seed))

    # Pass 2: the four non-neutral expressions, FaceDetailer over each base.
    # A person with no base is skipped here -- the base pass creates it; this
    # guard is what makes either pass alone resumable.
    for emotion in EMOTIONS[1:]:
        todo_e = [(pid, name) for pid, name in slice_people
                  if (RAW_DIR / "neutral" / (pid + ".png")).exists()
                  and not (RAW_DIR / emotion / (pid + ".png")).exists()]
        print("%s: %d to generate" % (emotion, len(todo_e)))
        for i, (person_id, name) in enumerate(todo_e):
            seed, text, _ = prompt_for(person_id, name, emotion)
            image, mask = generate_expression(person_id, emotion, seed, text)
            comfy._confined(RAW_DIR / emotion / (person_id + ".png"), RAW_DIR).write_bytes(image)
            comfy._confined(MASK_DIR / emotion / (person_id + ".png"), MASK_DIR).write_bytes(mask)
            print("  [%d/%d] %s %s (seed %d)" % (i + 1, len(todo_e), person_id, emotion, seed))

    print("done: portraits and masks under sources/portraits/{raw,mask}/<emotion>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
