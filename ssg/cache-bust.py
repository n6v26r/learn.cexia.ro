#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import posixpath
import re
import shutil
from pathlib import Path

RAW = Path("zig-out/.zine-release-raw")
OUT = Path("zig-out/release")

ASSET_EXTS = {
    ".css",
    ".js",
    ".woff",
    ".woff2",
    ".ttf",
    ".otf",
    ".eot",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".svg",
    ".webp",
    ".avif",
    ".ico",
    ".json",
    ".webmanifest",
}
TEXT_EXTS = {".css", ".js", ".svg", ".html", ".json", ".xml", ".txt", ".webmanifest"}
PATH_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./")
CODE_RE = re.compile(r"(<code\b[\s\S]*?</code>)", re.IGNORECASE)


def is_asset(rel: str) -> bool:
    if rel == "vercel.json":
        return False
    if rel == "robots.txt" or rel == "sitemap.xml" or rel == "favicon.ico":
        return False
    if rel == ".well-known" or rel.startswith(".well-known/"):
        return False
    suffix = Path(rel).suffix.lower()
    return suffix in ASSET_EXTS and suffix not in {".html", ".xml"}


def hashed_name(rel: str) -> str:
    file = RAW / rel
    digest = hashlib.md5(file.read_bytes()).hexdigest()
    base = posixpath.basename(rel)
    stem, ext = posixpath.splitext(base)
    name = f"{stem}_{digest}{ext}"
    parent = posixpath.dirname(rel)
    return f"{parent}/{name}" if parent else name


def web_rel(current: str, target: str) -> str:
    current_dir = posixpath.dirname(current)
    if not current_dir:
        return target
    return posixpath.relpath(target, current_dir)


def is_edge(text: str, start: int, length: int) -> bool:
    before = start == 0 or text[start - 1] not in PATH_CHARS
    end = start + length
    after = end >= len(text) or text[end] not in PATH_CHARS
    return before and after


def is_root_edge(text: str, start: int, length: int) -> bool:
    end = start + length
    if end < len(text) and text[end] in PATH_CHARS:
        return False
    if start == 0 or text[start - 1] not in PATH_CHARS:
        return True

    scheme = text.rfind("://", 0, start)
    if scheme < 0:
        return False
    host_start = scheme + len("://")
    return "/" not in text[host_start:start]


def replace_token(text: str, needle: str, repl: str, root: bool = False) -> str:
    out: list[str] = []
    pos = 0
    while True:
        start = text.find(needle, pos)
        if start < 0:
            out.append(text[pos:])
            return "".join(out)
        edge = is_root_edge(text, start, len(needle)) if root else is_edge(text, start, len(needle))
        if edge:
            out.append(text[pos:start])
            out.append(repl)
            pos = start + len(needle)
        else:
            out.append(text[pos : start + 1])
            pos = start + 1


def rewrite_chunk(text: str, current: str, assets: dict[str, str]) -> str:
    for src, dst in assets.items():
        text = replace_token(text, f"/{src}", f"/{dst}", root=True)

        rel_src = web_rel(current, src)
        rel_dst = web_rel(current, dst)
        text = replace_token(text, src, rel_dst)
        if rel_src != src:
            text = replace_token(text, rel_src, rel_dst)
    return text


def rewrite_text(text: str, current: str, assets: dict[str, str]) -> str:
    if not current.endswith(".html"):
        return rewrite_chunk(text, current, assets)

    parts = CODE_RE.split(text)
    for i in range(0, len(parts), 2):
        parts[i] = rewrite_chunk(parts[i], current, assets)
    return "".join(parts)


def main() -> int:
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)

    files = sorted(file.relative_to(RAW).as_posix() for file in RAW.rglob("*") if file.is_file())
    assets = {rel: hashed_name(rel) for rel in files if is_asset(rel)}

    for rel in files:
        dst_rel = assets.get(rel, rel)
        src = RAW / rel
        dst = OUT / dst_rel
        dst.parent.mkdir(parents=True, exist_ok=True)

        if src.suffix.lower() in TEXT_EXTS:
            text = src.read_text(encoding="utf-8")
            dst.write_text(rewrite_text(text, dst_rel, assets), encoding="utf-8")
        else:
            shutil.copy2(src, dst)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
