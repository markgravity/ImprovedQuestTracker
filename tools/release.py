"""Release helpers, run by the GitHub workflow (.github/workflows/release.yml)
on every version tag (v1.0.0, v1.1.0-beta1...). Python standard library only.

    python tools/release.py check v1.0.0   the tag matches the TOC's version
    python tools/release.py notes          this version's CHANGELOG section
    python tools/release.py curseforge     upload the zip to CurseForge
    python tools/release.py title          the release title stem (TOC ## Title)
    python tools/release.py versions [txt] list CurseForge game versions (optionally filtered)

CurseForge needs CF_API_KEY: a GitHub secret in CI, or a line in the local
.env (git-ignored) when run by hand. The
project ID comes from the TOC (## X-Curse-Project-ID), the game versions from
CF_GAME_VERSION (default 1.60.1, WoW Forever) or CF_GAME_VERSION_ID; both take
a comma-separated list (e.g. "1.60.1,5.5.3" for Forever and MoP Classic).
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = os.environ.get("ADDON") or next(ROOT.glob("*.toc")).stem
TITLE = os.environ.get("ADDON_TITLE")
API = "https://wow.curseforge.com/api"


def load_env():
    """Fill missing environment variables from a local, git-ignored .env (KEY=value lines)."""
    env = ROOT / ".env"
    if not env.is_file():
        return
    for line in env.read_text(encoding="utf-8").splitlines():
        key, sep, value = line.partition("=")
        if sep and not key.strip().startswith("#"):
            os.environ.setdefault(key.strip(), value.strip().strip("'\""))


load_env()


def toc_field(name):
    toc = (ROOT / f"{ADDON}.toc").read_text(encoding="utf-8")
    match = re.search(rf"^## {re.escape(name)}:\s*(\S+)", toc, re.M)
    return match and match.group(1)


def toc_field_line(name):
    """A TOC field's whole value (titles have spaces); colour codes stripped."""
    toc = (ROOT / f"{ADDON}.toc").read_text(encoding="utf-8")
    match = re.search(rf"^## {re.escape(name)}:\s*(.+?)\s*$", toc, re.M)
    return match and re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", match.group(1))


def version():
    return toc_field("Version")


def notes(ver=None):
    """The CHANGELOG section of a version, without its title."""
    ver = ver or version()
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    match = re.search(rf"^## {re.escape(ver)}(?=\s|$).*?$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        sys.exit(f"CHANGELOG.md has no '## {ver}' section")
    return match.group(1).strip() + "\n"


def release_type(ver):
    if "alpha" in ver:
        return "alpha"
    if "beta" in ver or "-" in ver:
        return "beta"
    return "release"


def request(url, token, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers={"X-Api-Token": token, **(headers or {})})
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8") or "null")
    except urllib.error.HTTPError as error:
        sys.exit(f"{url}: HTTP {error.code} {error.read().decode('utf-8', 'replace')}")


def find_game_version(versions, wanted):
    found = [v for v in versions if v.get("name") == wanted]
    if not found:
        close = sorted({v.get("name") for v in versions if str(v.get("name", "")).startswith(wanted.split(".")[0] + ".")})
        sys.exit(f"No CurseForge game version named {wanted}. Close ones: {', '.join(close[-20:])}\n"
                 "Set the CF_GAME_VERSION (or CF_GAME_VERSION_ID) repository variable.")
    if len(found) > 1:
        print("Several game versions named", wanted, [(v["id"], v.get("gameVersionTypeID")) for v in found])
    return found[-1]["id"]


def game_version_ids(token):
    if os.environ.get("CF_GAME_VERSION_ID"):
        return [int(v) for v in os.environ["CF_GAME_VERSION_ID"].split(",") if v.strip()]
    wanted = [v.strip() for v in (os.environ.get("CF_GAME_VERSION") or "1.60.1").split(",") if v.strip()]
    versions = request(f"{API}/game/versions", token)
    return [find_game_version(versions, name) for name in wanted]


def curseforge():
    token = os.environ.get("CF_API_KEY")
    if not token:
        sys.exit("CF_API_KEY is not set (GitHub: Settings > Secrets and variables > Actions)")
    project = toc_field("X-Curse-Project-ID")
    if not project:
        sys.exit("The TOC has no '## X-Curse-Project-ID'")
    ver = version()
    zip_path = ROOT / "dist" / f"{ADDON}-{ver}.zip"
    if not zip_path.is_file():
        sys.exit(f"{zip_path} is missing: run tools/package.py first")

    metadata = {
        "changelog": notes(ver),
        "changelogType": "markdown",
        "displayName": f"{TITLE or toc_field_line('Title') or ADDON} {ver}",
        "releaseType": release_type(ver),
        "gameVersions": game_version_ids(token),
    }
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".encode(),
        json.dumps(metadata).encode("utf-8"),
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{zip_path.name}\"\r\n"
        "Content-Type: application/zip\r\n\r\n".encode(),
        zip_path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    result = request(f"{API}/projects/{project}/upload-file", token, body,
                     {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    print(f"CurseForge: {zip_path.name} uploaded ({metadata['releaseType']}), file id {result and result.get('id')}")


def versions(filter_text=""):
    token = os.environ.get("CF_API_KEY") or sys.exit("CF_API_KEY is not set")
    types = {t["id"]: t["name"] for t in request(f"{API}/game/version-types", token)}
    for v in request(f"{API}/game/versions", token):
        line = f'{v["id"]:>6}  {v.get("name")}  ({types.get(v.get("gameVersionTypeID"), "?")})'
        if filter_text.lower() in line.lower():
            print(line)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "check":
        tag = sys.argv[2] if len(sys.argv) > 2 else ""
        if tag != f"v{version()}":
            sys.exit(f"The tag {tag} doesn't match the TOC's version {version()} (expected v{version()})")
        notes()
        print(f"Version {version()}: ok")
    elif command == "notes":
        sys.stdout.write(notes(sys.argv[2] if len(sys.argv) > 2 else None))
    elif command == "curseforge":
        curseforge()
    elif command == "title":
        print(TITLE or toc_field_line("Title") or ADDON)
    elif command == "versions":
        versions(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
