# Anvil

[![Build](https://github.com/kiritosky/nooktools/actions/workflows/build.yml/badge.svg)](https://github.com/kiritosky/nooktools/actions/workflows/build.yml)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](https://swift.org)
[![GPL v3](https://img.shields.io/badge/Lizenz-GPL--3.0-blue)](LICENSE)

Eine native macOS-Werkzeugsammlung für den Alltag und fürs Entwickeln — mit
KI-Funktionen auf Basis der **Apple Foundation Models** (on-device) und
optionalen externen Anbietern.

> Partner-App zu Nook. Das Repository heißt weiterhin `nooktools`, das Produkt
> heißt **Anvil**.

## Idee

Ein Fenster, viele Werkzeuge, eine gemeinsame Basis:

- **Sprache zuerst.** Diktieren, live transkribieren, und anschließend per
  Sprachmodell Füllwörter, Versprecher, Grammatik und Zeichensetzung aufräumen
  — verbatim geglättet oder umgeschrieben zu sauberer Prosa, Bullet-Points,
  Commit-Message oder Zusammenfassung.
- **Von überall.** Ein globales Tastenkürzel (voreingestellt ⌥⌘D) blendet eine
  kleine Bubble über jeder App ein. Sprechen, Kürzel noch einmal drücken — der
  aufgeräumte Text landet im Textfeld, in dem der Cursor steht, sonst in der
  Zwischenablage. Das Hauptfenster bleibt zu.
- **Tastenkürzel, die dir gehören.** Jede Aktion — Diktat, Ausschnitt,
  Vollbild, Fenster, Text vom Bildschirm — hat ein Kürzel, das sich ändern,
  abschalten und zwischen „nur in Anvil“ und „überall“ umstellen lässt.
  Kollisionen werden erkannt, statt still zu gewinnen.
- **Eigene Wörter.** Eine persönliche Wortliste wird im Diktat deterministisch
  durchgesetzt — Produktnamen, Kollegen, Code-Bezeichner stehen richtig da,
  bevor das Modell den Text überhaupt sieht.
- **On-Device zuerst.** Standardweg ist das lokale Apple-Intelligence-Modell.
  Externe Anbieter sind möglich, aber nie Voraussetzung — und wer Claude Code,
  Codex oder die Gemini CLI installiert hat, nutzt sie ohne API-Schlüssel über
  die vorhandene Anmeldung. Auch Texterkennung aus Bildern läuft lokal über
  Vision.
- **Erweiterbar von Anfang an.** Tools sind Registrierungen, keine
  Sonderfälle. Reine Prompt-Tools kommen ohne Neukompilieren als JSON-Datei
  dazu, und im Tool-Store lässt sich jedes Tool ein- und ausschalten.

## Was drin ist

| Bereich | Werkzeuge |
| --- | --- |
| Sprache & Audio | Speech Studio, Diktat-Vokabular |
| KI-Werkzeuge | 15 Prompt-Tools: Commit-Message, Code-Review, Tests, Regex, Shell, Übersetzen, E-Mail … |
| Text & Daten | JSON, Base64, URL, JWT, Prüfsummen, UUID, Zeitstempel, Schreibweise, Zeilen, Slug, Hex, HTML, Statistik, Regex-Tester, Textvergleich |
| Coding | Zahlensysteme, Zeichen (Unicode), Dateirechte, HTTP-Codes, Cron |
| Alltag | Bildschirmfoto, Zwischenablage-Verlauf, Farben, QR-Code, Text aus Bild, Passwörter, Einheiten, Prozent, Zeitzonen, Blindtext |
| System | Tool-Store |

Alles ohne KI-Bedarf läuft deterministisch und ohne Netz; die KI-Werkzeuge
nutzen das On-Device-Modell, sofern nicht anders eingestellt.

## Installieren

Fertige Bundles liegen unter
[Releases](https://github.com/kiritosky/nooktools/releases). Zip entpacken,
`Anvil.app` nach `/Programme` ziehen.

Anvil ist **nicht notarisiert** — für dieses Projekt gibt es kein
Developer-ID-Zertifikat. Beim ersten Start meldet sich deshalb Gatekeeper.
Einmalig im Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Anvil.app
```

Voraussetzung ist macOS 26 oder neuer: Apple Foundation Models und
`SpeechAnalyzer` gibt es darunter nicht.

## Selbst bauen

Voraussetzungen: macOS 26, Xcode 26 bzw. eine passende Swift-Toolchain.

```sh
./Scripts/run.sh                  # bauen und starten
./Scripts/build-app.sh release    # Release-Bundle
swift test                        # Tests
./Scripts/check-translations.py   # fehlende Übersetzungen
```

Mit eigenem Zertifikat:

```sh
./Scripts/build-app.sh release --sign "Developer ID Application: …"
```

Die App läuft **ohne** App Sandbox — Werkzeuge greifen frei aufs Dateisystem,
auf Git-Repos und auf lokale Prozesse zu. Ein Weg in den Mac App Store ist
nicht vorgesehen.

## Aufbau

| Target | Zweck |
| --- | --- |
| `AnvilKit` | Tool-Modell, Registry, Dependency-Kontext, Storage, Utilities |
| `AnvilUI` | Design-Tokens, Basis-Layouts, Komponentenbibliothek |
| `AnvilAI` | Sprachmodell-Abstraktion inkl. Foundation Models |
| `AnvilSpeech` | Aufnahme und Transkription über `SpeechAnalyzer` |
| `AnvilToolbox` | Die Tools und die generischen Tool-Engines |
| `AnvilApp` | App-Shell: Sidebar, Command-Palette, Einstellungen, Menüleiste |

Abhängigkeiten zeigen ausschließlich nach unten —
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) erklärt, warum.

## Dokumentation

| Datei | Inhalt |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Die sechs Targets und was in welches gehört |
| [docs/ADDING_A_TOOL.md](docs/ADDING_A_TOOL.md) | Vier Wege zu einem neuen Werkzeug, vom billigsten an |
| [docs/LOCALIZATION.md](docs/LOCALIZATION.md) | Wie Texte übersetzbar bleiben |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Regeln, Tests, Commits |

## Sprachen

Deutsch und Englisch. Der deutsche Quelltext ist zugleich der
Übersetzungsschlüssel, eine neue Sprache ist ein zusätzlicher `.lproj`-Ordner —
siehe [docs/LOCALIZATION.md](docs/LOCALIZATION.md).

## Status

In Entwicklung. Aufgebaut wird von unten nach oben: erst Kern und
Design-System, dann Dienste, dann Tools.

## Lizenz

GNU GPL v3 — siehe [LICENSE](LICENSE).
