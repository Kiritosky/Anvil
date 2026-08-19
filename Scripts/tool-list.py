#!/usr/bin/env python3
"""Schreibt docs/TOOLS.md aus dem Quelltext.

Die Liste von Hand zu pflegen heißt, dass sie beim übernächsten Werkzeug
falsch ist. Hier kommt sie aus derselben Stelle wie die App selbst.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

AREAS = [
    ("speech", "Sprache & Audio"),
    ("coding", "Coding"),
    ("text", "Text & Daten"),
    ("everyday", "Alltag"),
    ("custom", "Eigene Werkzeuge"),
    ("system", "System"),
]

FIELD = r'{0}:\s*"((?:[^"\\]|\\.)*)"'


def constants(sources):
    """`static let toolID: ToolIdentifier = "screen.shot"` — id: toolID meint das."""
    table = {}
    for text in sources:
        for match in re.finditer(
            r'let (\w+): ToolIdentifier = "([a-z][a-z0-9]*\.[a-z0-9]+)"', text
        ):
            table[match.group(1)] = match.group(2)
    return table


def tools():
    found = {}
    sources = [p.read_text() for p in sorted((ROOT / "Sources" / "AnvilToolbox").rglob("*.swift"))]
    named = constants(sources)

    for text in sources:
        for match in re.finditer(r'id:\s*"?([\w.]+)"?', text):
            identifier = named.get(match.group(1), match.group(1))
            if "." not in identifier or identifier.split(".")[0].isupper():
                continue
            if identifier == "user.example":
                continue
            window = text[match.end():match.end() + 500]
            title = re.search(FIELD.format("title"), window)
            subtitle = re.search(FIELD.format("subtitle"), window)
            category = re.search(r"category(?:ID)?:\s*(?:ToolCategory\.)?\.?(\w+)", window)
            if not title:
                continue
            found[identifier] = (
                title.group(1),
                subtitle.group(1) if subtitle else "",
                category.group(1) if category else "text",
            )
    return found


def main() -> int:
    found = tools()
    lines = [
        "# Werkzeuge",
        "",
        "Erzeugt aus dem Quelltext — `./Scripts/tool-list.py` schreibt diese Datei neu.",
        "",
        f"**{len(found)} Werkzeuge**, davon "
        f"{sum(1 for i in found if i.startswith('ai.'))} mit Sprachmodell.",
        "",
    ]

    for key, heading in AREAS:
        rows = sorted(
            (identifier, *values)
            for identifier, values in found.items()
            if values[2] == key
        )
        if not rows:
            continue
        lines += [f"## {heading}", "", "| Werkzeug | Was es tut | Kennung |", "| --- | --- | --- |"]
        lines += [f"| {title} | {subtitle} | `{identifier}` |" for identifier, title, subtitle, _ in rows]
        lines.append("")

    (ROOT / "docs" / "TOOLS.md").write_text("\n".join(lines))
    print(f"docs/TOOLS.md: {len(found)} Werkzeuge")
    return 0


if __name__ == "__main__":
    sys.exit(main())
