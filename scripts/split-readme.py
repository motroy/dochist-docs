#!/usr/bin/env python3
"""Split README.md into mdBook chapters (one per top-level `## ` section)
and generate src/SUMMARY.md, so the sidebar reflects the README's real
structure instead of a single flat page."""

import re
from pathlib import Path

README = Path("README.md")
SRC = Path("src")

HEADING_RE = re.compile(r"^## (.+)$")


def slugify(text: str) -> str:
    text = re.sub(r"[`*_]", "", text)
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def main() -> None:
    lines = README.read_text().splitlines(keepends=True)

    sections = []
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line.rstrip("\n"))
        if m:
            sections.append((m.group(1).strip(), i))

    SRC.mkdir(exist_ok=True)

    intro_end = sections[0][1] if sections else len(lines)
    (SRC / "README.md").write_text("".join(lines[:intro_end]))

    summary = ["# Summary\n", "\n", "[Introduction](README.md)\n", "\n"]

    used_slugs = set()
    for idx, (title, start) in enumerate(sections):
        end = sections[idx + 1][1] if idx + 1 < len(sections) else len(lines)
        body = "".join(lines[start:end])

        slug = slugify(title) or f"section-{idx}"
        if slug in used_slugs:
            slug = f"{slug}-{idx}"
        used_slugs.add(slug)

        filename = f"{slug}.md"
        (SRC / filename).write_text(body)
        summary.append(f"- [{title}]({filename})\n")

    (SRC / "SUMMARY.md").write_text("".join(summary))


if __name__ == "__main__":
    main()
