#!/usr/bin/env bash
# Preflight for the Godot MCP toolkit bridge. Prints one decisive line per check
# and never a raw log dump.
#
# Exists because the stack it replaced failed silently for months: an orphaned
# server held its port, every later session died on EADDRINUSE, and the only
# symptom anybody saw was tools that were not there. Nothing in that chain ever
# said why. This script is the thing that says why.
#
#   bash tools/check_mcp.sh
#
# Exit 1 if a REQUIRED check fails -- the bridge could not run at all. The editor
# and the running game are reported but never required: not having Godot open is
# a normal state, not a broken one.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
warned=0
ok()   { printf '[ OK ] %s\n' "$1"; }
info() { printf '[ -- ] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; warned=1; return 0; }
bad()  { printf '[FAIL] %s\n' "$1"; [ "${2:-required}" = required ] && fail=1; return 0; }

# -- 1. Node -----------------------------------------------------------------
# The bridge package declares engines >=22. A too-old node fails deep inside an
# import rather than at the entry point, so check the version, not just presence.
if ! command -v node >/dev/null 2>&1; then
  bad "node not on PATH -- install Node.js 22 or newer"
else
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$node_major" -lt 22 ]; then
    bad "node $(node -v) is too old -- the bridge needs 22 or newer"
  else
    ok "node $(node -v)"
  fi
fi

# -- 2. The bridge itself ----------------------------------------------------
# Read the command out of .mcp.json rather than hardcoding it here, so the check
# validates the config that is actually used instead of a second copy of it.
mcp_json=".mcp.json"
if [ ! -f "$mcp_json" ]; then
  bad ".mcp.json missing -- Project > Tools > MCP Toolkit > Write .mcp.json, or copy the form in docs/tooling.md"
else
  entry="$(python - <<'PY' 2>/dev/null
import io, json, sys
try:
    d = json.load(io.open(".mcp.json", encoding="utf-8"))
except Exception:
    sys.exit(1)
servers = d.get("mcpServers") or {}
key = next((k for k in servers if "godot-mcp" in k.lower()), None)
if not key:
    sys.exit(2)
e = servers[key]
print(key)
print(e.get("command", ""))
print("\t".join(e.get("args") or []))
print((e.get("env") or {}).get("GODOT_MCP_EDITOR_PORT", ""))
PY
)"
  case "$?" in
    1) bad ".mcp.json is not valid JSON" ;;
    2) bad ".mcp.json has no godot-mcp* server entry" ;;
    *)
      srv_key="$(printf '%s\n' "$entry" | sed -n 1p)"
      srv_cmd="$(printf '%s\n' "$entry" | sed -n 2p)"
      srv_arg="$(printf '%s\n' "$entry" | sed -n 3p | cut -f1)"
      # Exported for the registry check below, which compares the pin against the
      # port the editor actually bound.
      CHECK_MCP_EDITOR_PIN="$(printf '%s
' "$entry" | sed -n 4p)"
      export CHECK_MCP_EDITOR_PIN
      ok ".mcp.json registers '$srv_key' as: $srv_cmd $srv_arg"
      if [ -n "$CHECK_MCP_EDITOR_PIN" ]; then
        ok "editor port pinned to $CHECK_MCP_EDITOR_PIN"
      else
        # Not a failure, but worth naming: with no pin the bridge reads the port
        # out of the registry, and a registry that says -1 (game running, editor
        # closed) crashes bridge 1.0.0 at startup with ERR_INVALID_URL.
        info "no editor port pin -- the bridge falls back to registry discovery"
      fi
      # A node-direct registration names a file; resolve it. An npx registration
      # names a package and is resolved by npm at launch, so there is nothing
      # here to stat -- report it rather than pretending to have checked it.
      if [ "$srv_cmd" = "node" ] && [ -n "$srv_arg" ]; then
        if [ -f "$srv_arg" ]; then
          ok "bridge entry point present"
        else
          bad "bridge entry point missing: $srv_arg -- npm install -g @npgamedev/godot-mcp-server"
        fi
      else
        info "bridge is launched through '$srv_cmd'; resolution happens at launch (needs the npm registry on a cold cache)"
      fi
      ;;
  esac
fi

# -- 3. The addon side -------------------------------------------------------
if [ -d addons/godot_mcp_toolkit ]; then
  ok "addons/godot_mcp_toolkit present"
else
  bad "addons/godot_mcp_toolkit missing -- reinstall it, see docs/tooling.md"
fi

if grep -q 'godot_mcp_toolkit/plugin.cfg' project.godot; then
  ok "plugin enabled in project.godot"
else
  bad "project.godot does not enable godot_mcp_toolkit -- Project Settings > Plugins"
fi

# The old mkdevkit stack committed three autoloads pointing at a gitignored
# addon. Nothing should reintroduce them; a stray one is a fresh-clone error on
# every run, so it is checked rather than remembered.
if grep -q 'addons/godot_mcp/' project.godot; then
  bad "project.godot still references the removed addons/godot_mcp -- delete those lines"
else
  ok "no stale addons/godot_mcp reference"
fi

# An editor addon that registers an autoload writes it into project.godot on enable,
# pointing into gitignored addons/. Committing that gives a fresh clone an autoload
# whose script does not exist -- measured as three ERROR lines per process, once per
# test, so noise rather than breakage, but noise nobody chose. Checked against HEAD
# and the index rather than the working tree, because the working tree legitimately
# carries these while the plugins are enabled.
#
# THE WHOLE SECTION IS CHECKED, NOT ONE ADDON'S LINE. The first version grepped
# `^MCP.*=.*addons/godot_mcp` -- two conditions an entry had to meet to be seen, and
# an enabled DialogueManager meets neither: it is not named MCP*, and it registers as
# `uid://c3rodes2l3gxb` rather than as a path. It sat in the working tree unseen until
# an external review found it. AGENTS.md's rule is "no autoloads in the game code", so
# the guard is now that rule rather than a list of the ways one addon writes itself in.
#
# THE RULE HAS ONE STATED EXCEPTION, AND THE GUARD READS IT FROM GIT. V2.4b adopted
# dialogue_manager by committing the addon whole, so its autoload and its plugin.cfg
# resolve on a fresh clone; flagging them warned on every run about a decision already
# taken. An entry is therefore stray only when what it points at is NOT TRACKED --
# AGENTS.md's "src/ may reference an addon file only if that file is committed", applied
# to project.godot. A uid:// entry cannot be resolved here, so it is still flagged.
tracked() { case "$1" in res://*) git ls-files --error-unmatch -- "${1#res://}" >/dev/null 2>&1 ;; *) return 1 ;; esac; }
if git rev-parse --git-dir >/dev/null 2>&1; then
  # What the NEXT commit will contain: the index when project.godot is staged,
  # HEAD otherwise. Checking HEAD first would keep warning about a line the index
  # has already dropped.
  if git diff --cached --quiet -- project.godot 2>/dev/null; then
    autoload_src="HEAD:project.godot"
    autoload_where="the committed project.godot"
  else
    autoload_src=":project.godot"
    autoload_where="the STAGED project.godot"
  fi
  # awk rather than grep: an autoload is defined by the SECTION it sits in, not by
  # anything about its own line, so the section is what has to be read.
  autoloads="$(git show "$autoload_src" 2>/dev/null | awk '
    /^\[autoload\]/ { inside = 1; next }
    /^\[/           { inside = 0 }
    inside && /=/    { split($0, kv, "="); gsub(/["*]/, "", kv[2]); print kv[1] "=" kv[2] }
  ' | while IFS= read -r entry; do tracked "${entry#*=}" || printf '%s
' "$entry"; done)"
  if [ -n "$autoloads" ]; then
    warn "$autoload_where carries an autoload whose script is not tracked -- a fresh clone logs each as a missing script. Drop it from what you commit:"
    printf '         %s
' $autoloads
  else
    ok "every autoload in what the next commit would contain points at a tracked script"
  fi

  # The same failure through the other door. `enabled=` names plugin.cfg paths, and
  # every addon here is gitignored by AGENTS.md's rule -- including the toolkit's own,
  # which is why tracked-ness is NOT the test. The toolkit is the one this project
  # expects (the check above requires it); anything else in that list is whatever this
  # machine happens to have installed, and a fresh clone gets an editor error per entry.
  extra_plugins="$(git show "$autoload_src" 2>/dev/null \
    | sed -n 's/^enabled=PackedStringArray(\(.*\))$/\1/p' \
    | tr ',' '\n' | tr -d ' "' | sed 's|^res://||' \
    | grep -v '^$' | grep -v '^addons/godot_mcp_toolkit/plugin.cfg$'     | while IFS= read -r cfg; do tracked "res://$cfg" || printf '%s
' "$cfg"; done || true)"
  if [ -n "$extra_plugins" ]; then
    warn "$autoload_where enables an untracked addon beyond the toolkit -- a fresh clone errors on each. Drop them from enabled= in what you commit:"
    printf '         %s\n' $extra_plugins
  else
    ok "no stray addon enabled in what the next commit would contain"
  fi
fi

# -- 4. Registry -------------------------------------------------------------
# The bridge discovers the editor and runtime ports by matching its own cwd
# against this file. A missing entry is the normal state with Godot closed, so it
# is informational; a STALE entry (dead pid) is the failure worth naming.
registry="${APPDATA:-$HOME/AppData/Roaming}/godot-mcp-toolkit/projects.json"
if [ ! -f "$registry" ]; then
  info "no registry yet at $registry -- written the first time the toolkit binds a port"
else
  # pwd -W, not $PWD: git bash reports /f/Dev/... while Godot publishes F:/Dev/...,
  # and the two never compare equal however they are normalised.
  python - "$registry" "$(pwd -W)" <<'PY'
import io, json, os, subprocess, sys

reg_path, cwd = sys.argv[1], sys.argv[2]

def norm(p):
    return p.replace("\\", "/").rstrip("/").lower()

try:
    reg = json.load(io.open(reg_path, encoding="utf-8"))
except Exception:
    print("[FAIL] registry is not valid JSON: %s" % reg_path)
    sys.exit(0)

projects = reg.get("by_path", {}) if isinstance(reg, dict) else {}
me = norm(cwd)
match = None
for key, val in (projects.items() if isinstance(projects, dict) else []):
    if norm(key) == me or norm(str(val.get("path", ""))) == me:
        match = (key, val)
        break

if match is None:
    print("[ -- ] no registry entry for this project -- open it in Godot, or run the game, to publish one")
    sys.exit(0)

key, val = match
alive = set()
try:
    out = subprocess.run(
        ["powershell", "-NoProfile", "-Command", "Get-Process | ForEach-Object { $_.Id }"],
        capture_output=True, text=True, timeout=30,
    ).stdout
    alive = {int(x) for x in out.split() if x.strip().isdigit()}
except Exception:
    pass

def report(label, pid, port):
    port = int(port or 0)
    if not pid or port <= 0:
        # A -1 port is how the toolkit says "this channel is not up". Worth naming:
        # bridge 1.0.0 interpolates a discovered port straight into a WebSocket URL,
        # so ws://127.0.0.1:-1 throws ERR_INVALID_URL and takes the whole server down
        # at startup. GODOT_MCP_EDITOR_PORT in .mcp.json is what keeps that
        # unreachable -- see docs/tooling.md.
        print("[ -- ] %s: not running" % label)
        return
    pid = int(pid)
    if not alive:
        print("[ -- ] %s: pid %s port %s (could not read the process list to confirm)" % (label, pid, port))
    elif pid in alive:
        print("[ OK ] %s: pid %s on port %s" % (label, pid, port))
    else:
        print("[FAIL] %s: registry names dead pid %s on port %s -- STALE entry; "
              "restart Godot, or delete %s" % (label, pid, port, reg_path))

print("[ OK ] registry entry for %s" % key)
report("editor channel", val.get("pid"), val.get("port"))
report("runtime channel", val.get("runtime_pid"), val.get("runtime_port"))

pin = os.environ.get("CHECK_MCP_EDITOR_PIN", "")
live_editor_port = int(val.get("port") or 0)
if pin and live_editor_port > 0 and int(pin) != live_editor_port:
    print("[FAIL] .mcp.json pins the editor to port %s but the editor bound %d -- "
          "the bridge will dial a port nobody is listening on. Free port %s and "
          "restart Godot, or change the pin." % (pin, live_editor_port, pin))
elif pin and live_editor_port > 0:
    print("[ OK ] editor pin %s matches the bound port" % pin)

token = val.get("token_path") or ""
if not token:
    print("[ -- ] entry publishes no token path")
elif os.path.isfile(token):
    print("[ OK ] auth token readable")
else:
    print("[FAIL] auth token missing at %s -- restart the editor to regenerate it" % token)
PY
fi

# -- 5. Listeners ------------------------------------------------------------
# Names what is actually bound in the two bands. The editor and the game each own
# their listener, so a port here with nothing in the registry is a process the
# bridge cannot find -- worth seeing, and invisible from inside Godot.
listeners="$(netstat -ano 2>/dev/null | grep LISTENING | grep -Eo '127\.0\.0\.1:(65[5-8][0-9]) +[^ ]+ +LISTENING +[0-9]+' || true)"
if [ -z "$listeners" ]; then
  info "nothing listening in 6550-6560 (editor) or 6570-6585 (runtime)"
else
  printf '%s\n' "$listeners" | awk '{print "[ OK ] listening " $1 " (pid " $NF ")"}'
fi

# -- verdict -----------------------------------------------------------------
if [ "$fail" -ne 0 ]; then
  echo "check_mcp: the bridge cannot run -- fix the FAIL lines above" >&2
  exit 1
fi
if [ "$warned" -ne 0 ]; then
  echo "check_mcp: bridge side is sound, with warnings above"
  exit 0
fi
echo "check_mcp: bridge side is sound"
