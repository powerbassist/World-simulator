#!/usr/bin/env bash
# Greps every tracked file for real-world names banned by
# docs/fictionalization.md. Zero hits, or the content is wrong.
#
#   bash tools/check_names.sh             # the check over this checkout
#   bash tools/check_names.sh --selftest  # the scan against a synthetic repo
#
# ONE `git grep` over the tracked files, not one `grep` per file: the per-file
# loop forked ~10 800 processes and took 5 to 6 minutes on Windows, where a
# process start is slow (43 s for CI's whole checks job on Linux); one call takes
# seconds. `git grep` reads the same set the loop read -- the tracked files'
# working-tree contents -- and its -w is at least as strict as GNU grep's: its word
# characters are ASCII letters, digits and `_`, so it can report a hit next to a
# non-ASCII letter that GNU grep would not, and never misses one GNU grep reports.
set -euo pipefail
cd "$(dirname "$0")/.."

# banned_names.txt has two sections. Everything before the `[places]` marker is
# checked in every tracked file; everything after it is checked in data/companies/
# ONLY, because those names are real companies that are ALSO real places -- and
# docs/fictionalization.md says both that a firm may not reuse a real company's name
# and that cities and regions are real. V2.2a imported Santander, a bank and a city of
# 173 635 people, and a check that is permanently red over a real place is one nobody
# reads. The ban that matters there is the one about firms, so it is scoped to the
# file a firm's name lives in.
#
# A Windows checkout has the list with CRLF endings (autocrlf). No stripping is needed:
# `git grep -f` drops a carriage return before a line feed when it reads a pattern file,
# a CR-only line counts as blank below, and the marker match is unanchored at its end.
# The selftest's list is CRLF to keep it that way.
split_patterns() {  # LIST ALL_OUT PLACES_OUT
  { grep -v '^#' "$1" || true; } | { grep -v '^[[:space:]]*$' || true; } \
    | awk -v all="$2" -v places="$3" '/^\[places\]/{p=1; next} {print > (p ? places : all)}'
}

# Prints every hit as path:line:text. Returns 0 on no hit, 1 on a hit, 2 on an error.
scan() {  # ALL_PATTERNS PLACES_PATTERNS, run from the repository's top level
  local rc found=0
  # -w, because the banned list holds short real party names that are honest
  # substrings of longer invented ones -- one Dutch and one British case in
  # data/parties/. Without word boundaries the check rejects content it should
  # pass, and an always-red check is one nobody reads. -I skips binary files.
  #
  # The exclusions:
  # - V4.2's ultra pass-1: the committed Obsidian vault's third-party plugin
  #   bundles (excalidraw's main.js alone) trip real-name hits in minified JS
  #   nobody authored. The vault is editor config, not game content -- the
  #   same reason addons/ is editor-side -- and the fictionalization rule
  #   guards content.
  # - The vendored Impeccable design skill (Apache-2.0, see REUSE.toml): its font
  #   index lists real typefaces by name. Agent tooling, not game content.
  # - V3.7 Phase B3: the portrait reference attribution is the ONE committed
  #   file where real names must appear -- the Commons photo licences for the
  #   img2img references require crediting the source works. The
  #   fictionalization rule still guards every other file, and the names here
  #   are source-credits, not content. See docs/fictionalization.md.
  rc=0
  git --no-pager grep -I -n -F -w -f "$1" -- . \
    ':(exclude)tools/banned_names.txt' ':(exclude)tools/check_names.sh' \
    ':(exclude).obsidian' ':(exclude).claude/skills/impeccable' \
    ':(exclude)docs/portrait-attribution.md' || rc=$?
  case "$rc" in 0) found=1 ;; 1) ;; *) echo "check_names: git grep failed ($rc)" >&2; return 2 ;; esac
  if [ -s "$2" ]; then
    rc=0
    git --no-pager grep -I -n -F -w -f "$2" -- 'data/companies/' || rc=$?
    case "$rc" in 0) found=1 ;; 1) ;; *) echo "check_names: git grep failed ($rc)" >&2; return 2 ;; esac
  fi
  return "$found"
}

# The scan against a throwaway repository with synthetic names: a hit, a substring
# that -w must pass, each exclusion, the [places] scope, a binary file, and a CRLF
# list. Each case is one a past change could break without the real check noticing,
# since the real tree has zero hits either way.
selftest() (  # a subshell: its cd and its trap end with it
  t="$(mktemp -d)"
  trap 'cd / && rm -rf "$t"' EXIT
  printf '# synthetic list\r\nVexmont Draal\r\nVXD\r\n\r\n[places]\r\nQuellport\r\n' > "$t/list.txt"
  split_patterns "$t/list.txt" "$t/all.txt" "$t/places.txt"
  mkdir -p "$t/repo" && cd "$t/repo"
  git init -q .
  git config core.autocrlf false  # the files below are LF on purpose; no conversion warnings
  mkdir -p content docs data/companies .obsidian/plugins .claude/skills/impeccable tools
  echo "the minister Vexmont Draal said" > content/hit.txt
  echo "VXDomain is an invented word" > content/substring.txt
  echo "Vexmont Draal in minified JS" > .obsidian/plugins/main.js
  echo "Vexmont Draal, a typeface" > .claude/skills/impeccable/fonts.md
  echo "credit: Vexmont Draal" > docs/portrait-attribution.md
  echo "Vexmont Draal" > tools/banned_names.txt
  echo '{"name": "Quellport Steel"}' > data/companies/firm.json
  echo "the harbour of Quellport" > docs/city.md
  printf 'Vexmont Draal\0binary' > content/blob.dat
  git add -A
  rc=0; out="$(scan "$t/all.txt" "$t/places.txt")" || rc=$?
  want=$'content/hit.txt:1:the minister Vexmont Draal said\ndata/companies/firm.json:1:{"name": "Quellport Steel"}'
  if [ "$rc" -ne 1 ] || [ "$out" != "$want" ]; then
    printf 'check_names --selftest: FAIL (exit %s), got:\n%s\nwanted:\n%s\n' "$rc" "$out" "$want" >&2
    return 1
  fi
  git rm -q -f content/hit.txt data/companies/firm.json
  rc=0; out="$(scan "$t/all.txt" "$t/places.txt")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -n "$out" ]; then
    printf 'check_names --selftest: FAIL on a clean tree (exit %s): %s\n' "$rc" "$out" >&2
    return 1
  fi
  echo "check_names --selftest: ok"
)

if [ "${1:-}" = "--selftest" ]; then
  selftest
  exit
fi

pattern_file="$(mktemp)"
places_file="$(mktemp)"
trap 'rm -f "$pattern_file" "$places_file"' EXIT
split_patterns tools/banned_names.txt "$pattern_file" "$places_file"

rc=0
scan "$pattern_file" "$places_file" || rc=$?
if [ "$rc" -eq 1 ]; then
  echo "check_names: banned real-world names found above" >&2
  exit 1
elif [ "$rc" -ne 0 ]; then
  exit 2
fi
echo "check_names: zero hits"
