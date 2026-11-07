"""The lint over numbers shipped about real relations, and the private basis behind them.

docs/design/v5.3-ab.md section 6 (b): a person row may ship `start_regard_offset`, one
number under an altered name. Who it winks at and why lives in a gitignored local file,
never in the repository, so this lint has two halves:

  - EVERYWHERE, CI included: every shipped offset is a number inside [-0.30, +0.30] with
    two decimals. The loader refuses the same (Person.from_dict); this says it without a
    Godot, over every nation at once, before a data PR is opened.
  - ONLY WHERE THE PRIVATE FILE IS PRESENT: every non-zero offset on a marked person has
    a basis line. Presence only: it cannot check that a line is true, a person does that.

The private file, tools/private/skills_basis.json, is keyed by the game's id:

    {"<person id>": {"real_inspired": true, "regard_offset": "<one line, with its source>"}}

`real_inspired` is the mark. A worktree does not carry a gitignored file, so --basis
points at the main checkout's copy. A basis failure names only the id, and the id on
that line IS the mark: read it locally, never paste it into a PR, a commit or a job.

    python tools/check_skills.py [--basis PATH]
    python tools/check_skills.py --selftest

The skills block (docs/design/v5.3-skills.md) adds its numbers and basis lines here.
"""
import argparse
import glob
import json
import os
import sys

OFFSET = "start_regard_offset"
OFFSET_MAX = 0.30
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_BASIS = os.path.join(ROOT, "tools", "private", "skills_basis.json")


def offset_problems(people):
    """Lines for every shipped offset that breaks the range or the two decimals."""
    out = []
    for person in people:
        if OFFSET not in person:
            continue
        value = person[OFFSET]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            out.append("%s: %s is not a number" % (person.get("id", "?"), OFFSET))
        elif abs(value) > OFFSET_MAX or abs(value - round(value, 2)) > 1e-9:
            out.append("%s: %s %s is outside [-0.30, +0.30] or past two decimals" % (person.get("id", "?"), OFFSET, value))
    return out


def basis_problems(people, basis):
    """Lines for a marked person's offset with no basis, and a row naming nobody."""
    out = []
    known = {person.get("id") for person in people}
    for person_id in sorted(set(basis) - known):
        out.append("%s: in the basis file, not in data/people" % person_id)
    for person in people:
        person_id = person.get("id")
        row = basis.get(person_id)
        if not person.get(OFFSET) or not isinstance(row, dict) or row.get("real_inspired") is not True:
            continue
        if not str(row.get("regard_offset", "")).strip():
            out.append("%s: no basis line" % person_id)
    return out


def load_people():
    people = []
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "people", "*.json"))):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        people.extend(data["people"] if isinstance(data, dict) else data)
    return people


def selftest():
    good = [{"id": "A_a", OFFSET: -0.30}, {"id": "A_b", OFFSET: 0.07}, {"id": "A_c", OFFSET: 0}, {"id": "A_d"}]
    if offset_problems(good):
        print("SELFTEST FAIL: a good row was refused: %r" % offset_problems(good))
        return 1
    for bad in (0.31, -0.31, 0.255, "0.2", True):
        if not offset_problems([{"id": "A_a", OFFSET: bad}]):
            print("SELFTEST FAIL: %r was taken" % (bad,))
            return 1
    marked = {"A_a": {"real_inspired": True, "regard_offset": "a line"}, "A_b": {"real_inspired": True}, "A_c": {"regard_offset": ""}}
    people = [{"id": "A_a", OFFSET: 0.1}, {"id": "A_b", OFFSET: 0.1}, {"id": "A_c", OFFSET: 0.1}, {"id": "A_d", OFFSET: 0.1}]
    # A_b is marked with no line; A_c is not marked; A_d is not in the file at all.
    if basis_problems(people, marked) != ["A_b: no basis line"]:
        print("SELFTEST FAIL: basis_problems returned %r" % basis_problems(people, marked))
        return 1
    if basis_problems([{"id": "A_a", OFFSET: 0}], {"A_a": {"real_inspired": True}}):
        print("SELFTEST FAIL: a zero offset asked for a basis")
        return 1
    if basis_problems([], {"A_z": {}}) != ["A_z: in the basis file, not in data/people"]:
        print("SELFTEST FAIL: a row naming nobody passed")
        return 1
    print("check_skills selftest: all checks passed")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--basis", default=DEFAULT_BASIS)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    people = load_people()
    problems = offset_problems(people)
    if os.path.isfile(args.basis):
        with open(args.basis, encoding="utf-8") as f:
            problems += basis_problems(people, json.load(f))
        checked = "numbers and basis"
    else:
        checked = "numbers only, no private file"
    for line in problems:
        print(line)
    shipped = sum(1 for person in people if person.get(OFFSET))
    print("check_skills: %d people, %d non-zero offsets, %s: %s" % (len(people), shipped, checked, "FAILED" if problems else "clean"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
