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
  python tools/voice_pipeline.py --selftest      no network; CI runs it
"""

import argparse
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
        "events": events,
    }


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

def _request(method: str, url: str, key: str, body: bytes = None) -> tuple:
    headers = {"xi-api-key": key, "Accept": "application/json" if method == "GET" else "audio/mpeg"}
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


def allowance(key: str) -> int:
    """Characters left this period, from the account's own count."""
    status, body = _request("GET", API + "/user/subscription", key)
    if status != 200:
        raise PipelineError("subscription: HTTP %d" % status)
    try:
        sub = json.loads(body)
        return int(sub["character_limit"]) - int(sub["character_count"])
    except (ValueError, KeyError, TypeError) as e:
        raise PipelineError("subscription: not the account's count (%s)" % type(e).__name__)


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
    for f in fails:
        print("SELFTEST FAIL: %s" % f)
    if not fails:
        print("voice_pipeline selftest: all checks passed")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--every", action="store_true", help="voice an event line in every archetype a speaker may carry")
    ap.add_argument("--only", default="", help="one archetype")
    ap.add_argument("--run", action="store_true", help="the PAID path; needs --floor and --max-chars")
    ap.add_argument("--floor", type=int, default=None, help="characters the allowance must keep")
    ap.add_argument("--max-chars", type=int, default=None, help="this batch's ceiling in characters")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.run:
        return dry_run(REPO, args.every, args.only)
    if args.floor is None or args.max_chars is None:
        print("--run needs --floor and --max-chars (no defaults: the parent's GO names them)")
        return 2
    key = os.environ.get(KEY_ENV, "")
    if not key:
        print("%s is not set" % KEY_ENV)
        return 2
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
