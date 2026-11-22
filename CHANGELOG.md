# Changelog

All notable changes to DeepL-oFM. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions use
[Semantic Versioning](https://semver.org/).

## [1.1.1] — 2026-11-22

### Changed

- File translation lives only in the **Files** tab. The redundant in-window
  File menu and the global drop target on the translation view were removed, so
  a document can no longer be dropped into the text/chat screen.

## [1.1.0] — 2026-11-22

### Added

- **Files tab**: a dedicated form that takes a document, the target language
  and a Translate button. A percentage progress bar follows the translation,
  the output is created as `name_<language>.<extension>` and Save writes it
  wherever you need. The document text is not loaded into the translation
  panes.
- **DeepL Write** mode: rewrite text for clarity, grammar and style while
  keeping the meaning, with the same rendered/text/Markdown views.
- **Voice picker** for speech, with a stop control that works without quitting
  the app. Enhanced and Premium system voices are listed when installed.
- **Percentage progress** in the text and file translation bars.

### Changed

- The Dock icon appears while the window is open and disappears when the window
  is hidden, even in menu-bar-only mode.

## [1.0.10] — 2026-11-22

### Added

- iPhone app source in `ios/`: the same translation core, SwiftUI interface,
  nine interface languages, cloud providers and a custom LAN endpoint. Build
  instructions are in `ios/README.md`.

### Fixed

- Closing the window keeps DeepL-oFM in the menu bar; the clipboard hotkey now
  brings the window back instead of leaving the app active without a window.

## [1.0.9] — 2026-11-22

### Added

- Dock icon switch: hide DeepL-oFM from the Dock and keep it in the menu bar.
  Turning the Dock icon off enables the menu bar icon automatically when it is
  the last way to reach the app.
- README editions for German, French, Spanish, Polish, Portuguese and Italian,
  with localized screenshots, the demo GIF and a language switch across all
  nine editions.

## [1.0.8] — 2026-11-22

### Added

- Interface languages: German, French, Spanish, Polish, Portuguese and Italian,
  alongside English, Ukrainian and Russian.
- Formatting-aware paste: HTML or RTF copied from a browser or a word processor
  is converted to Markdown, so headings, lists, links and emphasis survive
  translation.
- Rendered Markdown view in both panes, with a toggle back to the raw markup.
- File translation for `.txt`, `.md`, `.pdf` and `.docx`, including drag and
  drop and saving the translation back in the original format.
- DOCX is updated in place (only `word/document.xml`), and PDF keeps the
  original pages, images and layout with the translation drawn over each text
  block.
- Refined style and tone selectors; Settings moved into the ⋯ menu, with Escape
  returning to the translation. The Markdown view keeps the line structure of
  PDF and DOCX documents.
- Result pane with three views — rendered Markdown, plain text without markup,
  and the raw Markdown source — with Copy following the active view.
- Paste from clipboard and Translate now actions in the empty panes.

### Fixed

- A model id at the end of a sentence (`Hy-MT2.`) no longer sends the whole line
  back to the source language.
- The hotkey status text updates immediately when the shortcut changes.

### Changed

- Refreshed interface: gradient background, brand mark, provider icon, grouped
  language switcher and settings card accents.
- The interface-language picker is a menu, ready for nine locales.

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

[1.1.1]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.1.1
[1.1.0]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.1.0
[1.0.10]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.10
[1.0.9]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.9
[1.0.8]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.8
[1.0.7]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.7
[1.0.6]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.6
[1.0.5]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.5
[1.0.4]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.4
[1.0.3]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.3
[1.0.2]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.2
[1.0.1]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.1
[1.0.0]: https://github.com/Lexus2016/deepl-on-free-models/releases/tag/v1.0.0
