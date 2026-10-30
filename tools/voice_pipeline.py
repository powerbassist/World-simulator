"""V5.2 d, the voice pipeline (docs/design/v5.2-d-spec.md section 6). Dev-only, stdlib.

Every voiced line is generated ONCE, here, never while the game runs: each event's
`speaker_line` and each voice archetype's own line set, on designed voices (one per
archetype, never a real person's -- the likeness ruling), into
assets/audio/voice/<archetype>/<line_id>.ogg, loudness-normalised to one target so
the lines sit together.

**Dry-run is the default and contacts nothing.** It lists every clip it would make
with its characters and text hash, each with a status:
  new           -- no clip yet;
  stale         -- a clip exists, but its text changed (the manifest's hash differs);
  ok            -- a clip exists for this exact text;
  not-voiceable -- the line holds a variable, a printf slot or a glossary mark: only
                   variable-free lines are voiced, so it is never a job;
  no-voice      -- its archetype is missing or has no generator voice id: this script
                   never designs or picks a voice, it uses the one the table names.
and prints the totals under BOTH readings of who speaks an event line (the volume
call, see voices_for()). A data file not written yet is zero clips, said so.

**The paid path is `--run`, and it is gated by shape, not trust:** it needs --floor
(characters the allowance must keep) and --max-chars (this batch's ceiling), with no
defaults; it reads the remaining allowance first and refuses a batch that would cross
the floor, re-checks before every clip, and stops at the first error. Each clip is
written with its manifest row and its REUSE.toml annotation together. No paid batch
runs without the parent's GO, who asks the author: it spends the author's credits.

The key: ELEVENLABS_API_KEY from the environment only, sent as a header, never in
argv, never printed or logged; an error prints the status code and the line id only.

The manifest, assets/audio/voice/manifest.json, is playback's contract: flat JSON,
"<archetype>/<line_id>" -> {archetype, line_id, file, text_sha256, chars, voice_id,
model, date, source}. Godot reads it to find a clip and to know it matches the text.

  python tools/voice_pipeline.py                 dry-run over the repo
  python tools/voice_pipeline.py --every         dry-run, the per-speaker reading
  python tools/voice_pipeline.py --run --floor 2000 --max-chars 9000 [--only ARCH]
  python tools/voice_pipeline.py --design        dry-run of the archetype voices to design
  python tools/voice_pipeline.py --design --run --floor 2000 --max-chars 3000
  python tools/voice_pipeline.py --selftest      no network; CI runs it
"""

import argparse
import base64
import datetime
import hashlib
import http.client
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
API = "https://api.elevenlabs.io/v1"
KEY_ENV = "ELEVENLABS_API_KEY"
## The model sets the credit rate per character, so it is the parent's and the
## author's call, named here once (the PR body says which), never picked per run.
MODEL_ID = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_128"
## One loudness target for every line (EBU R128-style integrated loudness, LUFS).
LOUDNORM = "loudnorm=I=-16:TP=-1.5:LRA=11"
PLAN = "ElevenLabs Starter, commercial licence bought 2026-10-19"
VOICE_DIR = "assets/audio/voice"
MANIFEST = VOICE_DIR + "/manifest.json"
ARCHETYPES = "data/voices/archetypes.json"
## Only variable-free lines are voiced (section 6): a {{variable}}, a printf slot or
## a glossary mark would make the clip say something other than the shown text.
## A printf slot with flags, width or precision too ("%.1f", "%5d"), #187 QA.
## No space among the flags: "100% sure" is prose, not a "% s" slot (pass 1).
UNVOICEABLE = re.compile(r"\{\{|%[-+#0-9.]*[sdif%]|\[g=")
## An archetype id and a line id become a path: letters, digits, '_', '.', '-' only,
## and never '..', so data can never write outside VOICE_DIR.
SAFE_ID = re.compile(r"^(?!.*\.\.)[A-Za-z0-9_.-]+$")
## A generator voice id goes into the URL path: ElevenLabs' ids are plain
## alphanumerics, so anything else is refused before a request is made (#187 QA).
SAFE_VOICE_ID = re.compile(r"^[A-Za-z0-9]{1,64}$")
## Where the paid audio of a clip whose conversion failed is kept (gitignored), named
## by its key and text hash, so the next run converts it again instead of paying twice.
RECOVER_DIR = "reports/voice_failed"
## --design (the archetype voices). The design model is ElevenLabs' text-to-voice one,
## not the speech MODEL_ID. The preview text is the archetype's own lines, which the
## API takes at 100 to 1000 characters; a description under 20 characters is not a
## prompt. The chosen preview's audio is kept (gitignored) for the author to hear.
DESIGN_MODEL = "eleven_multilingual_ttv_v2"
DESIGN_TEXT_MIN = 100
DESIGN_TEXT_MAX = 1000
DESIGN_DESC_MIN = 20
DESIGN_DIR = "reports/voice_design"
DESIGN_HEAD = "# Designed voices (tools/voice_pipeline.py --design), never a real person's voice:"


class PipelineError(Exception):
    pass


# --- Reading ---------------------------------------------------------------------------

def _json(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def read_sources(root: Path) -> dict:
    """The archetype table, the people by kind, and the events that carry a line."""
    table = _json(root / ARCHETYPES) or {}
    people = []
    for f in sorted((root / "data" / "people").glob("*.json")):
        people.extend((_json(f) or {}).get("people", []))
    # Everyone the data names in an office (heads of state and government, party
    # leaders, pretenders): with OFFICE_KIND's people, the possible holders.
    holders = set()
    for d in ("nations", "parties"):
        for f in sorted((root / "data" / d).glob("*.json")):
            _holder_ids(_json(f), holders)
    events = []
    for f in sorted((root / "data" / "events").glob("*.json")):
        for ev in (_json(f) or {}).get("events", []):
            if str(ev.get("speaker_line", "")).strip():
                events.append(ev)
    return {
        "has_table": (root / ARCHETYPES).exists(),
        "archetypes": {str(a.get("id", "")): a for a in table.get("archetypes", [])},
        "defaults": table.get("defaults", {}),
        "people": people,
        "holders": holders,
        "events": events,
    }


def _holder_ids(node, out: set) -> None:
    """Every value of a `person` or `*person_id` key, anywhere in a data file."""
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, str) and (k == "person" or k.endswith("person_id")) and v:
                out.add(v)
            else:
                _holder_ids(v, out)
    elif isinstance(node, list):
        for v in node:
            _holder_ids(v, out)


# The kind whose people may hold an office or head a foreign government: an office's
# default falls back to this kind's (src/core/voices.gd), and a challenge installs a
# party's own member as its leader.
OFFICE_KIND = "politician"


def voices_for(speaker: dict, src: dict, every: bool) -> list:
    """The archetypes an event line is voiced in -- the one place this is decided.

    The default reading (every=False): the speaker kind's default archetype, one clip a
    line, the spec's own volume (about 112 event lines). `every`: one clip for every
    archetype a qualifying speaker may carry (a person's own `voice`, else their kind's
    default), since the face resolves at delivery and may be any of them -- over EVERY
    nation's people, on purpose (#187 QA asked): any nation may be the played one, and
    the speaker is drawn from the played nation's people. A speaker that
    is not a kind (an office, the evidence's person, a foreign head) reads its own
    `defaults` key: "office:<office>", "evidence_person", "foreign_head".

    An office or a foreign head is a PERSON at delivery (Voices.speaker_archetype:
    a woman prime minister speaks in her own voice, #205), so `every` voices those
    lines in every possible holder's archetype too (QA on #205, against "Une par
    visage"): OFFICE_KIND's people, anyone the data names in an office and, for an
    office, anyone with a party (a leadership challenge can make any member of any
    kind the party's leader, then the prime minister: QA on #206), each
    their own `voice` else their kind's default, beside the form's own default for a
    vacant office. The evidence's person, the exposure's witness, may be anyone of any
    kind, so its line is voiced in every person's archetype (the parent, 2026-10-30).
    """
    defaults = src["defaults"]
    if "kind" in speaker:
        kind = str(speaker["kind"])
        if not every:
            return [defaults[kind]] if defaults.get(kind) else []
        ids = {str(p.get("voice") or defaults.get(kind) or "") for p in src["people"] if p.get("kind") == kind}
        return sorted(i for i in ids if i)
    if "office" in speaker:
        key = "office:" + str(speaker["office"])
    elif speaker.get("evidence_person"):
        key = "evidence_person"
    elif speaker.get("foreign_head"):
        key = "foreign_head"
    else:
        return []
    if every:
        ids = {str(p.get("voice") or defaults.get(str(p.get("kind", ""))) or "") for p in src["people"]
               if key == "evidence_person" or p.get("kind") == OFFICE_KIND or p.get("id") in src.get("holders", ())
               or (key.startswith("office:") and p.get("party_id"))}
        ids.add(str(defaults.get(key) or ""))
        return sorted(i for i in ids if i)
    return [defaults[key]] if defaults.get(key) else []


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def jobs(src: dict, manifest: dict, every: bool) -> list:
    """Every clip the data asks for, each with its status (see the header)."""
    out = []

    def add(arch: str, line_id: str, text: str, source: str):
        key = "%s/%s" % (arch, line_id)
        row = src["archetypes"].get(arch, {})
        sha = text_hash(text)
        if UNVOICEABLE.search(text):
            status = "not-voiceable"
        elif not str(row.get("voice_id", "")).strip():
            status = "no-voice"  # never written, so its id never becomes a path
        elif not SAFE_ID.match(arch) or not SAFE_ID.match(line_id) \
                or not SAFE_VOICE_ID.match(str(row.get("voice_id", ""))):
            status = "bad-id"
        elif key not in manifest:
            status = "new"
        elif manifest[key].get("text_sha256") != sha:
            status = "stale"
        else:
            status = "ok"
        out.append({"key": key, "archetype": arch, "line_id": line_id, "text": text, "source": source,
                    "chars": len(text), "sha": sha, "status": status, "voice_id": str(row.get("voice_id", "")),
                    "file": "%s/%s/%s.ogg" % (VOICE_DIR, arch, line_id)})

    for ev in src["events"]:
        line = str(ev["speaker_line"])
        archs = voices_for(ev.get("speaker", {}), src, every)
        if not archs:
            add("(none)", "event.%s" % ev.get("id", ""), line, "events/%s.speaker_line" % ev.get("id", ""))
        for arch in archs:
            add(arch, "event.%s" % ev.get("id", ""), line, "events/%s.speaker_line" % ev.get("id", ""))
    for arch, row in sorted(src["archetypes"].items()):
        for line_id, text in sorted(row.get("lines", {}).items()):
            add(arch, str(line_id), str(text), "voices/%s.lines.%s" % (arch, line_id))
    return out


def _todo(rows: list) -> list:
    return [r for r in rows if r["status"] in ("new", "stale")]


# --- Dry run --------------------------------------------------------------------------

def dry_run(root: Path, every: bool, only: str) -> int:
    src = read_sources(root)
    manifest = _json(root / MANIFEST) or {}
    rows = [r for r in jobs(src, manifest, every) if not only or r["archetype"] == only]
    if not src["has_table"]:
        print("%s: not written yet -- no archetype, so no voice (Content's)" % ARCHETYPES)
    print("events with a speaker_line: %d" % len(src["events"]))
    for r in rows:
        print("%-13s %-28s %-40s %4d  %s  %s" % (r["status"], r["archetype"], r["line_id"], r["chars"],
                                               r["sha"][:12], r["text"][:60]))
    for label, flag in (("kind-default archetype only", False), ("every archetype a speaker may carry", True)):
        todo = _todo([r for r in jobs(src, manifest, flag) if not only or r["archetype"] == only])
        print("%s: %d clips to make, %d characters" % (label, len(todo), sum(r["chars"] for r in todo)))
    print("ffmpeg: %s" % ("found" if shutil.which("ffmpeg") else "NOT FOUND (needed by --run)"))
    print("%s: %s" % (KEY_ENV, "set" if os.environ.get(KEY_ENV) else "not set"))
    return 0


# --- The paid path ----------------------------------------------------------------------

def _request(method: str, url: str, key: str, body: bytes = None, accept: str = "") -> tuple:
    headers = {"xi-api-key": key, "Accept": accept or ("application/json" if method == "GET" else "audio/mpeg")}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    # URLError, a timeout and a reset are all OSError; a body cut short is an
    # HTTPException. Each is "no answer", a stop with a reason, never a traceback.
    except (OSError, http.client.HTTPException):
        return 0, b""


def account(key: str) -> dict:
    """The account's own counts: credits left this period and voice slots free."""
    status, body = _request("GET", API + "/user/subscription", key)
    if status != 200:
        raise PipelineError("subscription: HTTP %d" % status)
    try:
        sub = json.loads(body)
        return {"left": int(sub["character_limit"]) - int(sub["character_count"]),
                "slots_free": int(sub["voice_limit"]) - int(sub["voice_slots_used"])}
    except (ValueError, KeyError, TypeError) as e:
        raise PipelineError("subscription: not the account's count (%s)" % type(e).__name__)


def allowance(key: str) -> int:
    """Characters left this period, from the account's own count."""
    return account(key)["left"]


def kept_path(root: Path, r: dict) -> Path:
    """Where a clip's paid audio waits after a failed conversion: named by its key, its
    voice and its text, so it is reused only for the same line in the same voice."""
    return root / RECOVER_DIR / ("%s.%s.%s.mp3" % (r["key"].replace("/", "__"), r["voice_id"], r["sha"][:12]))


def speak(key: str, voice_id: str, text: str) -> bytes:
    url = "%s/text-to-speech/%s?output_format=%s" % (API, voice_id, OUTPUT_FORMAT)
    status, body = _request("POST", url, key, json.dumps({"text": text, "model_id": MODEL_ID}).encode("utf-8"))
    if status != 200:
        raise PipelineError("HTTP %d" % status)
    return body


def to_ogg(mp3: bytes, out: Path) -> None:
    """One pass: loudness-normalised to LOUDNORM, Vorbis in an Ogg."""
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.mp3"
        src.write_bytes(mp3)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-af", LOUDNORM,
                        "-c:a", "libvorbis", "-q:a", "5", str(out)], check=True)


def reuse_block(row: dict, date: str) -> str:
    """One REUSE.toml annotation for one clip (D11): its generator, plan, model, voice,
    date and the text it says. `.ogg*` so the editor's .import sibling is covered too."""
    return "\n".join([
        "[[annotations]]",
        "# Voice clip: %s, model %s, designed voice %s (archetype %s), %s; says %s (sha256 %s)." % (
            PLAN, MODEL_ID, row["voice_id"], row["archetype"], date, row["source"], row["sha"][:12]),
        'path = "%s*"' % row["file"],
        'precedence = "override"',
        'SPDX-FileCopyrightText = "2026 powerbassist"',
        'SPDX-License-Identifier = "CC-BY-NC-4.0"',
    ])


def annotate(reuse: Path, row: dict, date: str) -> None:
    """Add the clip's annotation, or replace the one a stale clip had: one per path."""
    raw = reuse.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")
    blocks = text.split("\n\n")
    marker = 'path = "%s*"' % row["file"]
    blocks = [b for b in blocks if marker not in b]
    text = "\n\n".join(blocks).rstrip("\n") + "\n\n" + reuse_block(row, date) + "\n"
    with open(reuse, "w", encoding="utf-8", newline=nl) as f:
        f.write(text)


def run(root: Path, every: bool, only: str, floor: int, max_chars: int, key: str, date: str,
        allowance_fn=allowance, speak_fn=speak, convert_fn=to_ogg) -> int:
    src = read_sources(root)
    manifest_path = root / MANIFEST
    manifest = _json(manifest_path) or {}
    rows = [r for r in jobs(src, manifest, every) if not only or r["archetype"] == only]
    bad = [r for r in rows if r["status"] in ("not-voiceable", "bad-id")]
    if bad:
        for r in bad:
            print("%s: %s" % (r["status"], r["key"]))
        raise PipelineError("%d line(s) not voiceable or with an unsafe id; fix the data first" % len(bad))
    todo = _todo(rows)
    # A clip whose audio was kept from a failed conversion costs nothing this time.
    planned = sum(r["chars"] for r in todo if not kept_path(root, r).exists())
    if planned > max_chars:
        raise PipelineError("%d characters planned, over --max-chars %d (use --only)" % (planned, max_chars))
    left = allowance_fn(key)
    if left - planned < floor:
        raise PipelineError("%d characters left, %d planned: the floor %d would be crossed" % (left, planned, floor))
    used = 0
    stopped = False
    for r in todo:
        # Read again before every clip: credits spent elsewhere meanwhile (the author's
        # own use of the account) count against the floor too.
        if allowance_fn(key) - r["chars"] < floor:
            print("stopped at the floor before %s" % r["key"])
            stopped = True
            break
        kept = kept_path(root, r)
        if kept.exists():
            audio = kept.read_bytes()  # paid for by an earlier run whose conversion failed
        else:
            try:
                audio = speak_fn(key, r["voice_id"], r["text"])
            except PipelineError as e:
                raise PipelineError("%s: %s" % (r["key"], e))
            used += r["chars"]
        try:
            convert_fn(audio, root / r["file"])
        except (subprocess.CalledProcessError, OSError) as e:
            kept.parent.mkdir(parents=True, exist_ok=True)
            kept.write_bytes(audio)
            raise PipelineError("%s: conversion failed (%s); the paid audio is kept in %s" % (
                r["key"], type(e).__name__, kept.relative_to(root).as_posix()))
        kept.unlink(missing_ok=True)
        manifest[r["key"]] = {"archetype": r["archetype"], "line_id": r["line_id"], "file": r["file"],
                              "text_sha256": r["sha"], "chars": r["chars"], "voice_id": r["voice_id"],
                              "model": MODEL_ID, "date": date, "source": r["source"]}
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(manifest_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(manifest, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
        annotate(root / "REUSE.toml", r, date)
        print("made %s (%d characters)" % (r["key"], r["chars"]))
    print("%d characters used of %d left" % (used, left))
    # A batch the floor cut short did not make what was asked (#187 QA): not 0.
    return 1 if stopped else 0


# --- Designing the archetype voices (--design) -------------------------------------------
#
# The author's call (2026-10-30): the tool designs the 14 archetype voices with the
# author's key, from each archetype's `description` (Content's), in ElevenLabs Voice
# Design. Design charges the preview text's characters, once per design call, and each
# saved voice takes a voice slot, so the batch is held to --max-chars and the floor like
# the clips, and refused outright when the slots are short. The first of the returned
# previews is saved (the tool decides, as the author asked); its audio is kept in
# DESIGN_DIR for the author to hear. Each voice id is written into the table as soon as
# it exists, so a batch stopped half-way keeps what it paid for.

def design_jobs(table: dict) -> list:
    """Every archetype with its design status: designed, to-design, no-description
    (Content has not written its prompt) or short-preview (its own lines make fewer
    than the 100 characters the API needs to preview a voice)."""
    out = []
    for row in table.get("archetypes", []):
        arch = str(row.get("id", ""))
        description = str(row.get("description", "")).strip()
        text = " ".join(str(t) for t in row.get("lines", {}).values())[:DESIGN_TEXT_MAX]
        if str(row.get("voice_id", "")).strip():
            status = "designed"
        elif not SAFE_ID.match(arch):
            status = "bad-id"
        elif not DESIGN_DESC_MIN <= len(description) <= DESIGN_TEXT_MAX:
            status = "no-description"
        elif len(text) < DESIGN_TEXT_MIN:
            status = "short-preview"
        else:
            status = "to-design"
        # Seven hex digits: a seed under 2**28 fits any integer the API may take (pass 1).
        out.append({"id": arch, "status": status, "description": description, "text": text,
                    "chars": len(text), "seed": int(text_hash(arch)[:7], 16),
                    "sha": text_hash(description + "\n" + text)})
    return out


def design_dry_run(root: Path) -> int:
    rows = design_jobs(_json(root / ARCHETYPES) or {})
    for r in rows:
        print("%-15s %-24s %4d" % (r["status"], r["id"], r["chars"]))
    todo = [r for r in rows if r["status"] == "to-design"]
    print("--design: %d voices to design, %d preview characters, %d voice slots" % (
        len(todo), sum(r["chars"] for r in todo), len(todo)))
    print("%s: %s" % (KEY_ENV, "set" if os.environ.get(KEY_ENV) else "not set"))
    return 0


def design_voice(key: str, description: str, text: str, seed: int) -> tuple:
    """Previews a voice; returns the first preview's generated id and its audio."""
    body = json.dumps({"voice_description": description, "text": text, "model_id": DESIGN_MODEL,
                       "seed": seed}).encode("utf-8")
    status, raw = _request("POST", API + "/text-to-voice/design", key, body, accept="application/json")
    if status != 200:
        raise PipelineError("design: HTTP %d" % status)
    try:
        first = json.loads(raw)["previews"][0]
        return str(first["generated_voice_id"]), base64.b64decode(first["audio_base_64"])
    except (ValueError, KeyError, IndexError, TypeError) as e:
        raise PipelineError("design: not a preview (%s)" % type(e).__name__)


def save_voice(key: str, name: str, description: str, generated_id: str, labels: dict) -> str:
    """Saves a preview as a voice in the account (one slot); returns its voice id."""
    body = json.dumps({"voice_name": name, "voice_description": description,
                       "generated_voice_id": generated_id, "labels": labels}).encode("utf-8")
    status, raw = _request("POST", API + "/text-to-voice", key, body, accept="application/json")
    if status != 200:
        raise PipelineError("save: HTTP %d (generated voice %s)" % (status, generated_id))
    try:
        return str(json.loads(raw)["voice_id"])
    except (ValueError, KeyError, TypeError) as e:
        raise PipelineError("save: no voice id (%s; generated voice %s)" % (type(e).__name__, generated_id))


def write_voice(root: Path, arch: str, voice_id: str, date: str) -> None:
    """The voice id and its provenance into the table, and one line into REUSE.toml."""
    path = root / ARCHETYPES
    raw = path.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    table = json.loads(raw)
    for row in table["archetypes"]:
        if row.get("id") == arch:
            row["voice_id"] = voice_id
            row["provenance"] = ("Designed archetype, never a real person's voice: ElevenLabs Voice Design "
                                 "(model %s), %s, from the description above, %s." % (DESIGN_MODEL, PLAN, date))
    with open(path, "w", encoding="utf-8", newline=nl) as f:
        f.write(json.dumps(table, indent=2, ensure_ascii=False) + "\n")
    reuse = root / "REUSE.toml"
    raw = reuse.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    blocks = raw.replace("\r\n", "\n").rstrip("\n").split("\n\n")
    line = "# %s: voice %s, ElevenLabs Voice Design (model %s), %s, %s." % (arch, voice_id, DESIGN_MODEL, PLAN, date)
    for i, block in enumerate(blocks):
        if block.startswith(DESIGN_HEAD):
            kept = [x for x in block.split("\n") if not x.startswith("# %s:" % arch)]
            blocks[i] = "\n".join(kept + [line])
            break
    else:
        blocks.append(DESIGN_HEAD + "\n" + line)
    with open(reuse, "w", encoding="utf-8", newline=nl) as f:
        f.write("\n\n".join(blocks) + "\n")


def _pending(root: Path, r: dict) -> Path:
    """A design paid for whose save failed: reused by the next run while the
    archetype's description and lines are unchanged (pass 1)."""
    return root / DESIGN_DIR / ("%s.json" % r["id"])


def _pending_row(root: Path, r: dict) -> dict:
    """The kept design while the archetype is unchanged; carries `voice_id` too once
    the save went through and only the table write is left (QA #201 R(b))."""
    kept = _json(_pending(root, r)) or {}
    return kept if kept.get("sha") == r["sha"] else {}


def _pending_id(root: Path, r: dict) -> str:
    return str(_pending_row(root, r).get("generated_voice_id", ""))


def design_run(root: Path, key: str, floor: int, max_chars: int, date: str,
               account_fn=account, design_fn=design_voice, save_fn=save_voice, only: str = "") -> int:
    rows = [r for r in design_jobs(_json(root / ARCHETYPES) or {}) if not only or r["id"] == only]
    bad = [r for r in rows if r["status"] in ("no-description", "short-preview", "bad-id")]
    if bad:
        for r in bad:
            print("%s: %s" % (r["status"], r["id"]))
        raise PipelineError("%d archetype(s) cannot be designed; fix the data first" % len(bad))
    todo = [r for r in rows if r["status"] == "to-design"]
    planned = sum(r["chars"] for r in todo if not _pending_id(root, r))
    if planned > max_chars:
        raise PipelineError("%d preview characters planned, over --max-chars %d" % (planned, max_chars))
    acc = account_fn(key)
    if acc["slots_free"] < len(todo):
        raise PipelineError("%d voice slot(s) free, %d voices to design" % (acc["slots_free"], len(todo)))
    if acc["left"] - planned < floor:
        raise PipelineError("%d characters left, %d planned: the floor %d would be crossed" % (
            acc["left"], planned, floor))
    used = 0
    for r in todo:
        kept = _pending_row(root, r)
        generated = str(kept.get("generated_voice_id", ""))
        # Only a new design spends characters: a kept one is saved for free, so the floor
        # does not stop it (QA #201 R(a)).
        if not generated and account_fn(key)["left"] - r["chars"] < floor:
            print("stopped at the floor before %s" % r["id"])
            return 1
        if not generated:
            try:
                generated, audio = design_fn(key, r["description"], r["text"], r["seed"])
            except PipelineError as e:
                raise PipelineError("%s: %s" % (r["id"], e))
            used += r["chars"]
            heard = root / DESIGN_DIR / ("%s.mp3" % r["id"])
            heard.parent.mkdir(parents=True, exist_ok=True)
            heard.write_bytes(audio)
            _pending(root, r).write_text(json.dumps({"generated_voice_id": generated, "sha": r["sha"]}),
                                         encoding="utf-8")
        voice_id = str(kept.get("voice_id", ""))
        if not voice_id:
            try:
                voice_id = save_fn(key, "Nation Simulator %s" % r["id"], r["description"], generated,
                                   {"project": "nation-simulator", "archetype": r["id"]})
            except PipelineError as e:
                raise PipelineError("%s: %s; the design is kept, the next run saves it" % (r["id"], e))
            if not SAFE_VOICE_ID.match(voice_id):
                raise PipelineError("%s: the saved voice id %r is not plain alphanumeric; it is in the account, "
                                    "not in the table" % (r["id"], voice_id))
            # Kept before the table write: a failed write must not make the rerun save
            # the same design a second time (a duplicate voice, or a refusal).
            _pending(root, r).write_text(json.dumps({"generated_voice_id": generated, "sha": r["sha"],
                                                     "voice_id": voice_id}), encoding="utf-8")
        try:
            write_voice(root, r["id"], voice_id, date)
        except (OSError, ValueError, KeyError) as e:
            raise PipelineError("%s: voice %s is saved but the table write failed (%s); the next run writes it"
                                % (r["id"], voice_id, type(e).__name__))
        _pending(root, r).unlink(missing_ok=True)
        print("designed %s (%d characters)" % (r["id"], r["chars"]))
    print("%d preview characters used of %d left" % (used, acc["left"]))
    return 0


# --- Selftest ---------------------------------------------------------------------------

def selftest() -> int:
    fails = []
    secret = "sk-SELFTEST-NEVER-PRINT"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "data" / "events").mkdir(parents=True)
        (root / "data" / "people").mkdir(parents=True)
        (root / "data" / "voices").mkdir(parents=True)
        events = [
            {"id": "strike", "speaker": {"kind": "union_leader"}, "speaker_line": "The depots are out."},
            {"id": "plant", "speaker": {"kind": "executive"}, "speaker_line": "We close in March."},
            {"id": "named", "speaker": {"kind": "union_leader"}, "speaker_line": "{{president}} must act."},
            {"id": "crisis", "speaker": {"office": "head_of_government"}, "speaker_line": "The cabinet holds."},
            {"id": "mute", "speaker": {"kind": "judge"}, "speaker_line": "Order."},
        ]
        (root / "data" / "events" / "x.json").write_text(json.dumps({"events": events}), encoding="utf-8")
        people = [{"id": "a", "kind": "union_leader"}, {"id": "b", "kind": "union_leader", "voice": "gruff"},
                  {"id": "c", "kind": "executive"}]
        (root / "data" / "people" / "AAA.json").write_text(json.dumps({"people": people}), encoding="utf-8")
        table = {"archetypes": [{"id": "union", "voice_id": "V1", "lines": {"greet": "You asked for me."}},
                                {"id": "gruff", "voice_id": "V2"}, {"id": "boss", "voice_id": "V3"},
                                {"id": "cabinet", "voice_id": ""}],
                 "defaults": {"union_leader": "union", "executive": "boss", "office:head_of_government": "cabinet"}}
        (root / ARCHETYPES).write_text(json.dumps(table), encoding="utf-8")
        (root / VOICE_DIR).mkdir(parents=True)
        manifest = {"boss/event.plant": {"text_sha256": text_hash("We close in April.")},
                    "union/greet": {"text_sha256": text_hash("You asked for me.")}}
        (root / MANIFEST).write_text(json.dumps(manifest), encoding="utf-8")
        (root / "REUSE.toml").write_bytes(b"version = 1\r\n")

        src = read_sources(root)
        status = {r["key"]: r["status"] for r in jobs(src, manifest, False)}
        want = {"union/event.strike": "new", "boss/event.plant": "stale", "union/event.named": "not-voiceable",
                "cabinet/event.crisis": "no-voice", "(none)/event.mute": "no-voice", "union/greet": "ok"}
        if status != want:
            fails.append("statuses: %r" % status)
        # QA on #205: under --every an office or a foreign head is voiced in every
        # possible holder's archetype -- OFFICE_KIND's own voices and defaults, anyone
        # the data names in an office (here an executive), and the office's default.
        holders = dict(src, people=src["people"] + [{"id": "p1", "kind": OFFICE_KIND},
                                                   {"id": "p2", "kind": OFFICE_KIND, "voice": "pol_f"},
                                                   {"id": "r1", "kind": "regional", "voice": "reg_f", "party_id": "x"}],
                       defaults=dict(src["defaults"], **{OFFICE_KIND: "pol_m"}), holders={"c"})
        got = voices_for({"office": "head_of_government"}, holders, True)
        # QA on #206: a party member of another kind can win the leadership, so an
        # office reaches their archetype too; a foreign head does not.
        if got != ["boss", "cabinet", "pol_f", "pol_m", "reg_f"]:
            fails.append("--every does not voice an office in every holder's archetype: %r" % got)
        if voices_for({"foreign_head": True}, holders, True) != ["boss", "pol_f", "pol_m"]:
            fails.append("--every does not voice a foreign head in every holder's archetype: %r"
                         % voices_for({"foreign_head": True}, holders, True))
        # The parent (2026-10-30): the witness may be anyone, so every person's archetype.
        holders["defaults"]["evidence_person"] = "union"
        if voices_for({"evidence_person": True}, holders, True) != ["boss", "gruff", "pol_f", "pol_m", "reg_f", "union"]:
            fails.append("--every does not voice the evidence's person in every archetype: %r"
                         % voices_for({"evidence_person": True}, holders, True))
        if voices_for({"office": "head_of_government"}, holders, False) != ["cabinet"]:
            fails.append("the default reading of an office is not its default alone")
        named = set()
        _holder_ids({"head_of_state": {"person": "x"}, "parties": [{"leader_person_id": "y"}], "name": "z"}, named)
        if named != {"x", "y"}:
            fails.append("the data's office holders are not read: %r" % named)
        bad_src = dict(src, archetypes=dict(src["archetypes"], **{"evil": {"voice_id": "V9", "lines": {"x/../../y": "Hi."}}}))
        if [r["status"] for r in jobs(bad_src, manifest, False) if r["archetype"] == "evil"] != ["bad-id"]:
            fails.append("a line id with '..' or '/' is not refused as a path")
        # #187 QA: an id that is not the generator's plain alphanumeric form is refused
        # before it reaches a URL path.
        evil_voice = dict(src, archetypes=dict(src["archetypes"], union={"voice_id": "../user", "lines": {}}))
        if [r["status"] for r in jobs(evil_voice, manifest, False) if r["key"] == "union/event.strike"] != ["bad-id"]:
            fails.append("a voice id with '../' is not refused before the URL")
        # #187 QA: any printf slot, not only the bare ones, makes a line unvoiceable.
        for slot in ("Up %.1f points.", "Rank %5d.", "Name %-3s."):
            if not UNVOICEABLE.search(slot):
                fails.append("UNVOICEABLE misses %r" % slot)
        if UNVOICEABLE.search("We are 100% sure."):
            fails.append("a plain per cent sign before a word reads as a printf slot")
        # The kept audio of one voice is never reused for another.
        row = {"key": "a/b", "sha": "0" * 64, "voice_id": "V1"}
        if kept_path(root, row) == kept_path(root, dict(row, voice_id="V2")):
            fails.append("the kept audio's name ignores the voice id")
        # A 200 whose body is not the subscription is a stop with a reason too.
        class Page:
            status = 200
            def __enter__(self):
                return self
            def __exit__(self, *a):
                return False
            def read(self):
                return b"<html>maintenance</html>"
        real_urlopen = urllib.request.urlopen
        urllib.request.urlopen = lambda *a, **k: Page()
        try:
            allowance(secret)
            fails.append("a page that is not the subscription read as an allowance")
        except PipelineError:
            pass
        except Exception as e:
            fails.append("%s escaped allowance()" % type(e).__name__)
        finally:
            urllib.request.urlopen = real_urlopen
        # #187 QA: a dropped connection is a stop with a reason, never a traceback.
        for exc in (TimeoutError("t"), ConnectionResetError("r"), http.client.IncompleteRead(b"")):
            def boom(*a, _exc=exc, **k):
                raise _exc
            urllib.request.urlopen = boom
            try:
                if _request("GET", API + "/user/subscription", secret)[0] != 0:
                    fails.append("%s did not read as no answer" % type(exc).__name__)
            except Exception as e:
                fails.append("%s escaped _request" % type(e).__name__)
            finally:
                urllib.request.urlopen = real_urlopen
        def broken(a, p):
            raise subprocess.CalledProcessError(1, "ffmpeg")
        every = sorted(r["key"] for r in jobs(src, manifest, True) if r["line_id"] == "event.strike")
        if every != ["gruff/event.strike", "union/event.strike"]:
            fails.append("the every reading: %r" % every)

        previous = os.environ.get(KEY_ENV)
        os.environ[KEY_ENV] = secret
        captured = io.StringIO()
        made = []
        try:
            with redirect_stdout(captured), redirect_stderr(captured):
                dry_run(root, False, "")
                try:
                    run(root, False, "", 0, 10000, secret, "2026-10-26",
                        allowance_fn=lambda k: 1000, speak_fn=lambda k, v, t: b"mp3",
                        convert_fn=lambda a, p: made.append(p))
                    fails.append("--run went ahead with a not-voiceable line")
                except PipelineError:
                    pass
                events[2]["speaker_line"] = "The union must act."
                (root / "data" / "events" / "x.json").write_text(json.dumps({"events": events}), encoding="utf-8")
                # The batch ceiling refuses before the account is asked or a clip is paid.
                calls = []
                try:
                    run(root, False, "", 0, 10, secret, "2026-10-26",
                        allowance_fn=lambda k: calls.append("allowance") or 1000,
                        speak_fn=lambda k, v, t: calls.append("speak") or b"mp3",
                        convert_fn=lambda a, p: made.append(p))
                    fails.append("--run went over --max-chars")
                except PipelineError as e:
                    if "--max-chars" not in str(e):
                        fails.append("the ceiling stopped with the wrong reason: %s" % e)
                if calls:
                    fails.append("the ceiling refused after calling %s" % calls)
                try:
                    run(root, False, "", 990, 10000, secret, "2026-10-26",
                        allowance_fn=lambda k: 1000, speak_fn=lambda k, v, t: b"mp3",
                        convert_fn=lambda a, p: made.append(p))
                    fails.append("--run crossed the floor")
                except PipelineError:
                    pass
                try:
                    run(root, False, "", 0, 10000, secret, "2026-10-26", allowance_fn=lambda k: 1000,
                        speak_fn=lambda k, v, t: b"mp3", convert_fn=broken)
                    fails.append("a failed conversion did not stop the batch")
                except PipelineError as e:
                    if "conversion failed" not in str(e):
                        fails.append("a failed conversion stopped with the wrong reason: %s" % e)
                # #187 QA: the paid audio of a failed conversion is kept, and the next
                # run converts it again without paying for it twice.
                kept = sorted((root / RECOVER_DIR).glob("*.mp3")) if (root / RECOVER_DIR).exists() else []
                if len(kept) != 1:
                    fails.append("a failed conversion kept %d paid clips, not 1" % len(kept))
                # The account drops to 900 before the third clip (spent elsewhere): the
                # per-clip read stops the batch there, two clips made. --max-chars 37 is
                # the batch's 56 characters less the kept clip's 19: the kept clip costs
                # nothing, so the ceiling does not count it.
                reads = [1000, 1000, 1000, 900]
                spoken = []
                code = run(root, False, "", 900, 37, secret, "2026-10-26",
                           allowance_fn=lambda k: reads.pop(0) if len(reads) > 1 else reads[0],
                           speak_fn=lambda k, v, t: spoken.append(t) or b"mp3", convert_fn=lambda a, p: made.append(p))
                # #187 QA: a batch the floor cut short is not a success.
                if code == 0:
                    fails.append("a batch stopped at the floor exited 0")
                if len(spoken) != 1:
                    fails.append("the kept clip was paid for again: %d clips spoken for 2 made" % len(spoken))
                if (root / RECOVER_DIR).exists() and list((root / RECOVER_DIR).glob("*.mp3")):
                    fails.append("a recovered clip stayed in %s after its conversion" % RECOVER_DIR)
        except PipelineError as e:
            fails.append("run failed: %s" % e)
        finally:
            if previous is None:
                del os.environ[KEY_ENV]
            else:
                os.environ[KEY_ENV] = previous
        if secret in captured.getvalue():
            fails.append("the key reached the output")
        if len(made) != 2:
            fails.append("the floor did not stop the batch mid-way: %d clips made" % len(made))
        manifest = _json(root / MANIFEST)
        if manifest.get("boss/event.plant", {}).get("text_sha256") != text_hash("We close in March."):
            fails.append("the stale clip's manifest row was not rewritten: %r" % manifest.get("boss/event.plant"))
        reuse = (root / "REUSE.toml").read_bytes().decode("utf-8")
        if reuse.count("[[annotations]]") != 2 or 'path = "assets/audio/voice/boss/event.plant.ogg*"' not in reuse:
            fails.append("REUSE.toml annotations: %r" % reuse)
        if "\r\n" not in reuse or "\n\n" in reuse.replace("\r\n", "\n").replace("\n\n[[", "[["):
            fails.append("REUSE.toml lost its line ending or gained blank lines: %r" % reuse)
        annotate(root / "REUSE.toml", jobs(read_sources(root), manifest, False)[0] | {"voice_id": "V1"}, "x")
        again = (root / "REUSE.toml").read_bytes().decode("utf-8")
        if again.count('path = "assets/audio/voice/union/event.strike.ogg*"') != 1:
            fails.append("a re-made clip's annotation was duplicated")
    _selftest_design(fails, secret)
    for f in fails:
        print("SELFTEST FAIL: %s" % f)
    if not fails:
        print("voice_pipeline selftest: all checks passed")
    return 1 if fails else 0


def _selftest_design(fails: list, secret: str) -> None:
    """--design with no network: statuses, the preflight stops, the writes."""
    lines = {"greet": "Thank you for seeing me. I know your time is short.",
             "refuse": "I cannot give you that. My own side would not forgive it, and nor would I."}
    desc = "A man in his fifties, a calm low baritone, measured pace, a career politician."
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "data" / "voices").mkdir(parents=True)
        table = {"archetypes": [
            {"id": "pol", "voice_id": "", "description": desc, "provenance": "Not yet designed.", "lines": lines},
            {"id": "boss", "voice_id": "", "description": desc, "provenance": "Not yet designed.", "lines": lines},
            {"id": "done", "voice_id": "V1", "description": desc, "provenance": "Designed.", "lines": lines},
            {"id": "mute", "voice_id": "", "provenance": "Not yet designed.", "lines": lines},
            {"id": "terse", "voice_id": "", "description": desc, "provenance": "Not yet designed.", "lines": {"a": "Yes."}},
        ], "defaults": {"politician": "pol"}}
        arch = root / ARCHETYPES
        arch.write_text(json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        (root / "REUSE.toml").write_bytes(b"version = 1\r\n")
        status = {r["id"]: r["status"] for r in design_jobs(json.loads(arch.read_text(encoding="utf-8")))}
        if status != {"pol": "to-design", "boss": "to-design", "done": "designed", "mute": "no-description",
                      "terse": "short-preview"}:
            fails.append("design statuses: %r" % status)
        texts = [r["text"] for r in design_jobs(table) if r["id"] == "pol"]
        if not texts or not 100 <= len(texts[0]) <= 1000 or lines["greet"] not in texts[0]:
            fails.append("the preview text is not the archetype's own lines, 100-1000 characters: %r" % texts)
        captured = io.StringIO()
        calls = []
        def account(left, slots):
            return lambda k: calls.append("account") or {"left": left, "slots_free": slots}
        def design(k, d, t, seed):
            calls.append("design")
            return "G" + str(seed % 97), b"preview-mp3"
        def save(k, name, d, gen, labels):
            calls.append("save")
            return "VOICE" + gen
        with redirect_stdout(captured), redirect_stderr(captured):
            # A row with no description or too short a preview refuses the batch.
            try:
                design_run(root, secret, 0, 10000, "2026-10-30", account_fn=account(30000, 30),
                           design_fn=design, save_fn=save)
                fails.append("--design --run went ahead with a row it cannot design")
            except PipelineError:
                pass
            table["archetypes"] = table["archetypes"][:3]
            arch.write_text(json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            planned = sum(r["chars"] for r in design_jobs(table) if r["status"] == "to-design")
            # The slots, the ceiling and the floor each stop the batch before a voice is made.
            for left, slots, ceiling, floor, why in ((30000, 1, 10000, 0, "slot"),
                                                     (30000, 30, planned - 1, 0, "--max-chars"),
                                                     (planned + 5, 30, 10000, 10, "floor")):
                calls.clear()
                try:
                    design_run(root, secret, floor, ceiling, "2026-10-30", account_fn=account(left, slots),
                               design_fn=design, save_fn=save)
                    fails.append("--design went ahead past the %s" % why)
                except PipelineError as e:
                    if why not in str(e):
                        fails.append("the %s stop gave the wrong reason: %s" % (why, e))
                if "design" in calls or "save" in calls:
                    fails.append("the %s stop came after a paid call: %s" % (why, calls))
            calls.clear()
            code = design_run(root, secret, 0, 10000, "2026-10-30", account_fn=account(30000, 30),
                              design_fn=design, save_fn=save)
        if secret in captured.getvalue():
            fails.append("the key reached the output of --design")
        if code != 0 or calls.count("save") != 2:
            fails.append("--design did not make the two voices: exit %r, calls %r" % (code, calls))
        after = json.loads(arch.read_text(encoding="utf-8"))
        ids = {a["id"]: a["voice_id"] for a in after["archetypes"]}
        if not ids["pol"].startswith("VOICEG") or not ids["boss"].startswith("VOICEG") or ids["done"] != "V1":
            fails.append("the voice ids were not written into the table: %r" % ids)
        if any("Not yet designed" in a["provenance"] for a in after["archetypes"]):
            fails.append("a designed row kept its 'not yet designed' provenance")
        if after["defaults"] != table["defaults"] or after["archetypes"][0]["lines"] != lines:
            fails.append("writing a voice id changed the rest of the table")
        reuse = (root / "REUSE.toml").read_bytes().decode("utf-8")
        if reuse.count(ids["pol"]) != 1 or reuse.count(ids["boss"]) != 1 or "\r\n" not in reuse:
            fails.append("REUSE.toml does not carry one provenance line per designed voice: %r" % reuse)
        if not (root / DESIGN_DIR / "pol.mp3").exists():
            fails.append("the chosen preview was not kept for the author to hear")
        # A second run designs nothing: every row has its voice.
        calls.clear()
        with redirect_stdout(io.StringIO()):
            design_run(root, secret, 0, 10000, "2026-10-30", account_fn=account(30000, 30),
                       design_fn=design, save_fn=save)
        if "design" in calls:
            fails.append("a second --design run designed a voice again")
        # Pass 1: the seed fits a signed 32-bit integer for any id.
        if any(not 0 <= r["seed"] < 2 ** 31 for r in design_jobs({"archetypes": [{"id": "x%d" % i} for i in range(200)]})):
            fails.append("a design seed does not fit a signed 32-bit integer")
        # Pass 1: a failed save names its archetype, and the rerun saves the same design
        # without paying for it again; --only designs one archetype.
        for a in table["archetypes"][:2]:
            a["voice_id"] = ""
        arch.write_text(json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        def refuse(k, name, d, gen, labels):
            calls.append("save")
            raise PipelineError("save: HTTP 409 (generated voice %s)" % gen)
        def unsafe(k, name, d, gen, labels):
            calls.append("save")
            return "not-a-plain-id"
        with redirect_stdout(io.StringIO()):
            calls.clear()
            try:
                design_run(root, secret, 0, 10000, "2026-10-30", account_fn=account(30000, 30),
                           design_fn=design, save_fn=refuse, only="pol")
                fails.append("a refused save did not stop --design")
            except PipelineError as e:
                if "pol" not in str(e):
                    fails.append("a refused save does not name its archetype: %s" % e)
            calls.clear()
            design_run(root, secret, 0, 10000, "2026-10-30", account_fn=account(30000, 30),
                       design_fn=design, save_fn=save, only="pol")
            if "design" in calls or calls.count("save") != 1:
                fails.append("the rerun after a refused save paid for the design again: %r" % calls)
            try:
                design_run(root, secret, 0, 10000, "2026-10-30", account_fn=account(30000, 30),
                           design_fn=design, save_fn=unsafe, only="boss")
                fails.append("an unsafe saved voice id was written")
            except PipelineError as e:
                if "not-a-plain-id" not in str(e) or "boss" not in str(e):
                    fails.append("an unsafe saved voice id is not reported with its archetype: %s" % e)
        ids = {a["id"]: a["voice_id"] for a in json.loads(arch.read_text(encoding="utf-8"))["archetypes"]}
        if not ids["pol"] or ids["boss"]:
            fails.append("--only did not design exactly the one archetype: %r" % ids)
        _selftest_design_resume(fails, secret, root, table, calls, design, save)


def _selftest_design_resume(fails: list, secret: str, root: Path, table: dict, calls: list, design, save) -> None:
    """QA #201: the mid-batch floor, a kept design past the floor, a failed table write."""
    arch = root / ARCHETYPES

    def reset():
        for a in table["archetypes"][:2]:
            a["voice_id"] = ""
        arch.write_text(json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        for kept in (root / DESIGN_DIR).glob("*.json"):
            kept.unlink()

    def reads(*left):
        queue = list(left)
        return lambda k: calls.append("account") or {"left": queue.pop(0) if len(queue) > 1 else queue[0],
                                                      "slots_free": 30}

    def voice(arch_id):
        return {a["id"]: a["voice_id"] for a in json.loads(arch.read_text(encoding="utf-8"))["archetypes"]}[arch_id]

    chars = {r["id"]: r["chars"] for r in design_jobs(table)}
    with redirect_stdout(io.StringIO()):
        # TAKE 1: the account drops below the floor before the second voice (spent
        # elsewhere): the batch stops there, exits 1, and designs nothing more.
        reset()
        calls.clear()
        code = design_run(root, secret, 1000, 10000, "2026-10-30",
                          account_fn=reads(30000, 30000, 1000 + chars["boss"] - 1), design_fn=design, save_fn=save)
        if code != 1:
            fails.append("a --design batch stopped at the floor exited %r, not 1" % code)
        if calls.count("design") != 1 or voice("boss"):
            fails.append("the mid-batch floor did not stop --design before the second voice: %r" % calls)
        # R(a): a kept design costs nothing more, so the floor does not stop its save.
        reset()

        def refuse(k, name, d, gen, labels):
            raise PipelineError("save: HTTP 409 (generated voice %s)" % gen)
        try:
            design_run(root, secret, 0, 10000, "2026-10-30", account_fn=reads(30000),
                       design_fn=design, save_fn=refuse, only="boss")
        except PipelineError:
            pass
        calls.clear()
        try:
            code = design_run(root, secret, 10, 10000, "2026-10-30", account_fn=reads(10 + chars["boss"] - 1),
                              design_fn=design, save_fn=save, only="boss")
        except PipelineError as e:
            code = "raised: %s" % e
        if code != 0 or "design" in calls or not voice("boss"):
            fails.append("the floor stopped the free save of a kept design: exit %r, calls %r" % (code, calls))
        # R(b): the save went through, the table write failed: the rerun writes the
        # saved voice and does not save the design a second time.
        reset()
        real = globals()["write_voice"]

        def broken(*a):
            raise OSError("disk full")
        globals()["write_voice"] = broken
        first = ""
        try:
            design_run(root, secret, 0, 10000, "2026-10-30", account_fn=reads(30000),
                       design_fn=design, save_fn=save, only="boss")
            fails.append("a failed table write did not stop --design")
        except PipelineError as e:
            first = (_json(root / DESIGN_DIR / "boss.json") or {}).get("voice_id", "")
            if not first or first not in str(e) or "boss" not in str(e):
                fails.append("a failed table write does not name the saved voice: %s" % e)
        finally:
            globals()["write_voice"] = real
        calls.clear()
        design_run(root, secret, 0, 10000, "2026-10-30", account_fn=reads(30000),
                   design_fn=design, save_fn=save, only="boss")
        if "save" in calls or "design" in calls or not first or voice("boss") != first:
            fails.append("the rerun after a failed table write saved again: calls %r, voice %r" % (calls, voice("boss")))
        if (root / DESIGN_DIR / "boss.json").exists():
            fails.append("the kept design stayed after its voice was written")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--every", action="store_true", help="voice an event line in every archetype a speaker may carry")
    ap.add_argument("--only", default="", help="one archetype")
    ap.add_argument("--run", action="store_true", help="the PAID path; needs --floor and --max-chars")
    ap.add_argument("--floor", type=int, default=None, help="characters the allowance must keep")
    ap.add_argument("--max-chars", type=int, default=None, help="this batch's ceiling in characters")
    ap.add_argument("--design", action="store_true", help="design the archetype voices (Voice Design)")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.run:
        return design_dry_run(REPO) if args.design else dry_run(REPO, args.every, args.only)
    if args.floor is None or args.max_chars is None:
        print("--run needs --floor and --max-chars (no defaults: the parent's GO names them)")
        return 2
    key = os.environ.get(KEY_ENV, "")
    if not key:
        print("%s is not set" % KEY_ENV)
        return 2
    if args.design:
        try:
            return design_run(REPO, key, args.floor, args.max_chars, datetime.date.today().isoformat(),
                              only=args.only)
        except PipelineError as e:
            print("stopped: %s" % e)
            return 1
    if not shutil.which("ffmpeg"):
        print("ffmpeg not found")
        return 2
    try:
        return run(REPO, args.every, args.only, args.floor, args.max_chars, key,
                   datetime.date.today().isoformat())
    except PipelineError as e:
        print("stopped: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
