#!/usr/bin/env python3
"""Localisation worklist -- V5.1b. Dev-only, never shipped. See docs/localisation.md.

What a translator needs to know, read off the tree rather than kept by hand:

  python tools/i18n_extract.py            coverage of every language in data/i18n
  python tools/i18n_extract.py --todo fr  the msgids and row keys fr has not translated,
                                          as JSON ({english-or-key: ""}) to fill in
  python tools/i18n_extract.py --check    exit 1 on a stale key (its source went away),
                                          an empty value, or a placeholder mismatch

The sources are the ENGLISH itself, in two places:

  UI     every literal inside tr("...") or Strings.t("...") in src/ui/*.gd (dev_*.gd is
         English by design), plus every literal on a line that ends `# i18n: msgid`
         -- the way a const table of prose is marked, since a const cannot call tr().
         The table is data/i18n/<lang>/ui.json: {msgid: translation}.
  ROWS   the translatable fields of the rows in data/<kind>/*.json (TRANSLATABLE below),
         keyed `<id>.<field>`; nested choices as `<event id>.choices.<choice id>.label`.
         The table is data/i18n/<lang>/<kind>.json. The English stays in the row.

There is no English table: English is the source (docs/localisation.md says why).
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
# tr( or Strings.t( ending the text before a literal; not str( / substr(.
WRAPPED = re.compile(r"(?<![A-Za-z0-9_])(?:tr|Strings\.t)\($")
PLACEHOLDER = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdfxXc%]")

# data directory -> the fields of a row (dotted for nested) that a player reads as
# prose. Names of people, parties, outlets, firms and places are proper nouns and are
# not here; a language that wants them adds the kind and the field to this table.
TRANSLATABLE = {
    "laws": ["name", "summary"],
    "events": ["name", "summary", "choices.*.label", "choices.*.summary"],
    "programme": ["name", "summary"],
    "campaign-actions": ["name", "summary"],
    "diplomatic-actions": ["name", "summary"],
    "company-actions": ["name", "summary"],
    "energy-actions": ["name", "summary"],
    "investment-actions": ["name", "summary"],
    "project-actions": ["name", "summary"],
    "bloc-proposals": ["name", "summary"],
    "pledges": ["name", "summary"],
}
# The list a kind's rows sit in, per file: laws.json holds {"laws": [...]}; a file
# whose top level is a single row (orgs) is read as one.
ROW_LISTS = {"laws": "laws", "events": "events", "programme": "programme"}


def literals(line):
    """[(start, end, text)] of the string literals of one GDScript line, comment cut."""
    out = []
    i = 0
    while i < len(line):
        c = line[i]
        if c == "#":
            break
        if c == '"':
            start = i
            i += 1
            text = ""
            while i < len(line) and line[i] != '"':
                if line[i] == BS and i + 1 < len(line):
                    text += line[i]
                    i += 1
                text += line[i]
                i += 1
            out.append((start, i, text))
        i += 1
    return out


def unescape(text):
    """The string GDScript makes of the literal's source."""
    text = re.sub(re.escape(BS) + r"u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), text)
    return text.replace(BS + "n", "\n").replace(BS + "t", "\t").replace(BS + '"', '"').replace(BS + BS, BS)


def ui_msgids():
    found = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "src", "ui", "*.gd"))):
        if os.path.basename(path).startswith("dev_"):
            continue
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            marked = line.rstrip().endswith("# i18n: msgid")
            for start, _end, text in literals(line):
                before = line[:start]
                if marked or WRAPPED.search(before):
                    if re.search(r"[A-Za-z]{2,}", text):
                        found.setdefault(unescape(text), "%s:%d" % (os.path.basename(path), number))
    return found


def _rows_of(kind, doc):
    key = ROW_LISTS.get(kind)
    if key and isinstance(doc.get(key), list):
        return doc[key]
    for value in doc.values():
        if isinstance(value, list) and value and isinstance(value[0], dict) and "id" in value[0]:
            return value
    return [doc] if "id" in doc else []


def _dig(row, dotted):
    """[(field path, text)] for one dotted field; '*' walks a list of rows by their id."""
    parts = dotted.split(".")
    results = [("", row)]
    for part in parts:
        nxt = []
        for path, node in results:
            if part == "*" and isinstance(node, list):
                for item in node:
                    if isinstance(item, dict) and "id" in item:
                        nxt.append((path + str(item["id"]) + ".", item))
            elif isinstance(node, dict) and part in node:
                nxt.append((path + part + ("." if part != parts[-1] else ""), node[part]))
        results = nxt
    return [(p.rstrip("."), v) for p, v in results if isinstance(v, str) and v.strip()]


def row_texts():
    """kind -> {"<id>.<field path>": english}."""
    out = {}
    for kind, fields in TRANSLATABLE.items():
        texts = {}
        for path in sorted(glob.glob(os.path.join(ROOT, "data", kind, "*.json"))):
            doc = json.load(open(path, encoding="utf-8"))
            for row in _rows_of(kind, doc):
                if "id" not in row:
                    continue
                for dotted in fields:
                    for field, value in _dig(row, dotted):
                        texts["%s.%s" % (row["id"], field)] = value
        if texts:
            out[kind] = texts
    return out


def languages():
    return [
        d for d in sorted(os.listdir(os.path.join(ROOT, "data", "i18n")))
        if os.path.isdir(os.path.join(ROOT, "data", "i18n", d))
    ]


def load_table(lang, name):
    path = os.path.join(ROOT, "data", "i18n", lang, name + ".json")
    if not os.path.exists(path):
        return {}
    return {k: v for k, v in json.load(open(path, encoding="utf-8")).items() if not k.startswith("_")}


def report(lang):
    """(label, source, table) per table of a language, UI first."""
    sources = [("ui", ui_msgids())] + sorted(row_texts().items())
    return [(name, src, load_table(lang, name)) for name, src in sources]


def problems(source, table):
    stale = sorted(k for k in table if k not in source)
    empty = sorted(k for k, v in table.items() if not str(v).strip())
    holders = sorted(
        k for k, v in table.items()
        if k in source and PLACEHOLDER.findall(source[k] if isinstance(source[k], str) and k not in source.get("_keyed", {}) else k)
        != PLACEHOLDER.findall(str(v))
    )
    return stale, empty, holders


def main(argv):
    # Windows consoles default to a legacy code page; the tables are UTF-8.
    sys.stdout.reconfigure(encoding="utf-8")
    langs = languages()
    if "--todo" in argv:
        lang = argv[argv.index("--todo") + 1]
        out = {}
        for name, source, table in report(lang):
            for key, where in source.items():
                if key not in table:
                    # rows are keyed by id, so the English is the value to translate
                    out[key if name == "ui" else name + "/" + key] = "" if name == "ui" else where
        json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return 0
    bad = 0
    for lang in langs:
        print("== %s" % lang)
        for name, source, table in report(lang):
            done = sum(1 for k in source if k in table)
            stale, empty, holders = problems(
                {k: (k if name == "ui" else v) for k, v in source.items()}, table
            )
            print("  %-20s %5d / %-5d translated   stale %d, empty %d, placeholder mismatch %d" % (name, done, len(source), len(stale), len(empty), len(holders)))
            for label, items in (("stale", stale), ("empty", empty), ("placeholders", holders)):
                for key in items[:5]:
                    print("      %s: %s" % (label, key))
            bad += len(stale) + len(empty) + len(holders)
    if "--check" in argv and bad:
        print("i18n check: %d problem(s)" % bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
