<div align="center">

# Anvil

**Eine native macOS-Werkzeugsammlung für den Alltag und fürs Entwickeln —
mit KI auf dem Gerät statt in der Cloud.**

[![Build](https://github.com/Kiritosky/Anvil/actions/workflows/build.yml/badge.svg)](https://github.com/Kiritosky/Anvil/actions/workflows/build.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Top-Sprache](https://img.shields.io/github/languages/top/Kiritosky/Anvil?color=F05138)](https://github.com/Kiritosky/Anvil/search?l=swift)
[![Codegröße](https://img.shields.io/github/languages/code-size/Kiritosky/Anvil)](https://github.com/Kiritosky/Anvil)
[![Letzter Commit](https://img.shields.io/github/last-commit/Kiritosky/Anvil)](https://github.com/Kiritosky/Anvil/commits)
[![Sterne](https://img.shields.io/github/stars/Kiritosky/Anvil?style=flat&logo=github)](https://github.com/Kiritosky/Anvil/stargazers)
[![Lizenz](https://img.shields.io/github/license/Kiritosky/Anvil?color=blue)](LICENSE)

**82 Werkzeuge** · **on-device** · **ohne Netz nutzbar** · Deutsch & Englisch

[Werkzeuge](docs/TOOLS.md) · [Aufbau](docs/ARCHITECTURE.md) ·
[Neues Werkzeug](docs/ADDING_A_TOOL.md) · [Mitmachen](CONTRIBUTING.md)

In English: **[README.en.md](README.en.md)**

</div>

---

Anvil ist ein Fenster mit einer Seitenleiste voller Werkzeuge: diktieren,
Text umformen, Bilder umwandeln, Repositories durchsehen, Archive öffnen,
Codezeilen zählen. Alles, was ohne Sprachmodell auskommt, rechnet
deterministisch und ohne Netzverbindung. Was ein Modell braucht, nimmt
standardmäßig das lokale von **Apple Intelligence**.

> Partner-App zu Nook.

## Warum

- **Sprache zuerst.** Diktieren, live transkribieren, und danach per Modell
  Füllwörter, Versprecher und Zeichensetzung aufräumen — geglättet oder
  umgeschrieben zu Prosa, Stichpunkten, Commit-Message oder Zusammenfassung.
- **Von überall.** Ein globales Kürzel (⌥⌘D) blendet eine kleine Bubble über
  jeder App ein. Sprechen, Kürzel noch einmal — der Text landet im Feld, in
  dem der Cursor steht. Das Hauptfenster bleibt zu.
- **On-Device zuerst.** Externe Anbieter sind möglich, nie Voraussetzung. Wer
  Claude Code, Codex oder die Gemini CLI installiert hat, nutzt sie ohne
  API-Schlüssel über die vorhandene Anmeldung.
- **Massenaktionen überall.** Dreißig Bilder, hundert Dateien, alle
  Repositories auf einmal — kein Werkzeug hört bei einem Element auf.
- **Nichts Vertrauliches auf der Platte.** Werkzeuge merken sich die letzte
  Eingabe — außer sie sieht nach einem Schlüssel aus, und außer bei JWT,
  Prüfsummen, Base64 und Hex. Ergebnisse werden nie gespeichert.
- **GitHub mit einem Klick.** Anmeldung über GitHubs Device Flow, Token im
  Schlüsselbund, gefragt wird nur nach `repo`.
- **Erweiterbar.** Ein Werkzeug ist eine Registrierung, kein Sonderfall. Reine
  Prompt-Werkzeuge kommen als JSON-Datei dazu, ohne Neukompilieren.

## Werkzeuge

| Bereich | Anzahl | Beispiele |
| --- | ---: | --- |
| Coding | 41 | Repositories, Patch, Netzrechner, JSON zu Typen, Codezeilen, Commit-Message, Pull-Request-Beschreibung, Code-Review, Umbauen, Portieren |
| Alltag | 27 | Bildschirmfoto, Text aus Bild, PDF, QR-Code, Dubletten, Speicherplatz, Archive, Übersetzen, Antwort entwerfen, Protokoll |
| Text & Daten | 10 | Markdown, Textvergleich, Lesbarkeit, Slug, Korrekturlesen, Einfach erklären, Tabelle bauen |
| Sprache & Audio | 2 | Speech Studio, Diktat-Vokabular |
| System & Eigene | 2 | Tool-Store, Eigenes Werkzeug |

Fünfundzwanzig davon fragen ein Sprachmodell — die übrigen 57 rechnen selbst.

Die vollständige Liste steht in **[docs/TOOLS.md](docs/TOOLS.md)** — erzeugt
aus dem Quelltext, nicht von Hand gepflegt.

## Installieren

Eine fertige App gibt es noch nicht zum Herunterladen; bis zum ersten Release
baut man sie selbst — drei Zeilen, siehe unten.

Voraussetzung ist **macOS 26** oder neuer: Apple Foundation Models und
`SpeechAnalyzer` gibt es darunter nicht.

## Selbst bauen

```sh
git clone https://github.com/Kiritosky/Anvil.git && cd Anvil
./Scripts/run.sh                  # bauen und starten
```

Weitere Wege:

```sh
./Scripts/build-app.sh release    # Release-Bundle nach .build/release/Anvil.app
swift test                        # Unit-Tests
./Scripts/check-translations.py   # fehlende Übersetzungen
./Scripts/tool-list.py            # docs/TOOLS.md neu schreiben
```

Mit eigenem Zertifikat signieren:

```sh
./Scripts/build-app.sh release --sign "Developer ID Application: …"
```

Die App läuft **ohne App Sandbox** — Werkzeuge greifen frei aufs Dateisystem,
auf Git-Repositories und auf lokale Prozesse zu. Ein Weg in den Mac App Store
ist nicht vorgesehen.

## Aufbau

| Target | Zweck |
| --- | --- |
| `AnvilKit` | Tool-Modell, Registry, Kontext, Storage, Utilities |
| `AnvilUI` | Design-Tokens, Layouts, Komponentenbibliothek |
| `AnvilAI` | Sprachmodelle: Foundation Models, externe Anbieter, CLI-Agenten |
| `AnvilSpeech` | Aufnahme und Transkription über `SpeechAnalyzer` |
| `AnvilToolbox` | Die Werkzeuge und die generischen Werkzeug-Engines |
| `AnvilApp` | App-Shell: Seitenleiste, Command-Palette, Einstellungen, Menüleiste |

Abhängigkeiten zeigen ausschließlich nach unten — warum, steht in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Dokumentation

| Datei | Inhalt |
| --- | --- |
| [docs/TOOLS.md](docs/TOOLS.md) | Alle Werkzeuge, aus dem Quelltext erzeugt |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Die sechs Targets und was in welches gehört |
| [docs/ADDING_A_TOOL.md](docs/ADDING_A_TOOL.md) | Vier Wege zu einem neuen Werkzeug, vom billigsten an |
| [docs/LOCALIZATION.md](docs/LOCALIZATION.md) | Wie Texte übersetzbar bleiben |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Regeln, Tests, Commits |
| [CLAUDE.md](CLAUDE.md) | Projektregeln, an die sich auch Werkzeuge halten |

## Sprachen

Deutsch und Englisch. Der deutsche Quelltext ist zugleich der
Übersetzungsschlüssel; eine weitere Sprache ist ein zusätzlicher
`.lproj`-Ordner — siehe [docs/LOCALIZATION.md](docs/LOCALIZATION.md).

## Fenster

Ein Hauptfenster mit Seitenleiste — und jedes Werkzeug zusätzlich in einem
eigenen Fenster (⇧⌘N oder Rechtsklick in der Seitenleiste). Dasselbe Werkzeug
darf mehrfach offen sein, jedes mit eigenem Zustand und eigener Größe.

## Status

Version 1.0, in aktiver Entwicklung. Der Aufbau ging von unten nach oben:
erst Kern und Design-System, dann Dienste, dann Werkzeuge.

## Lizenz

[GNU GPL v3](LICENSE).
