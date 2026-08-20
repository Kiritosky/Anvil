<div align="center">

# Anvil

**A native macOS toolbox for everyday work and for building software —
with AI that runs on the device instead of in the cloud.**

[![Build](https://github.com/Kiritosky/Anvil/actions/workflows/build.yml/badge.svg)](https://github.com/Kiritosky/Anvil/actions/workflows/build.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Top language](https://img.shields.io/github/languages/top/Kiritosky/Anvil?color=F05138)](https://github.com/Kiritosky/Anvil/search?l=swift)
[![Code size](https://img.shields.io/github/languages/code-size/Kiritosky/Anvil)](https://github.com/Kiritosky/Anvil)
[![Last commit](https://img.shields.io/github/last-commit/Kiritosky/Anvil)](https://github.com/Kiritosky/Anvil/commits)
[![Stars](https://img.shields.io/github/stars/Kiritosky/Anvil?style=flat&logo=github)](https://github.com/Kiritosky/Anvil/stargazers)
[![License](https://img.shields.io/github/license/Kiritosky/Anvil?color=blue)](LICENSE)

**72 tools** · **on-device** · **works offline** · German & English

[Tools](docs/TOOLS.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Add a tool](docs/ADDING_A_TOOL.md) · [Contributing](CONTRIBUTING.md)

Auf Deutsch: **[README.md](README.md)**

</div>

---

Anvil is one window with a sidebar full of tools: dictate, reshape text,
convert images, look through repositories, open archives, count lines of code.
Everything that works without a language model is deterministic and needs no
network. Whatever does need a model uses the local one from **Apple
Intelligence** by default.

> Companion app to Nook.

## Why

- **Speech first.** Dictate, transcribe live, then have a model clean up filler
  words, false starts and punctuation — smoothed, or rewritten into prose, bullet
  points, a commit message or a summary.
- **From anywhere.** A global shortcut (⌥⌘D) shows a small bubble above any app.
  Speak, press the shortcut again — the text lands in whatever field the cursor
  is in. The main window stays closed.
- **On-device first.** External providers are possible, never required. If you
  have Claude Code, Codex or the Gemini CLI installed, Anvil uses them through
  their existing sign-in, without an API key.
- **Bulk actions everywhere.** Thirty images, a hundred files, every repository
  at once — no tool stops at a single item.
- **Nothing confidential on disk.** Tools remember your last input — unless it
  looks like a key, and never for JWTs, checksums, Base64 and hex. Results are
  never stored.
- **GitHub in one click.** Sign in through GitHub's device flow, token in the
  keychain, and the only scope asked for is `repo`.
- **Extensible.** A tool is a registration, not a special case. Pure prompt
  tools are added as a JSON file, without recompiling.

## Tools

| Area | Count | Examples |
| --- | ---: | --- |
| Coding | 37 | Repositories, patch, subnet calculator, JSON to types, lines of code, env files, app icons, commit message, code review |
| Everyday | 24 | Screenshot, text from image, PDF, QR code, duplicates, disk space, archives, translate |
| Text & data | 7 | Markdown, text compare, readability, lines, slug, text statistics |
| Speech & audio | 2 | Speech Studio, dictation vocabulary |
| System & custom | 2 | Tool store, custom tool |

Fifteen of them ask a language model — the other 57 compute the answer
themselves.

The full list lives in **[docs/TOOLS.md](docs/TOOLS.md)** — generated from the
source, not maintained by hand.

## Install

There is no finished app to download yet; until the first release you build it
yourself — three lines, see below.

You need **macOS 26** or newer: Apple Foundation Models and `SpeechAnalyzer`
do not exist below that.

## Build it yourself

```sh
git clone https://github.com/Kiritosky/Anvil.git && cd Anvil
./Scripts/run.sh                  # build and launch
```

Other ways in:

```sh
./Scripts/build-app.sh release    # release bundle in .build/release/Anvil.app
swift test                        # unit tests
./Scripts/check-translations.py   # missing translations
./Scripts/tool-list.py            # rewrite docs/TOOLS.md
```

Signing with your own certificate:

```sh
./Scripts/build-app.sh release --sign "Developer ID Application: …"
```

The app runs **without the App Sandbox** — tools reach the file system, git
repositories and local processes freely. There is no path to the Mac App Store.

## Architecture

| Target | Purpose |
| --- | --- |
| `AnvilKit` | Tool model, registry, context, storage, utilities |
| `AnvilUI` | Design tokens, layouts, component library |
| `AnvilAI` | Language models: Foundation Models, external providers, CLI agents |
| `AnvilSpeech` | Recording and transcription through `SpeechAnalyzer` |
| `AnvilToolbox` | The tools and the generic tool engines |
| `AnvilApp` | App shell: sidebar, command palette, settings, menu bar |

Dependencies only ever point downwards — the reasoning is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Documentation

The documentation is written in German.

| File | Contents |
| --- | --- |
| [docs/TOOLS.md](docs/TOOLS.md) | Every tool, generated from the source |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The six targets and what belongs in which |
| [docs/ADDING_A_TOOL.md](docs/ADDING_A_TOOL.md) | Four ways to a new tool, cheapest first |
| [docs/LOCALIZATION.md](docs/LOCALIZATION.md) | How display text stays translatable |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Rules, tests, commits |
| [CLAUDE.md](CLAUDE.md) | Project rules the tools themselves follow |

## Languages

German and English. The German source text doubles as the translation key;
another language is one more `.lproj` folder — see
[docs/LOCALIZATION.md](docs/LOCALIZATION.md).

## Windows

One main window with a sidebar — and every tool in a window of its own as well
(⇧⌘N, or right-click in the sidebar). The same tool may be open several times,
each copy with its own state and its own size.

## Status

Version 1.0, under active development. It was built from the bottom up: core
and design system first, then the services, then the tools.

## License

[GNU GPL v3](LICENSE).
