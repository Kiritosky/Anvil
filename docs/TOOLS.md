# Werkzeuge

Erzeugt aus dem Quelltext — `./Scripts/tool-list.py` schreibt diese Datei neu.

**72 Werkzeuge**, davon 15 mit Sprachmodell.

## Sprache & Audio

| Werkzeug | Was es tut | Kennung |
| --- | --- | --- |
| Speech Studio | Diktieren, transkribieren, aufräumen | `speech.studio` |
| Diktat-Vokabular | Eigene Begriffe, die richtig geschrieben werden | `speech.vocabulary` |

## Coding

| Werkzeug | Was es tut | Kennung |
| --- | --- | --- |
| Commit-Message | Aus dem Diff eine saubere Message | `ai.commit` |
| Doku-Kommentar | Dokumentation zu einer Funktion | `ai.doccomment` |
| Fehler verstehen | Stacktrace oder Compiler-Meldung deuten | `ai.error` |
| Code erklären | Was macht dieser Code — und warum | `ai.explain` |
| Benennung | Bessere Namen für Dinge im Code | `ai.naming` |
| Regex bauen | Beschreibung rein, Ausdruck raus | `ai.regex` |
| Code-Review | Fehler, Risiken, Verbesserungen | `ai.review` |
| Shell-Befehl | Beschreibung in ein Kommando | `ai.shell` |
| SQL | Abfrage aus einer Beschreibung | `ai.sql` |
| Tests schreiben | Testfälle zu vorhandenem Code | `ai.tests` |
| JSON zu Typen | Aus einer Beispielantwort werden Modelle | `data.model` |
| JSON, YAML, TOML | Ineinander umwandeln | `data.structured` |
| Tabellen | CSV ansehen, sortieren, umwandeln | `data.table` |
| Cron | Ausdruck lesen und nächste Termine | `dev.cron` |
| Umgebungsdateien | Was wo fehlt, ohne Werte zu zeigen | `dev.env` |
| HTTP-Codes | Was 418 eigentlich heißt | `dev.http` |
| Codezeilen | Woraus ein Projekt besteht | `dev.lines` |
| Zahlensysteme | Dezimal, Hex, Binär, Oktal | `dev.numbers` |
| Dateirechte | chmod-Zahlen und rwx | `dev.permissions` |
| Zeichen | Code-Points, Namen, UTF-8 | `dev.unicode` |
| Patch | Diff lesen, anwenden, umkehren | `diff.patch` |
| In Dateien ersetzen | Über viele Dateien, mit Vorschau | `files.replace` |
| Repositories | Wo noch Arbeit liegt | `git.overview` |
| Netzrechner | CIDR rechnen, teilen, Adressen zuordnen | `net.subnet` |
| Testdaten | Namen, Adressen, IBAN — reproduzierbar | `sample.data` |
| Base64 | Kodieren und dekodieren | `text.base64` |
| Schreibweise | camelCase, snake_case, kebab-case … | `text.case` |
| Prüfsummen | MD5, SHA-1, SHA-256, SHA-512 — auch von Dateien | `text.hash` |
| Hex | Text und Hexadezimal | `text.hex` |
| HTML-Entities | Sonderzeichen escapen | `text.html` |
| JSON | Formatieren, verkleinern, prüfen | `text.json` |
| JWT | Token lesbar machen | `text.jwt` |
| Regex-Tester | Muster live gegen Text prüfen | `text.regex` |
| Zeitstempel | Unix-Zeit und ISO 8601 umrechnen | `text.timestamp` |
| URL | Escapen, entpacken, Parameter lesen | `text.url` |
| UUID | Kennungen erzeugen | `text.uuid` |
| App-Symbole | Der ganze Satz aus einer Vorlage | `vision.iconset` |

## Text & Daten

| Werkzeug | Was es tut | Kennung |
| --- | --- | --- |
| Diktat starten und beenden | Kürzel drücken, sprechen, noch einmal drücken | `Self.actionID` |
| Markdown | Gliedern, prüfen, nach HTML | `markdown.document` |
| Textvergleich | Zwei Fassungen gegenüberstellen | `text.compare` |
| Zeilen | Sortieren, entdoppeln, nummerieren | `text.lines` |
| Lesbarkeit | Wie schwer ein Text zu lesen ist | `text.readability` |
| Slug | URL-taugliche Kurzform | `text.slug` |
| Textstatistik | Wörter, Zeichen, Lesezeit | `text.stats` |

## Alltag

| Werkzeug | Was es tut | Kennung |
| --- | --- | --- |
| E-Mail | Aus Stichworten eine Nachricht | `ai.email` |
| Ideen sammeln | Varianten zu einer Frage | `ai.ideas` |
| Umschreiben | Gleicher Inhalt, anderer Ton | `ai.rewrite` |
| Zusammenfassen | Das Wesentliche aus langem Text | `ai.summarize` |
| Übersetzen | Natürlich, nicht wörtlich | `ai.translate` |
| Zwischenablage | Alles, was du kopiert hast | `everyday.clipboard` |
| Farben | Umrechnen und Kontrast prüfen | `everyday.color` |
| Blindtext | Platzhalter in der richtigen Länge | `everyday.lorem` |
| Farbliste | Ganze Paletten prüfen und ausgeben | `everyday.palette` |
| Passwörter | Zufällig, ohne Verwechslungsgefahr | `everyday.password` |
| Prozent | Anteil, Aufschlag, Veränderung | `everyday.percent` |
| QR-Code | Erzeugen und aus Bildern lesen | `everyday.qr` |
| Zeitzonen | Wie spät ist es wo | `everyday.timezones` |
| Einheiten | Länge, Gewicht, Temperatur, Tempo, Daten | `everyday.units` |
| Archive | Hineinsehen, ein- und auspacken | `files.archive` |
| Ordner vergleichen | Was fehlt wo, und was ist anders | `files.compare` |
| Dubletten | Was doppelt auf der Platte liegt | `files.duplicates` |
| Umbenennen | Im Stapel, mit Vorschau | `files.rename` |
| Speicherplatz | Wo der Platz hingeht, nach Größe sortiert | `files.space` |
| PDF | Zusammenführen, teilen, drehen, auslesen | `pdf.pages` |
| Bildschirmfoto | Aufnehmen, lesen, weitergeben | `screen.shot` |
| Zeitrechner | Dauern, Zeitstempel, Abstände | `time.math` |
| Bild umwandeln | Format, Größe, Metadaten | `vision.image` |
| Text aus Bild | Bildschirmausschnitt, Screenshot oder Datei | `vision.text` |

## Eigene Werkzeuge

| Werkzeug | Was es tut | Kennung |
| --- | --- | --- |
| Eigenes Werkzeug | Aus einem Prompt ein Werkzeug machen | `custom.builder` |

## System

| Werkzeug | Was es tut | Kennung |
| --- | --- | --- |
| Tool-Store | Werkzeuge ein- und ausschalten | `system.store` |
