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
- **Von überall.** Ein globales Tastenkürzel (voreingestellt ⌥⌘D) öffnet ein
  schwebendes Diktatfeld über jeder App. Sprechen, Kürzel noch einmal drücken —
  der aufgeräumte Text liegt in der Zwischenablage oder wird direkt eingefügt.
- **On-Device zuerst.** Standardweg ist das lokale Apple-Intelligence-Modell.
  Externe Anbieter sind möglich, aber nie Voraussetzung.
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
