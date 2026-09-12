"""Cross-checks every portraits/backgrounds workflow JSON against the live
ComfyUI /object_info, so the templates are written against real node
signatures instead of guesses. Run with ComfyUI listening on 127.0.0.1:8188.

A missing class_type is a 500 from /prompt with no useful body -- the same
trap as the "_comment" key documented in portraits_generate.py -- so this
check exists to catch the lie at the template, not at generation time.

Checks, per tools/*_workflow.json: every class_type exists on the server;
every input key is a name that node actually takes; every STRING input whose
server spec carries a value list (a combo box -- model names, enum knobs)
holds a value FROM that list; every [node_id, slot] connection points at a
node present in the same file. The value check is what the first generation
run bought: a key can exist and still hold "face_yolov8m.pt" where the server
lists "bbox/face_yolov8m.pt" -- a 400 with a uselessly short body at queue
time, caught here at template time instead. Exit 1 naming the first lie.

The one allowed destination is the local ComfyUI and nothing else -- same
clamp as comfy_client._open(): scheme http, hostname in ALLOWED_HOSTS,
asserted before every request."""

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

HOST = "127.0.0.1"
PORT = 8188
ALLOWED_HOSTS = ("127.0.0.1", "localhost")

TOOLS = Path(__file__).resolve().parent


def _get(path: str, timeout: int = 60):
    url = urllib.parse.urlunparse(("http", "%s:%d" % (HOST, PORT), path, "", "", ""))
    parts = urllib.parse.urlparse(url)
    if parts.scheme != "http" or parts.hostname not in ALLOWED_HOSTS:
        raise RuntimeError("refusing non-local API URL: %s" % url)
    return urllib.request.urlopen(url, timeout=timeout)


def main() -> int:
    info = json.load(_get("/object_info"))
    failed = False
    for path in sorted(TOOLS.glob("*_workflow.json")):
        wf = json.loads(path.read_text(encoding="utf-8"))
        for node_id, node in sorted(wf.items()):
            ct = node["class_type"]
            if ct not in info:
                print("FAIL %s[%s]: class_type '%s' not in /object_info" % (path.name, node_id, ct))
                failed = True
                continue
            accepted = set()
            for group in ("required", "optional"):
                accepted |= set(info[ct]["input"].get(group, {}).keys())
            for key, value in node["inputs"].items():
                if key not in accepted:
                    print("FAIL %s[%s].%s: node takes %s" % (path.name, node_id, key, sorted(accepted)))
                    failed = True
                    continue
                spec = None
                for group in ("required", "optional"):
                    group_spec = info[ct]["input"].get(group, {}).get(key)
                    if group_spec is not None:
                        spec = group_spec
                        break
                # A combo input's spec is [[...values...], {...}]: a string
                # value must be one of them, or /prompt refuses the whole
                # graph with only the node id as explanation. __NAME__ blanks
                # are the recipe's injection placeholders (the generator
                # overwrites them per run) and are exempt.
                if (isinstance(value, str) and isinstance(spec, list)
                        and len(spec) >= 1 and isinstance(spec[0], list)
                        and not (value.startswith("__") and value.endswith("__"))):
                    if value not in spec[0]:
                        print("FAIL %s[%s].%s: %r not in %s" % (path.name, node_id, key, value, spec[0]))
                        failed = True
                if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str):
                    if value[0] not in wf:
                        print("FAIL %s[%s].%s: connects to absent node '%s'" % (path.name, node_id, key, value[0]))
                        failed = True
        print("%s: %d nodes checked" % (path.name, len(wf)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
