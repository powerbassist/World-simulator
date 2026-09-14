#!/usr/bin/env bash
# Greps every tracked file for real-world names banned by
# docs/fictionalization.md. Zero hits, or the content is wrong.
set -euo pipefail
cd "$(dirname "$0")/.."

pattern_file="$(mktemp)"
places_file="$(mktemp)"
trap 'rm -f "$pattern_file" "$places_file"' EXIT

# banned_names.txt has two sections. Everything before the `[places]` marker is
# checked in every tracked file; everything after it is checked in data/companies/
# ONLY, because those names are real companies that are ALSO real places -- and
# docs/fictionalization.md says both that a firm may not reuse a real company's name
# and that cities and regions are real. V2.2a imported Santander, a bank and a city of
# 173 635 people, and a check that is permanently red over a real place is one nobody
# reads. The ban that matters there is the one about firms, so it is scoped to the
# file a firm's name lives in.
awk '/^\[places\]/{p=1; next} {print > (p ? "'"$places_file"'" : "'"$pattern_file"'")}'   <(grep -v '^#' tools/banned_names.txt | grep -v '^[[:space:]]*$')

hits=0
while IFS= read -r f; do
  case "$f" in
    tools/banned_names.txt|tools/check_names.sh) continue ;;
    # V3.7 Phase B3: the portrait reference attribution is the ONE committed
    # file where real names must appear -- the Commons photo licences for the
    # img2img references require crediting the source works. The
    # fictionalization rule still guards every other file, and the names here
    # are source-credits, not content. See docs/fictionalization.md.
    docs/portrait-attribution.md) continue ;;
  esac
  # -w, because the banned list holds short real party names that are honest
  # substrings of longer invented ones -- one Dutch and one British case in
  # data/parties/. Without word boundaries the check rejects content it should
  # pass, and an always-red check is one nobody reads.
  if grep -InFw -f "$pattern_file" -- "$f" 2>/dev/null; then
    hits=1
  fi
  case "$f" in
    data/companies/*)
      if [ -s "$places_file" ] && grep -InFw -f "$places_file" -- "$f" 2>/dev/null; then
        hits=1
      fi
      ;;
  esac
done < <(git ls-files)

if [ "$hits" -ne 0 ]; then
  echo "check_names: banned real-world names found above" >&2
  exit 1
fi
echo "check_names: zero hits"
