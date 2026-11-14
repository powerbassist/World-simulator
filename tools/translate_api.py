#!/usr/bin/env python3
"""Draft translations through the Claude API -- dev-only, never shipped. DRAFTS ONLY.

  python tools/translate_api.py --table glossary --skill PATH --out DRAFTS.json [--lang fr]
         [--cap-usd 5] [--model claude-opus-5-5] [--limit N] [--dry-run]
  python tools/translate_api.py --selftest

It reads what `tools/i18n_extract.py --todo LANG` lists as untranslated for ONE table,
groups the strings of one row together (a glossary term with its definition and body, an
event with its choices; the ui table by the file that shows them), sends each group with
its context -- the key, the table, the src/ui files that display that table -- and the
language skill as the cached system prompt, and writes the answers as a WORKLIST to --out:
the format `i18n_extract.py --apply` reads, so a reviewer edits the slots and applies it.
It never writes into data/i18n/.

Gates on every answer, before it reaches the worklist: every key answered and non-empty,
and the same tokens as the English (i18n_extract.tokens: %-placeholders in order, every
{{variable}}, every glossary mark [g=id] and its [/g]). A draft that fails a gate goes to
"_rejected" with the reason, never to a fillable slot.

MONEY. The cost is computed from each response's usage fields at the model's list price
(PRICES below). Before every request the worst case of that request (its input estimated
generously, plus max_tokens of output) is added to what is spent: if the sum would pass
the cap (default and maximum 5 USD), it stops, sends nothing more, and says so. A billing
error (402, "billing_error", or "credit balance is too low") or an authentication or
permission error stops the run at once, sending nothing more, in one line. The cost is
printed at the end and stored in the worklist's "_meta".

THE KEY is read by the SDK from ANTHROPIC_API_KEY (or the SDK's other sources); this
script never reads, prints, logs or passes it. Only tracked, unmodified text under data/
is sent: the run refuses a data/ tree with untracked or modified files.

No refusal fallback: a group the model declines (stop_reason "refusal") is listed under
"_rejected" for a person to translate, because a fallback model's price would make the
cap a guess.
"""
from __future__ import annotations

import datetime
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import i18n_extract as X  # noqa: E402

ROOT = X.ROOT
HARD_CAP_USD = 5.0
# USD per million tokens: input, output, cache write (5 min), cache read. A model not here
# is refused: the cap needs its price. (claude-api skill table, cached 2026-11-03.)
PRICES = {
    "claude-opus-5-5": (4.00, 20.00, 5.00, 0.20),
    "claude-sonnet-5-5": (2.00, 10.00, 2.50, 0.10),
    "claude-haiku-5-5": (0.10, 0.50, 0.125, 0.01),
}
MAX_TOKENS = 16000
# A group holds at most this many keys: a request stays short and one bad answer costs
# one group.
GROUP_KEYS = 24
BILLING_WORDS = ("credit balance", "billing", "payment")

INSTRUCTIONS = """You translate a strategy game's English text into {language} for the
player to read. The system prompt above is the project's skill for {language}: follow its
termbase, typography, register and length budget.

Rules the game's code depends on, never broken:
- Keep every %-placeholder (%d %s %.1f %+d %%) exactly, in the same order.
- Keep every {{{{variable}}}} exactly as written (its name stays English).
- Keep every glossary mark: [g=id] stays as it is, the word inside is translated, and
  each [g=id] keeps its closing [/g].
- Names of people, parties, outlets, firms and places stay as they are.
- A leading or trailing space in the English is the caller's: do not add or drop one.

Answer with ONE JSON object and nothing else: each key below mapped to its {language}
text. Every key, no other key."""


def _git(args):
    return subprocess.run(["git"] + args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout


def data_tree_clean():
    """'' when every file under data/ is tracked and unmodified, else the first offenders."""
    dirty = [line for line in _git(["status", "--porcelain", "--untracked-files=all", "--", "data"]).splitlines() if line.strip()]
    return "; ".join(dirty[:5])


def callers_of(table):
    """The src/ui files that display `table` (a row kind) through Strings, for context."""
    if table == "ui":
        return []
    files = set()
    pattern = re.compile(r"Strings\.\w+\(\"%s\"" % re.escape(table))
    for name in sorted(os.listdir(os.path.join(ROOT, "src", "ui"))):
        if name.endswith(".gd"):
            text = open(os.path.join(ROOT, "src", "ui", name), encoding="utf-8").read()
            if pattern.search(text):
                files.add(name)
    return sorted(files)


def worklist_rows(lang, table):
    """{key: {"en": english, ...}} of `table`'s untranslated strings (i18n_extract --todo)."""
    todo = X.todo(lang)
    return todo["ui"] if table == "ui" else todo["rows"].get(table, {})


def group_rows(table, rows, ui_where=None):
    """[[key, ...]] -- the keys of one row together (the key's id, before its first dot), or
    for the ui table the msgids of one source file together; at most GROUP_KEYS a group."""
    by = {}
    for key in rows:
        if table == "ui":
            head = (ui_where or {}).get(key, "?").split(":")[0]
        else:
            head = key.split(".", 1)[0]
        by.setdefault(head, []).append(key)
    groups = []
    current = []
    for head in sorted(by):
        keys = by[head]
        if current and len(current) + len(keys) > GROUP_KEYS:
            groups.append(current)
            current = []
        current.extend(keys)
        while len(current) > GROUP_KEYS:
            groups.append(current[:GROUP_KEYS])
            current = current[GROUP_KEYS:]
    if current:
        groups.append(current)
    return groups


def request_text(lang_name, table, keys, rows, shown_by, done):
    """The user message of one group: the rules, then the context, then the strings."""
    lines = [INSTRUCTIONS.format(language=lang_name), "", "Table: %s" % table]
    if shown_by:
        lines.append("Shown by: %s" % ", ".join(shown_by))
    if done:
        lines.append("Already translated in this row (keep consistent):")
        lines.append(json.dumps(done, ensure_ascii=False, indent=1))
    lines.append("Strings to translate (key: English):")
    lines.append(json.dumps({k: rows[k]["en"] for k in keys}, ensure_ascii=False, indent=1))
    return "\n".join(lines)


def parse_answer(text):
    """The JSON object in a model answer; None when there is none."""
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        value = json.loads(text[start:end + 1])
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def gate(english, draft):
    """'' when the draft may go to a slot, else why not."""
    if not isinstance(draft, str) or not draft.strip():
        return "empty"
    if X.tokens(english) != X.tokens(draft):
        return "tokens differ (placeholders, {{variables}} or [g=] marks)"
    return ""


def cost_usd(model, usage):
    """The cost of one response from its usage fields."""
    p_in, p_out, p_write, p_read = PRICES[model]
    get = lambda name: int(getattr(usage, name, 0) or 0)
    return (get("input_tokens") * p_in + get("output_tokens") * p_out
            + get("cache_creation_input_tokens") * p_write + get("cache_read_input_tokens") * p_read) / 1e6


def worst_case_usd(model, system_text, user_text):
    """An upper bound of one request's cost before it is sent: input at 1 token per 2
    characters (generous for English and JSON), all of it priced as a cache write, plus
    max_tokens of output."""
    p_in, p_out, p_write, _p_read = PRICES[model]
    tokens_in = (len(system_text) + len(user_text)) / 2.0
    return (tokens_in * max(p_in, p_write) + MAX_TOKENS * p_out) / 1e6


def stop_reason_of_error(err):
    """'billing' / 'auth' / '' for an SDK exception: which errors end the run at once."""
    status = getattr(err, "status_code", None)
    kind = str(getattr(err, "type", "") or "")
    message = str(getattr(err, "message", "") or "").lower()
    if status == 402 or kind == "billing_error" or any(w in message for w in BILLING_WORDS):
        return "billing"
    if status in (401, 403) or kind in ("authentication_error", "permission_error"):
        return "auth"
    return ""


def run(client, model, lang, lang_name, table, system_text, cap, limit=0, out=print, rows=None):
    """Draft every untranslated string of `table` (or `rows`, the selftest's). Returns the worklist."""
    rows = worklist_rows(lang, table) if rows is None else rows
    ui_where = X.ui_msgids()[0] if table == "ui" else None
    if table == "ui":
        ui_where.update(X.dialogue_msgids())
    groups = group_rows(table, rows, ui_where)
    if limit:
        groups = groups[:limit]
    shown_by = callers_of(table)
    existing = X.load_table(lang, table)
    drafts, rejected = {}, {}
    spent = 0.0
    sent = 0
    stopped = ""
    system = [{"type": "text", "text": system_text, "cache_control": {"type": "ephemeral"}}]
    for keys in groups:
        heads = {k.split(".", 1)[0] for k in keys}
        done = {k: v for k, v in existing.items() if table != "ui" and k.split(".", 1)[0] in heads}
        user_text = request_text(lang_name, table, keys, rows, shown_by, done)
        if spent + worst_case_usd(model, system_text, user_text) > cap:
            stopped = "cap: the next request could pass %.2f USD (spent %.4f); stopped before sending it" % (cap, spent)
            break
        try:
            response = client.messages.create(model=model, max_tokens=MAX_TOKENS, system=system,
                                              messages=[{"role": "user", "content": user_text}])
        except Exception as err:  # the SDK's typed errors; classified, never printed raw
            why = stop_reason_of_error(err)
            if why == "billing":
                stopped = "billing error (credit balance or payment): stopped, nothing more sent"
            elif why == "auth":
                stopped = "authentication or permission error: stopped, nothing more sent"
            else:
                stopped = "API error (%s %s): stopped, nothing more sent" % (type(err).__name__, getattr(err, "status_code", ""))
            break
        sent += 1
        spent += cost_usd(model, response.usage)
        if response.stop_reason == "refusal":
            for k in keys:
                rejected[k] = {"en": rows[k]["en"], "why": "the model declined this group"}
            continue
        text = "".join(getattr(b, "text", "") for b in response.content if getattr(b, "type", "") == "text")
        answer = parse_answer(text) if response.stop_reason != "max_tokens" else None
        for k in keys:
            if answer is None:
                rejected[k] = {"en": rows[k]["en"], "why": "no JSON answer (%s)" % response.stop_reason}
                continue
            why = gate(rows[k]["en"], answer.get(k))
            if why:
                rejected[k] = {"en": rows[k]["en"], lang: answer.get(k), "why": why}
            else:
                drafts[k] = {"en": rows[k]["en"], lang: answer[k]}
        out("group %d/%d: %d keys, %d drafted so far, %.4f USD" % (sent, len(groups), len(keys), len(drafts), spent))
    work = {"lang": lang, "ui": {}, "rows": {}}
    if table == "ui":
        work["ui"] = drafts
    else:
        work["rows"][table] = drafts
    work["_rejected"] = rejected
    work["_meta"] = {"model": model, "table": table, "requests": sent, "groups": len(groups),
                     "drafted": len(drafts), "rejected": len(rejected), "cost_usd": round(spent, 4),
                     "cap_usd": cap, "stopped": stopped,
                     "when": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
    return work


def _arg(argv, name, default=None):
    if name in argv:
        i = argv.index(name)
        return argv[i + 1] if i + 1 < len(argv) else default
    return default


def selftest():
    """No network, no key: a fake client stands in for the API."""
    bad = []

    def check(what, got, want):
        if got != want:
            bad.append("%s: got %r, wanted %r" % (what, got, want))

    class U:
        def __init__(self, i, o, w=0, r=0):
            self.input_tokens, self.output_tokens = i, o
            self.cache_creation_input_tokens, self.cache_read_input_tokens = w, r

    class B:
        def __init__(self, text):
            self.type, self.text = "text", text

    class R:
        def __init__(self, text, usage, stop="end_turn"):
            self.content, self.usage, self.stop_reason = [B(text)], usage, stop

    class Err(Exception):
        def __init__(self, status, kind, message):
            super().__init__(message)
            self.status_code, self.type, self.message = status, kind, message

    class Fake:
        def __init__(self, replies):
            self.replies, self.calls, self.last = list(replies), 0, None
            self.messages = self

        def create(self, **kwargs):
            self.calls += 1
            self.last = kwargs
            reply = self.replies.pop(0)
            if isinstance(reply, Exception):
                raise reply
            return reply(kwargs) if callable(reply) else reply

    # The gates: a lost %d, {{variable}}, [g=id] or [/g] is refused; a moved mark is not.
    check("gate ok", gate("Spend %d bn on {{x}}", "Dépenser %d Md sur {{x}}"), "")
    check("gate placeholder", gate("Spend %d bn", "Dépenser des milliards") != "", True)
    check("gate variable", gate("Hello {{president}}", "Bonjour {{président}}") != "", True)
    check("gate mark id", gate("The [g=gdp]GDP[/g]", "Le [g=pib]PIB[/g]") != "", True)
    check("gate closing", gate("The [g=gdp]GDP[/g] grows", "Le [g=gdp]PIB croît") != "", True)
    check("gate empty", gate("Hi", "  "), "empty")
    check("parse fenced", parse_answer('```json\n{"a.term": "b"}\n```'), {"a.term": "b"})
    check("parse none", parse_answer("no json here"), None)
    # Grouping keeps a row's fields together.
    groups = group_rows("glossary", {"gdp.term": {}, "gdp.body": {}, "debt.term": {}})
    check("grouping", sorted(map(sorted, groups)), [["debt.term", "gdp.body", "gdp.term"]])
    check("grouping cap", max(len(g) for g in group_rows("glossary", {"r%d.term" % i: {} for i in range(60)})), GROUP_KEYS)
    # Cost from usage, at list price.
    check("cost", round(cost_usd("claude-opus-5-5", U(1000, 1000, 2000, 10000)), 6),
          round((1000 * 4 + 1000 * 20 + 2000 * 5 + 10000 * 0.2) / 1e6, 6))
    # Errors that stop the run.
    check("billing 402", stop_reason_of_error(Err(402, "billing_error", "x")), "billing")
    check("billing 400 credit", stop_reason_of_error(Err(400, "invalid_request_error",
                                                          "Your credit balance is too low to access the Anthropic API.")), "billing")
    check("auth", stop_reason_of_error(Err(401, "authentication_error", "invalid x-api-key")), "auth")
    check("other", stop_reason_of_error(Err(400, "invalid_request_error", "messages: bad")), "")

    # Whole runs over synthetic glossary rows (two groups), so the test does not depend on
    # what is still untranslated in the real tables.
    rows = {"t%02d.%s" % (i, f): {"en": "Term %d {{president}} %s" % (i, f)} for i in range(16) for f in ("term", "body")}
    groups = group_rows("glossary", rows)
    if len(groups) < 2:
        bad.append("the synthetic rows make %d group(s), the cap test needs two" % len(groups))
    else:
        def answer_all(broken_key=None):
            def reply(kwargs):
                asked = json.loads(kwargs["messages"][0]["content"].split("(key: English):\n", 1)[1])
                out = {k: ("FR " + v) for k, v in asked.items()}
                if broken_key in out:
                    out[broken_key] = "FR sans {{president}}" if "{{" not in asked[broken_key] else "FR"
                return R(json.dumps(out), U(3000, 500))
            return reply

        quiet = lambda *_a: None
        fake = Fake([answer_all() for _ in groups])
        work = run(fake, "claude-opus-5-5", "fr", "French", "glossary", "SKILL", HARD_CAP_USD, out=quiet, rows=rows)
        check("all drafted", work["_meta"]["drafted"], sum(len(g) for g in groups))
        check("system cached", fake.last["system"][0].get("cache_control"), {"type": "ephemeral"})
        check("context sent", "Shown by: " in fake.last["messages"][0]["content"], True)
        first = groups[0][0]
        fake = Fake([answer_all(broken_key=first)] + [answer_all() for _ in groups[1:]])
        work = run(fake, "claude-opus-5-5", "fr", "French", "glossary", "SKILL", HARD_CAP_USD, out=quiet, rows=rows)
        check("broken draft rejected", first in work["_rejected"] and first not in work["rows"]["glossary"], True)
        # A declined group goes to _rejected for a person, never to a slot.
        fake = Fake([R('{"x": "y"}', U(3000, 10), stop="refusal")] + [answer_all() for _ in groups[1:]])
        work = run(fake, "claude-opus-5-5", "fr", "French", "glossary", "SKILL", HARD_CAP_USD, out=quiet, rows=rows)
        check("refusal rejected", all(work["_rejected"].get(k, {}).get("why") == "the model declined this group"
                                      for k in groups[0]), True)
        # Billing on the first call: one call made, nothing more, the reason recorded.
        fake = Fake([Err(400, "invalid_request_error", "Your credit balance is too low to access the Anthropic API.")]
                    + [answer_all() for _ in groups])
        work = run(fake, "claude-opus-5-5", "fr", "French", "glossary", "SKILL", HARD_CAP_USD, out=quiet, rows=rows)
        check("billing stops after one call", fake.calls, 1)
        check("billing reason", work["_meta"]["stopped"].startswith("billing error"), True)
        # The cap: a reply that costs 4.80 USD leaves no room for a second request under 5
        # (one request's worst case is over 0.32 USD: 16 000 output tokens at 20 USD/M).
        if len(groups) > 1:
            fake = Fake([lambda kw: R("{}", U(0, 240000))] + [answer_all() for _ in groups])
            work = run(fake, "claude-opus-5-5", "fr", "French", "glossary", "SKILL", HARD_CAP_USD, out=quiet, rows=rows)
            check("cap stops", (fake.calls, work["_meta"]["stopped"].startswith("cap:")), (1, True))
            check("cap never passed", work["_meta"]["cost_usd"] <= HARD_CAP_USD, True)
        # A tiny cap sends nothing at all.
        fake = Fake([answer_all() for _ in groups])
        work = run(fake, "claude-opus-5-5", "fr", "French", "glossary", "SKILL", 0.01, out=quiet, rows=rows)
        check("tiny cap sends nothing", fake.calls, 0)
    # Arguments.
    check("refuses an out path in data/", main(["--table", "glossary", "--skill", __file__,
                                                "--out", os.path.join(ROOT, "data", "x.json"), "--dry-run"]), 2)
    check("refuses a cap over 5", main(["--table", "glossary", "--skill", __file__, "--out", "x.json",
                                        "--cap-usd", "6", "--dry-run"]), 2)
    check("refuses an unpriced model", main(["--table", "glossary", "--skill", __file__, "--out", "x.json",
                                             "--model", "claude-mystery", "--dry-run"]), 2)
    for line in bad:
        print("selftest: " + line)
    print("translate_api selftest: %s" % ("failed" if bad else "all checks passed"))
    return 1 if bad else 0


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if "--selftest" in argv:
        return selftest()
    table = _arg(argv, "--table")
    skill = _arg(argv, "--skill")
    out_path = _arg(argv, "--out")
    lang = _arg(argv, "--lang", "fr")
    model = _arg(argv, "--model", "claude-opus-5-5")
    limit = int(_arg(argv, "--limit", "0"))
    try:
        cap = float(_arg(argv, "--cap-usd", str(HARD_CAP_USD)))
    except ValueError:
        cap = -1.0
    if not table or not skill or not out_path:
        print(__doc__)
        return 2
    if not 0 < cap <= HARD_CAP_USD:
        print("refused: --cap-usd must be above 0 and at most %.2f" % HARD_CAP_USD)
        return 2
    if model not in PRICES:
        print("refused: no price for model '%s' (PRICES in this script); the cap needs one" % model)
        return 2
    out_abs = os.path.abspath(out_path)
    if out_abs.startswith(os.path.join(ROOT, "data") + os.sep):
        print("refused: drafts never go under data/ (--apply them after review)")
        return 2
    if not os.path.isfile(skill):
        print("refused: no skill file at %s" % skill)
        return 2
    lang_name = {"fr": "French"}.get(lang, lang)
    system_text = open(skill, encoding="utf-8").read()
    rows = worklist_rows(lang, table)
    groups = group_rows(table, rows, X.ui_msgids()[0] if table == "ui" else None)
    print("%s/%s: %d untranslated strings in %d groups; model %s; cap %.2f USD" % (lang, table, len(rows), len(groups), model, cap))
    if "--dry-run" in argv:
        worst = sum(worst_case_usd(model, system_text, json.dumps({k: rows[k]["en"] for k in g}, ensure_ascii=False)) for g in groups)
        print("dry run: nothing sent. Worst case of every request, uncached: %.2f USD" % worst)
        return 0
    dirty = data_tree_clean()
    if dirty:
        print("refused: data/ has untracked or modified files (only tracked text may go out): %s" % dirty)
        return 2
    import anthropic  # only for a real run: the selftest and a dry run need no SDK

    client = anthropic.Anthropic(max_retries=2)
    work = run(client, model, lang, lang_name, table, system_text, cap, limit)
    os.makedirs(os.path.dirname(out_abs) or ".", exist_ok=True)
    with open(out_abs, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(work, ensure_ascii=False, indent=2) + "\n")
    meta = work["_meta"]
    print("drafted %d, rejected %d, %d requests, cost %.4f USD -> %s" % (meta["drafted"], meta["rejected"], meta["requests"], meta["cost_usd"], out_abs))
    if meta["stopped"]:
        print("STOPPED: " + meta["stopped"])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
