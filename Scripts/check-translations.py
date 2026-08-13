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
# Dasselbe ohne Gruppe — für den Zweig eines `?:`, der nur davorstehen muss.
STR_ANY = r'"(?:[^"\\]|\\.)*"'

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
    # Ein Literal am Zeilenende hinter einem Doppelpunkt: der Zweig eines
    # mehrzeiligen `?:` und alles, was als Argument so umbrochen wurde.
    rf":\s*{STR}$",
    # Beide Zweige eines einzeiligen `?:`. Ohne die beiden Regeln blieb
    # `.anvilHelp(x ? "Hineingehen" : "Im Finder zeigen")` unbemerkt: Es steht
    # kein Aufrufname davor und kein Zeilenende dahinter.
    rf"\?\s*{STR}\s*:",
    rf"\?\s*{STR_ANY}\s*:\s*{STR}",
    # Ein Literal allein auf einer Zeile: so stehen Anzeigetexte in Listen
    # und Tupeln da, wo kein Aufrufname davorsteht.
    rf"^\s*{STR},?$",
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
    r"|\.ahead\b|\.behind\b|\.changed[A-Z]\w*|\bwritten\b"
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
    # Steht in einer Anweisung an das Sprachmodell, nicht auf dem Bildschirm.
    "Aufgabe: %@",
    # Ein Befehl fürs Terminal. Übersetzt wäre er keiner mehr.
    "cd %@ && git branch -d %@",
    "swift, md, json",                       # Dateiendungen als Beispiel
    "RGB", "HSL", "CSS", "SwiftUI",          # Format- und Rahmenwerknamen
    "code-%lld",                             # ein Dateiname, kein Anzeigetext
    "user.%@",                               # eine Werkzeugkennung
    "rm %@",                                 # ein Befehl fürs Terminal
    "AXSearchField",                         # Kennung aus den Bedienungshilfen
    # Ein Fehler für Entwickler, kein Anzeigetext: Er steht in einem
    # `fatalError` und wird nie jemandem gezeigt, der die App nur benutzt.
    "ToolContext is missing a service of type %@. ",
    "static let %@ = %@",                    # Swift-Quelltext, keine Anzeige
    # Ein Beispiel aus einer Stilvorlage: Namen und Schreibweisen, keine Sprache.
    "--marke: #3A7BD5;\\nHintergrund #FFFFFF\\nrgb(58, 123, 213)",
    # SF-Symbol-Namen ohne Punkt. Sie sehen aus wie Wörter und sind Bezeichner;
    # übersetzt zeichnete das Symbol nichts mehr.
    "archivebox", "aspectratio", "asterisk", "book", "calendar", "camera",
    "checklist", "checkmark",
    "circle", "clock", "cloud", "command", "curlybraces", "cylinder",
    "doc", "envelope", "equal", "eraser", "externaldrive", "eye", "folder",
    "gearshape", "globe", "highlighter", "hourglass", "house", "keyboard",
    "laptopcomputer", "link", "macwindow", "magnifyingglass", "mic", "network",
    "number", "oval", "paintpalette", "pencil", "photo", "plusminus", "qrcode",
    "rectangle", "repeat", "ruler", "shippingbox", "sparkle", "sparkles",
    "speedometer",
    "pin", "star", "tablecells", "terminal", "trash", "tray", "waveform",
    # Datei- und Produktnamen heißen in jeder Sprache gleich.
    "heic", "jpg", "pdf", "png", "tiff", "txt", "zip", "swift", "git",
    "claude", "codex", "gemini",
    "esc",                                   # die Taste heißt überall so
    "ul", "ol", "true", "false", " checked", # HTML und JSON in Beispielen
    # Namen, die ein Werkzeug erzeugt: Kennungen, Dateinamen, CSS-Variablen.
    # Übersetzt wären es andere Namen — und damit andere Dinge.
    "wahl", "werkzeug", "farbe%@", "farbe-%@",
}
SKIP_PATTERNS = [
    # SF-Symbol-Namen. Mit Punkt, sonst wäre die Regel zu weit: „heute" und
    # „leer" sind ebenfalls klein geschrieben und ohne Punkt — und beides ist
    # Anzeigetext, der übersetzt gehört.
    re.compile(r"^[a-z0-9]+(\.[a-z0-9]+)+$"),
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
    re.compile(r"^x-apple\."),            # Adressen der Systemeinstellungen
    re.compile(r"^F\d+$"),                # Funktionstasten
    re.compile(r"^IPv[46]$"),             # Protokollnamen
    re.compile(r"^(?:rgb|hsl)a?\("),      # Farbsyntax
    re.compile(r"^\s*class="),            # HTML-Bruchstücke
    re.compile(r"[⇧⌘⌥⌃⇪]"),               # Tastenkombinationen
    re.compile(r"^/|^%@/"),               # Pfade und Suchorte
    re.compile(r"^[A-Za-z]+/[A-Za-z_+-]+$"),  # Zeitzonen wie Europe/Berlin
    re.compile(r"^<"),                    # HTML-Bausteine
    re.compile(r"^%\("),                  # Formate für `git for-each-ref`
    re.compile(r"^(?:NS)?Color\("),       # Quelltext, den ein Werkzeug ausgibt
]


def placeholder(expression: str) -> str:
    """Was Foundation für eine Interpolation einsetzt."""
    # Ein Index innerhalb eines Subscripts liefert einen Teilstring, keine
    # Zahl — "\(text[index..<next])" ist also %@, nicht %lld.
    if "[" in expression:
        return "%@"
    return "%lld" if INTEGER_EXPRESSION.search(expression) else "%@"


def to_key(text: str) -> str:
    """Macht aus einem Swift-Literal den Schlüssel, den Foundation nachschlägt.

    Die Klammern werden gezählt statt mit einem Ausdruck gesucht: Ein regulärer
    Ausdruck kann beliebig tiefe Verschachtelung nicht, und genau die kommt vor
    — `\\(Int((wert * 100).rounded()))`. Blieb so etwas stehen, verglich dieses
    Skript einen Schlüssel, den es zur Laufzeit nie gibt.
    """
    result: list[str] = []
    index = 0
    while index < len(text):
        if not text.startswith("\\(", index):
            result.append(text[index])
            index += 1
            continue

        depth = 0
        cursor = index + 1
        while cursor < len(text):
            if text[cursor] == "(":
                depth += 1
            elif text[cursor] == ")":
                depth -= 1
                if depth == 0:
                    break
            cursor += 1

        # Eine Klammer, die nie zugeht, gibt es in gültigem Swift nicht — dann
        # ist es keine Interpolation.
        if cursor >= len(text):
            result.append(text[index])
            index += 1
            continue

        result.append(placeholder(text[index + 2:cursor]))
        index = cursor + 1
    return "".join(result)


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
