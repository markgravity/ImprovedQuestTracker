"""Build the release zip: dist/<Addon>-<version>.zip

<Addon> is the .toc file's name (override with ADDON=...). The zip holds a
single <Addon>/ folder with what the game loads: the TOC and the files it
lists, Bindings.xml, every texture under textures/ (.tga/.blp), and the
licence, README and CHANGELOG when present. Tools and design sources stay out.

Usage (from the addon's root, where the .toc is):
    python tools/package.py
    TEXTURE_PREFIX=ic_ python tools/package.py   # also check "ic_*" names used in the code exist
"""
import os
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = os.environ.get("ADDON") or next(ROOT.glob("*.toc")).stem
EXTRA = ["Bindings.xml", "LICENSE", "LICENSE.md", "README.md", "CHANGELOG.md"]
TEXTURE_PREFIX = os.environ.get("TEXTURE_PREFIX", "")


def main():
    toc = (ROOT / f"{ADDON}.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    listed = [line.strip().replace("\\", "/") for line in toc.splitlines()
              if line.strip() and not line.startswith("#")]

    extra = [f for f in EXTRA if (ROOT / f).is_file()]
    extra += sorted(p.name for p in ROOT.glob("LICENSE-*"))
    textures = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "textures").rglob("*")
                      if p.suffix.lower() in (".tga", ".blp"))
    files = [f"{ADDON}.toc"] + listed + extra + textures

    missing = [f for f in files if not (ROOT / f).is_file()]
    if missing:
        sys.exit("Missing files: " + ", ".join(missing))

    # Every texture the code names in full must be packaged
    if TEXTURE_PREFIX:
        code = "".join((ROOT / f).read_text(encoding="utf-8") for f in listed if f.endswith(".lua"))
        names = set(re.findall(rf'"({re.escape(TEXTURE_PREFIX)}[a-z0-9_]+)"', code))
        packaged = {Path(f).stem for f in textures}
        absent = sorted(n for n in names if n not in packaged and not n.endswith("_"))
        if absent:
            sys.exit("Textures used but not packaged: " + ", ".join(absent))

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    out = dist / f"{ADDON}-{version}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(ROOT / f, f"{ADDON}/{f}")
    size = out.stat().st_size / 1024
    print(f"{out.relative_to(ROOT)}: {len(files)} files, {size:.0f} KB")


if __name__ == "__main__":
    main()
