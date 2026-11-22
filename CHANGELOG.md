# Changelog

All notable changes to DeepL-oFM. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions use
[Semantic Versioning](https://semver.org/).

## [1.0.7] — 2026-11-22

### Added

- Optional fallback provider and model, with its own Keychain-backed key and a
  live model list.
- “Load the translator at launch”: connects to the provider, refreshes the model
  list and warms up a local model.
- Per-language screenshots in `docs/screenshots/{en,uk,ru}/`.
- Trilingual `CONTRIBUTING` and `SECURITY` documents.

### Fixed

- Groq: Unicode hyphens in model IDs (`Hy‑MT2`, U+2011) no longer make the app
  discard a valid translation.
- History tab is hidden while “Keep translation history” is off.
- Wider translation panes and larger line spacing.

### Changed

- Repository description and update feed for 1.0.7.
- GitHub release assets include the DMG, ZIP and appcast.

## [1.0.6] — 2026-11-22

### Added

- Sparkle 2 automatic updates with a signed appcast and a manual
  **Check for Updates…** action.
- Optional automatic download and installation.
- DMG contains an **Applications** shortcut for drag-and-drop installation.

### Fixed

- Hardened runtime and secure timestamp for notarization.
- Sparkle framework is embedded, signed and loaded from
  `Contents/Frameworks`.

## [1.0.5] — 2026-11-22

### Added

- English, Ukrainian and Russian READMEs.
- Notarized DMG; Developer ID signature survives rebuilds.

### Changed

- Renamed the app to DeepL-oFM; history migrates to
  `~/Library/Application Support/DeepL-oFM`.
- Internal bundle identifier `ua.admin.hymt` is kept for permissions and keys.

## [1.0.4] — 2026-11-22

### Added

- Progress display while translating; the finished text appears once.
- Markdown/HTML/RTF clipboard copy and a visible Copy button.
- Protection for URLs, e-mail, model IDs and inline code.

## [1.0.3] — 2026-11-22

### Fixed

- Accessibility permission survives rebuilds with Developer ID signing.
- Hotkey labels show the actual key (`⌥'`, `⌥є`, `⌥⌘T`).

## [1.0.2] — 2026-11-22

### Added

- Provider catalog, Connect flow and model filtering.
- Ollama Cloud, OpenRouter, Groq, Cerebras, LM Studio, oMLX, llama.cpp and
  custom OpenAI-compatible servers.

## [1.0.1] — 2026-11-22

### Fixed

- First-run connection checks and model selection.

## [1.0.0] — 2026-11-22

### Added

- Initial native SwiftUI translator with Hy-MT2 7B through Ollama.
- Two-pane translation, history, hotkeys and Ukrainian/Russian/English UI.

[1.0.7]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.7
[1.0.6]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.6
[1.0.5]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.5
[1.0.4]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.4
[1.0.3]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.3
[1.0.2]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.2
[1.0.1]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.1
[1.0.0]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.0
