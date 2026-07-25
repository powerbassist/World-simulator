#!/usr/bin/env bash
# Greps every tracked file for real-world names banned by
# docs/fictionalization.md. Zero hits, or the content is wrong.
set -euo pipefail
cd "$(dirname "$0")/.."

pattern_file="$(mktemp)"
trap 'rm -f "$pattern_file"' EXIT
grep -v '^#' tools/banned_names.txt | grep -v '^[[:space:]]*$' > "$pattern_file"

hits=0
while IFS= read -r f; do
  case "$f" in
    tools/banned_names.txt|tools/check_names.sh) continue ;;
  esac
  if grep -InF -f "$pattern_file" -- "$f" 2>/dev/null; then
    hits=1
  fi
done < <(git ls-files)

if [ "$hits" -ne 0 ]; then
  echo "check_names: banned real-world names found above" >&2
  exit 1
fi
echo "check_names: zero hits"
