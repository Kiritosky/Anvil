# Anvil

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
- **Eigene Wörter.** Eine persönliche Wortliste wird im Diktat deterministisch
  durchgesetzt — Produktnamen, Kollegen, Code-Bezeichner stehen richtig da,
  bevor das Modell den Text überhaupt sieht.
- **On-Device zuerst.** Standardweg ist das lokale Apple-Intelligence-Modell.
  Externe Anbieter sind möglich, aber nie Voraussetzung. Auch Texterkennung
  aus Bildern läuft lokal über Vision.
- **Erweiterbar von Anfang an.** Tools sind Registrierungen, keine
  Sonderfälle. Reine Prompt-Tools kommen ohne Neukompilieren als JSON-Datei
  dazu, und im Tool-Store lässt sich jedes Tool ein- und ausschalten.

## Status

In Entwicklung. Aufgebaut wird von unten nach oben: erst Kern und
Design-System, dann Dienste, dann Tools.

## Aufbau

| Target | Zweck |
| --- | --- |
| `AnvilKit` | Tool-Modell, Registry, Dependency-Kontext, Storage, Utilities |
| `AnvilUI` | Design-Tokens, Basis-Layouts, Komponentenbibliothek |
| `AnvilAI` | Sprachmodell-Abstraktion inkl. Foundation Models |
| `AnvilSpeech` | Aufnahme und Transkription über `SpeechAnalyzer` |
| `AnvilToolbox` | Die Tools und die generischen Tool-Engines |
| `AnvilApp` | App-Shell: Sidebar, Command-Palette, Einstellungen, Menüleiste |

## Was drin ist

| Bereich | Werkzeuge |
| --- | --- |
| Sprache & Audio | Speech Studio, Diktat-Vokabular |
| KI-Werkzeuge | 15 Prompt-Tools: Commit-Message, Code-Review, Tests, Regex, Shell, Übersetzen, E-Mail … |
| Text & Daten | JSON, Base64, URL, JWT, Prüfsummen, UUID, Zeitstempel, Schreibweise, Zeilen, Slug, Hex, HTML, Statistik, Regex-Tester, Textvergleich |
| Coding | Zahlensysteme, Zeichen (Unicode), Dateirechte, HTTP-Codes, Cron |
| Alltag | Zwischenablage-Verlauf, Farben, QR-Code, Text aus Bild, Passwörter, Einheiten, Prozent, Zeitzonen, Blindtext |
| System | Tool-Store |

Alles ohne KI-Bedarf läuft deterministisch und ohne Netz; die KI-Werkzeuge
nutzen das On-Device-Modell, sofern nicht anders eingestellt.

## Bauen

Voraussetzungen: macOS 26, Xcode 26 bzw. eine passende Swift-Toolchain.

```sh
./Scripts/run.sh                  # bauen und starten
./Scripts/build-app.sh release    # signiertes Release-Bundle
swift test                        # Tests
./Scripts/check-translations.py   # fehlende Übersetzungen
```

## Sprachen

Deutsch und Englisch. Der deutsche Quelltext ist zugleich der
Übersetzungsschlüssel, eine neue Sprache ist ein zusätzlicher `.lproj`-Ordner —
siehe [docs/LOCALIZATION.md](docs/LOCALIZATION.md).

## Lizenz

GNU GPL v3 — siehe [LICENSE](LICENSE).
