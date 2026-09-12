"""The ComfyUI HTTP discipline shared by the portrait and background
generators -- V3.7. Extracted from tools/portraits_generate.py when a second
caller appeared, not copied: two copies of a path guard is how one of them
quietly stops agreeing with the other.

Every filesystem path goes through _confined(), every URL through _open(),
every server-issued string through _safe_segment(). The one allowed
destination is the local ComfyUI -- scheme http, hostname in ALLOWED_HOSTS,
asserted on every request. Stdlib only."""

import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOST = "127.0.0.1"
PORT = 8188
ALLOWED_HOSTS = ("127.0.0.1", "localhost")


def _confined(path, root):
    """Every filesystem path this module's callers touch is normalized here and
    proven to resolve inside its declared root, so no joined or discovered path
    can walk out of the directories the recipe owns."""
    resolved = Path(path).resolve()
    base = Path(root).resolve()
    if base not in resolved.parents and resolved != base:
        raise RuntimeError("path '%s' escapes its allowed root '%s'" % (path, root))
    return resolved


## The loader's own namespacing rule (tests/test_people.gd checks the same
## thing): a person id is <NATION>_<surname>. Every output filename the
## generators build starts from a person id read out of a JSON file, so the ids
## are validated against the scheme before they are joined -- the register is
## trusted content, but a path is not the place to find out.
ID_SCHEME = re.compile(r"^[A-Z]{3}_[a-z][a-z0-9_]*$")


def _checked_id(person_id):
    if not ID_SCHEME.match(person_id):
        raise RuntimeError("person id '%s' does not match the register's <NATION>_<surname> scheme" % person_id)
    return person_id


## Anything that reaches a URL path or query -- the server-issued prompt id, a
## returned filename -- passes through here first: no parent-directory walks,
## no drive letters, no backslashes, no leading slash. ComfyUI subfolders may
## contain "/" (they are relative paths), everything else may not.
def _safe_segment(value, what, allow_slash=False):
    if value is None:
        raise RuntimeError("unsafe %s from the API: %r" % (what, value))
    text = str(value)
    if text == "":
        return text  # the API's "no subfolder" -- empty cannot traverse
    if text.startswith(("/", "\\")) or ":" in text or "\\" in text or ".." in text:
        raise RuntimeError("unsafe %s from the API: %r" % (what, text))
    if "/" in text and not allow_slash:
        raise RuntimeError("unsafe %s from the API: %r" % (what, text))
    return text


def _open(path, data=None, headers=None, timeout=90):
    """Every request goes through here, and here is where the one allowed
    destination is enforced: plain http to the local ComfyUI and nothing
    else, ever."""
    url = urllib.parse.urlunparse(("http", "%s:%d" % (HOST, PORT), path, "", "", ""))
    parts = urllib.parse.urlparse(url)
    if parts.scheme != "http" or parts.hostname not in ALLOWED_HOSTS:
        raise RuntimeError("refusing non-local API URL: %s" % url)
    req = urllib.request.Request(url, data=data, headers=headers or {})
    return urllib.request.urlopen(req, timeout=timeout)


def djb2(s):
    """Stable across languages and engine versions -- String.hash() is neither
    guaranteed across Godot bumps nor matching Python. The seed must survive
    re-runs, so it gets its own five lines."""
    h = 5381
    for c in s.encode("utf-8"):
        h = ((h * 33) + c) & 0xFFFFFFFF
    return h


def queue(workflow: dict) -> str:
    """POST one API-format workflow, return the server's prompt id. Every
    top-level key of the workflow must be a node the server knows -- a stray
    "_comment" is a 500 with no useful body."""
    payload = json.dumps({"prompt": workflow, "client_id": "ws-portraits"}).encode()
    prompt_id = json.load(_open("/prompt", data=payload,
                                headers={"Content-Type": "application/json"}))["prompt_id"]
    return _safe_segment(prompt_id, "prompt id")


def outputs(prompt_id: str, timeout_s: int = 600) -> dict:
    """Poll /history until the prompt completes; return
    {node_id: [image meta, ...]}. Raises on error status or timeout."""
    for _ in range(timeout_s // 2):
        time.sleep(2)
        history = json.loads(_open("/history/" + prompt_id).read())
        if prompt_id not in history:
            continue
        entry = history[prompt_id]
        status = entry.get("status", {})
        if status.get("status_str") == "error":
            raise RuntimeError("ComfyUI error on prompt %s" % prompt_id)
        if not status.get("completed"):
            continue
        return {node: node_out.get("images", [])
                for node, node_out in entry["outputs"].items()}
    raise RuntimeError("timed out waiting for %s" % prompt_id)


def fetch(meta: dict) -> bytes:
    """Download one output image by its server-issued metadata."""
    query = urllib.parse.urlencode({
        "filename": _safe_segment(meta["filename"], "image filename"),
        "subfolder": _safe_segment(meta.get("subfolder", ""), "image subfolder", allow_slash=True),
        "type": _safe_segment(meta["type"], "image type")})
    return _open("/view?" + query).read()


def upload_image(data: bytes, name: str) -> str:
    """POST one PNG into ComfyUI's input dir; return the name LoadImage wants."""
    boundary = "ws-portraits-boundary"
    body = (("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n"
             "Content-Type: image/png\r\n\r\n" % (boundary, name)).encode()
            + data + ("\r\n--%s--\r\n" % boundary).encode())
    meta = json.loads(_open("/upload/image", data=body, headers={
        "Content-Type": "multipart/form-data; boundary=%s" % boundary}).read())
    return _safe_segment(meta.get("name"), "uploaded image name")
