#!/usr/bin/env python3
"""Localisation worklist -- V5.1b. Dev-only, never shipped. See docs/localisation.md.

What a translator needs to know, read off the tree rather than kept by hand:

  python tools/i18n_extract.py                    coverage of every language in data/i18n
  python tools/i18n_extract.py --todo fr > w.json the worklist for fr (format below)
  python tools/i18n_extract.py --apply w.json     write a filled worklist back into the tables
  python tools/i18n_extract.py --check            exit 1 on a stale key (its source went away),
                                                  an empty value, a placeholder mismatch, or one
                                                  row id in two files of the same kind

THE SOURCES are the ENGLISH itself, in two places:

  UI     every literal inside tr("...") or Strings.t("...") in src/ui/*.gd (dev_*.gd is
         English by design), plus the literals on a line that ends `# i18n: msgid`
         -- the way a const table of prose is marked, since a const cannot call tr().
         On a marked line a literal that is a dictionary KEY (followed by `:`) is not a
         msgid; `# i18n: msgid label` lists only the values of the key "label" (a table
         whose rows also hold ids and numbers). The table is data/i18n/<lang>/ui.json:
         {msgid: translation}.
  ROWS   the translatable fields of the rows in data/<kind>/*.json (TRANSLATABLE below),
         keyed `<id>.<field>`; nested choices as `<event id>.choices.<choice id>.label`.
         The table is data/i18n/<lang>/<kind>.json. The English stays in the row.

There is no English table: English is the source (docs/localisation.md says why).

THE WORKLIST (--todo LANG) is JSON, one entry per untranslated string, the language's
slot empty, the English beside it so a translator never has to open the source:

  {"lang": "fr",
   "ui":   {"Save the game": {"en": "Save the game", "fr": ""}, ...},
   "rows": {"laws": {"single_term_reform.name": {"en": "Single-Term ...", "fr": ""}, ...},
            "events": {"com_gas_squeeze.choices.freeze_the_tariff.label": {...}, ...}}}

Fill the "fr" slots and run --apply on the file: every filled slot is written into
data/i18n/fr/ui.json or data/i18n/fr/<kind>.json (existing entries are kept, a filled slot
overwrites its key); an empty slot is skipped; a slot whose placeholders (%d %s %.1f ...)
differ from the English in kind or order is REFUSED and named; a key whose English has
gone away is refused as stale.
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
MARKER = re.compile(r"# i18n: msgid(?: (\w+))?\s*$")
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


def _marked_msgids(line, field):
    """The literals of a `# i18n: msgid` line that are msgids: not dictionary keys, and
    with a field named, only the values of that key."""
    out = []
    lits = literals(line)
    for index, (start, end, text) in enumerate(lits):
        if re.match(r"\s*:", line[end + 1:]):
            continue  # a key
        if field:
            before = line[:start].rstrip()
            key = lits[index - 1][2] if index > 0 and before.endswith(":") else None
            if key != field:
                continue
        out.append(text)
    return out


def ui_msgids():
    found = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "src", "ui", "*.gd"))):
        if os.path.basename(path).startswith("dev_"):
            continue
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            where = "%s:%d" % (os.path.basename(path), number)
            marker = MARKER.search(line)
            texts = []
            if marker:
                texts = _marked_msgids(line, marker.group(1))
            else:
                for start, _end, text in literals(line):
                    if WRAPPED.search(line[:start]):
                        texts.append(text)
            for text in texts:
                if re.search(r"[A-Za-z]{2,}", text):
                    found.setdefault(unescape(text), where)
    return found


def _rows_of(kind, doc):
    key = ROW_LISTS.get(kind)
    if key and isinstance(doc.get(key), list):
        return doc[key]
    for value in doc.values():
        if isinstance(value, list) and value and isinstance(value[0], dict) and "id" in value[0]:
            return value
    return [doc] if "id" in doc else []


def _dig(row, parts):
    """[(field path, text)] for one dotted field (as parts); '*' walks a list of rows by id."""
    results = [("", row)]
    for depth, part in enumerate(parts):
        last = depth == len(parts) - 1
        nxt = []
        for path, node in results:
            if part == "*" and isinstance(node, list):
                for item in node:
                    if isinstance(item, dict) and "id" in item:
                        nxt.append((path + str(item["id"]) + ".", item))
            elif isinstance(node, dict) and part in node:
                nxt.append((path + part + ("" if last else "."), node[part]))
        results = nxt
    return [(p, v) for p, v in results if isinstance(v, str) and v.strip()]


def row_texts():
    """({kind: {"<id>.<field path>": english}}, [duplicate row ids "kind: id (file, file)"])."""
    out = {}
    duplicates = []
    for kind, fields in TRANSLATABLE.items():
        texts = {}
        seen = {}
        for path in sorted(glob.glob(os.path.join(ROOT, "data", kind, "*.json"))):
            doc = json.load(open(path, encoding="utf-8"))
            for row in _rows_of(kind, doc):
                if "id" not in row:
                    continue
                name = os.path.basename(path)
                if row["id"] in seen:
                    duplicates.append("%s: id '%s' in %s and %s" % (kind, row["id"], seen[row["id"]], name))
                    continue
                seen[row["id"]] = name
                for dotted in fields:
                    for field, value in _dig(row, dotted.split(".")):
                        texts["%s.%s" % (row["id"], field)] = value
        if texts:
            out[kind] = texts
    return out, duplicates


def languages():
    return [
        d for d in sorted(os.listdir(os.path.join(ROOT, "data", "i18n")))
        if os.path.isdir(os.path.join(ROOT, "data", "i18n", d))
    ]


def table_path(lang, name):
    return os.path.join(ROOT, "data", "i18n", lang, name + ".json")


def load_table(lang, name):
    path = table_path(lang, name)
    if not os.path.exists(path):
        return {}
    return json.load(open(path, encoding="utf-8"))


def sources():
    """[(table name, {key: english})], UI first. Also the duplicate-id list."""
    rows, duplicates = row_texts()
    ui = ui_msgids()
    return [("ui", {k: k for k in ui})] + sorted(rows.items()), duplicates


def problems(source, table):
    live = {k: v for k, v in table.items() if not k.startswith("_")}
    stale = sorted(k for k in live if k not in source)
    empty = sorted(k for k, v in live.items() if not str(v).strip())
    holders = sorted(
        k for k, v in live.items()
        if k in source and PLACEHOLDER.findall(source[k]) != PLACEHOLDER.findall(str(v))
    )
    return stale, empty, holders


def todo(lang):
    out = {"lang": lang, "ui": {}, "rows": {}}
    tables, _dups = sources()
    for name, source in tables:
        table = load_table(lang, name)
        missing = {k: {"en": en, lang: ""} for k, en in source.items() if k not in table}
        if not missing:
            continue
        if name == "ui":
            out["ui"] = missing
        else:
            out["rows"][name] = missing
    return out


def apply_worklist(path):
    """Write the filled slots of a worklist into the tables; returns the number refused."""
    work = json.load(open(path, encoding="utf-8"))
    lang = work["lang"]
    tables = dict(sources()[0])
    refused = 0
    written = 0
    groups = [("ui", work.get("ui", {}))] + sorted(work.get("rows", {}).items())
    for name, entries in groups:
        source = tables.get(name)
        if source is None:
            print("refused: no table '%s'" % name)
            refused += len(entries)
            continue
        table = load_table(lang, name)
        changed = False
        for key, entry in entries.items():
            text = str(entry.get(lang, "")).strip()
            if not text:
                continue
            if key not in source:
                print("refused (stale, its English is gone): %s/%s" % (name, key))
                refused += 1
                continue
            if PLACEHOLDER.findall(source[key]) != PLACEHOLDER.findall(text):
                print("refused (placeholders differ from the English): %s/%s" % (name, key))
                refused += 1
                continue
            table[key] = text
            written += 1
            changed = True
        if changed:
            os.makedirs(os.path.dirname(table_path(lang, name)), exist_ok=True)
            with open(table_path(lang, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(json.dumps(table, ensure_ascii=False, indent=2) + "\n")
    print("applied %d, refused %d" % (written, refused))
    return refused


def main(argv):
    # Windows consoles default to a legacy code page; the tables are UTF-8.
    sys.stdout.reconfigure(encoding="utf-8")
    if "--todo" in argv:
        json.dump(todo(argv[argv.index("--todo") + 1]), sys.stdout, ensure_ascii=False, indent=2)
        print()
        return 0
    if "--apply" in argv:
        return 1 if apply_worklist(argv[argv.index("--apply") + 1]) else 0
    bad = 0
    tables, duplicates = sources()
    for lang in languages():
        print("== %s" % lang)
        for name, source in tables:
            table = load_table(lang, name)
            done = sum(1 for k in source if k in table)
            stale, empty, holders = problems(source, table)
            print("  %-20s %5d / %-5d translated   stale %d, empty %d, placeholder mismatch %d" % (name, done, len(source), len(stale), len(empty), len(holders)))
            for label, items in (("stale", stale), ("empty", empty), ("placeholders", holders)):
                for key in items[:5]:
                    print("      %s: %s" % (label, key))
            bad += len(stale) + len(empty) + len(holders)
    for line in duplicates:
        print("duplicate row id -- %s" % line)
    bad += len(duplicates)
    if "--check" in argv and bad:
        print("i18n check: %d problem(s)" % bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
