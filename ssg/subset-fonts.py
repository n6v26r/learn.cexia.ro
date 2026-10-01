#!/usr/bin/env python3
from __future__ import annotations

import html
import os
import re
import string
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path("zig-out/.zine-release-raw")

FONT_EXTS = {".otf", ".ttf", ".woff", ".woff2"}
TEXT_EXTS = {".css", ".html", ".js", ".json", ".txt", ".webmanifest", ".xml"}
ENTITY_RE = re.compile(r"&(#(?:x[0-9a-fA-F]+|\d+)|[A-Za-z][A-Za-z0-9]+);")
STANDARD_CHARS = string.ascii_letters + string.digits + string.punctuation


def add_text(points: set[int], text: str) -> None:
    for ch in text:
        cp = ord(ch)
        if cp >= 0x20 and not 0xD800 <= cp <= 0xDFFF:
            points.add(cp)

    for match in ENTITY_RE.finditer(text):
        for ch in html.unescape(match.group(0)):
            cp = ord(ch)
            if cp >= 0x20 and not 0xD800 <= cp <= 0xDFFF:
                points.add(cp)


def scan_chars(root: Path) -> set[int]:
    points = {ord(ch) for ch in STANDARD_CHARS}

    for file in root.rglob("*"):
        if file.is_file() and file.suffix.lower() in TEXT_EXTS:
            add_text(points, file.read_text(encoding="utf-8", errors="ignore"))

    return points


def unicode_ranges(points: set[int]) -> str:
    ranges: list[str] = []
    start = prev = None

    for cp in sorted(points):
        if start is None:
            start = prev = cp
        elif cp == prev + 1:
            prev = cp
        else:
            ranges.append(fmt_range(start, prev))
            start = prev = cp

    if start is not None:
        ranges.append(fmt_range(start, prev))

    return ",".join(ranges)


def fmt_range(start: int, end: int) -> str:
    if start == end:
        return f"{start:04X}"
    return f"{start:04X}-{end:04X}"


def subset_font(font: Path, tmp_dir: Path, unicodes: Path) -> None:
    tmp_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(dir=tmp_dir, suffix=font.suffix, delete=False) as file:
        tmp = Path(file.name)

    cmd = [
        sys.executable,
        "-m",
        "fontTools.subset",
        str(font),
        f"--output-file={tmp}",
        f"--unicodes-file={unicodes}",
        "--layout-features=*",
        "--ignore-missing-unicodes",
        "--no-hinting",
    ]
    suffix = font.suffix.lower()
    if suffix == ".woff":
        cmd.append("--flavor=woff")
    elif suffix == ".woff2":
        cmd.append("--flavor=woff2")

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)

    if font.read_bytes() == tmp.read_bytes():
        tmp.unlink()
    else:
        os.replace(tmp, font)


def main() -> int:
    fonts = [file for file in ROOT.rglob("*") if file.is_file() and file.suffix.lower() in FONT_EXTS]
    if not fonts:
        return 0

    tmp_dir = Path("zig-out/.font-subset-cache")
    points = scan_chars(ROOT)

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as file:
        file.write(unicode_ranges(points))
        unicodes = Path(file.name)

    try:
        for font in fonts:
            subset_font(font, tmp_dir, unicodes)
    finally:
        unicodes.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
