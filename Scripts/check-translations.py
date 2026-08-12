#!/usr/bin/env python3
"""Findet Anzeigetexte im Quelltext, die in keiner Übersetzung auftauchen.

Deutsch ist die Entwicklungssprache und der Schlüssel ist der deutsche Text
selbst — eine fehlende Übersetzung fällt also auf korrektes Deutsch zurück und
bricht nichts. Trotzdem soll sichtbar sein, was noch fehlt.

    ./Scripts/check-translations.py            # meldet Lücken in en.lproj
    ./Scripts/check-translations.py --list     # gibt alle gefundenen Schlüssel aus

Bewusst nicht gemeldet werden Bezeichner und Beispiele: SF-Symbol-Namen,
Formatnamen wie "camelCase", Platzhalter wie "sk-…". Sie stehen in SKIP.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STR = r'"((?:[^"\\]|\\.)*)"'

# Aufrufstellen, an denen ein Literal Anzeigetext ist.
PATTERNS = [
    rf"\blocalized\(\s*{STR}",
    rf"\bText\(\s*{STR}\s*\)",
    rf"\.help\(\s*{STR}\s*\)",
    rf"\.anvilHelp\(\s*{STR}\s*\)",
    rf"\bToggle\(\s*{STR}\s*,",
    rf"\bButton\(\s*{STR}\s*\)",
    rf"\bTextField\(\s*{STR}\s*,",
    rf"\bSecureField\(\s*{STR}\s*,",
    rf"\bLabel\(\s*{STR}\s*,",
    rf"\bSection\(\s*{STR}\s*\)",
    # Der Titel eines Menüs in der Menüleiste ist Anzeigetext wie jeder andere.
    rf"\bCommandMenu\(\s*{STR}\s*\)",
    rf"\.confirmationDialog\(\s*{STR}",
    rf"\bAnvilButton\(\s*\n?\s*{STR}",
    rf"\bStatusPill\(\s*\n?\s*{STR}",
    rf"\bProgressStrip\(\s*\n?\s*{STR}",
    rf"\bCopyButton\(\s*{STR}\s*,",
    rf"\bAnvilPane\(\s*\n?\s*{STR}",
    rf"\bAnvilSection\(\s*\n?\s*{STR}",
    rf"\bInspectorSection\(\s*\n?\s*{STR}",
    rf"\bOptionRow\(\s*\n?\s*{STR}",
    rf"\bSettingsPage\(\s*\n?\s*{STR}",
    rf"\bSettingsGroup\(\s*\n?\s*{STR}",
    rf"\bSettingsRow\(\s*\n?\s*{STR}",
    rf"\bSettingsWideRow\(\s*\n?\s*{STR}",
    rf"\btitle:\s*{STR}",
    rf"\bsubtitle:\s*{STR}",
    rf"\bmessage:\s*{STR}",
    rf"\bfootnote:\s*{STR}",
    rf"\bhelp:\s*{STR}",
    rf"\blabel:\s*{STR}",
    rf"\bplaceholder:\s*{STR}",
    rf"\bactionTitle:\s*{STR}",
    rf"\bdescription:\s*{STR}",
    rf"\binputPlaceholder:\s*{STR}",
    rf"\bdefaultValue:\s*{STR}",
    # Enum-artige Rückgaben: case .recording: "Ich höre zu"
    rf"^\s*case \.\w+: {STR}$",
    # Rückgaben aus berechneten LocalizedStringKey-Eigenschaften
    rf"^\s*return {STR}$",
]

# Interpolationen, die eine Zahl einsetzen — Foundation erzeugt dafür %lld.
#
# Ohne Compiler lässt sich der Typ nicht ausrechnen, also wird er am Namen
# erkannt. Die Liste ist gepflegt und nicht geraten: Steht ein neuer Name für
# eine Zahl nicht drin, erwartet dieses Skript „%@", während die App zur
# Laufzeit „%lld" nachschlägt — und der Text bliebe still unübersetzt. Genau
# deshalb gehört jeder neue Zähler hier hinein.
INTEGER_EXPRESSION = re.compile(
    r"[Cc]ount\b|statusCode|Int\(|\bindex\b|\+ 1\b|\.line\b|\.level\b"
    r"|\bdays\b|\bfailures\b|\bshare\b|\bdistinct\b|\bempty\b"
    r"|\.ahead\b|\.behind\b"
)

# Was absichtlich unübersetzt bleibt.
SKIP = {
    "Anvil",
    "Apple Intelligence (on-device)",
    "Base64", "Hex", "IBAN", "JSON", "JWT", "SQL", "URL", "UUID", "PostgreSQL",
    "Markdown", "CSV", "TSV", "HTML", "UTC", "ISO 8601", "YAML", "TOML", "PDF",
    "MD5", "SHA-1", "SHA-256", "SHA-512",
    # Bildformate heißen in jeder Sprache gleich.
    "PNG", "JPEG", "HEIC", "TIFF",
    "camelCase", "PascalCase", "snake_case", "kebab-case", "CONSTANT_CASE",
    "ICU (Swift/NSRegularExpression)", "Swift DocC (///)",
    "A → Z", "Z → A", "Slug", "Speech Studio",
    "Apple Foundation Models",
    "Claude Code", "Codex", "Gemini CLI",   # Produktnamen
    "-p",                                    # Beispielargument
    "\\t",                                   # das Trennzeichen selbst
    # SQL- und JSON-Syntax. Steht im Quelltext hinter einem `return` und sieht
    # damit aus wie Anzeigetext — ist aber Format und wird nie übersetzt.
    "INSERT INTO %@ (%@) VALUES (%@);",
    "    %@: %@",
    "@@ -%@ +%@ @@%@",                       # der Abschnittskopf eines Diffs
    "%@- [%@](#%@)",                         # eine Zeile im Inhaltsverzeichnis
    "%@@%@.example",                         # eine erfundene Adresse
}
SKIP_PATTERNS = [
    re.compile(r"^[a-z0-9.]+$"),          # SF-Symbol-Namen
    re.compile(r"^Privacy_"),             # Kennungen von Systemeinstellungs-Seiten
    re.compile(r"^https?://"),            # Beispiel-URLs
    re.compile(r"…$"),                    # Platzhalter wie "sk-…", "git diff …"
    # Ein Schlüssel, der *nur* aus Platzhaltern besteht. Ein Text, der bloß mit
    # einem Platzhalter anfängt, ist dagegen Anzeigetext wie jeder andere —
    # „%lld von %lld ließen sich nicht holen." gehört übersetzt.
    re.compile(r"^(?:%(?:@|lld)\s*)+$"),
    re.compile(r"^\{"),                   # JSON-Beispiele
    re.compile(r"^\d"),                   # Zahlenbeispiele
    re.compile(r"^z\. B\."),
]


def to_key(text: str) -> str:
    """Macht aus einem Swift-Literal den Schlüssel, den Foundation nachschlägt."""
    def replace(match: re.Match) -> str:
        expression = match.group(1)
        # Ein Index innerhalb eines Subscripts liefert einen Teilstring, keine
        # Zahl — "\(text[index..<next])" ist also %@, nicht %lld.
        if "[" in expression:
            return "%@"
        return "%lld" if INTEGER_EXPRESSION.search(expression) else "%@"

    return re.sub(r"\\\(([^()]*(?:\([^()]*\)[^()]*)*)\)", replace, text)


def collect_keys() -> dict[str, set[str]]:
    keys: dict[str, set[str]] = {}
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        text = path.read_text()
        for pattern in PATTERNS:
            for match in re.finditer(pattern, text, re.M):
                literal = match.group(1)
                key = to_key(literal)
                # Geprüft wird der fertige Schlüssel, nicht das Literal davor:
                # In „\(Int(progress * 100)) %" stecken Buchstaben, im
                # Schlüssel „%lld %" keine mehr — und was aus Platzhaltern und
                # Zeichen besteht, ist Format und kein Anzeigetext.
                #
                # Die Platzhalter selbst müssen dafür weg: In „%lld" und „\n"
                # stecken Buchstaben, die niemand liest.
                naked = re.sub(r"%(?:@|lld)|\\.", "", key)
                if len(literal) < 2 or not re.search(r"[A-Za-zÄÖÜäöü]", naked):
                    continue
                keys.setdefault(key, set()).add(path.name)
    return keys


def is_skipped(key: str) -> bool:
    return key in SKIP or any(pattern.search(key) for pattern in SKIP_PATTERNS)


def translated_keys(language: str) -> set[str]:
    path = ROOT / "Resources" / f"{language}.lproj" / "Localizable.strings"
    if not path.exists():
        return set()
    return set(re.findall(r'^"((?:[^"\\]|\\.)*)" = ', path.read_text(), re.M))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="alle Schlüssel ausgeben")
    parser.add_argument("--language", default="en")
    arguments = parser.parse_args()

    keys = collect_keys()
    if arguments.list:
        for key in sorted(keys):
            print(key)
        return 0

    have = translated_keys(arguments.language)
    missing = sorted(k for k in keys if k not in have and not is_skipped(k))

    print(f"{len(keys)} Anzeigetexte gefunden, {len(have)} übersetzt ({arguments.language}).")
    if not missing:
        print("Keine Lücken.")
        return 0

    print(f"\n{len(missing)} ohne Übersetzung:")
    for key in missing:
        print(f"  {key}\n      {', '.join(sorted(keys[key]))}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
