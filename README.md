# DeepL-oFM — a native macOS translator for local and free models

**English** · [Українська](README.uk.md) · [Русский](README.ru.md)

[![Release](https://img.shields.io/github/v/release/Lexus2016/deepl-on-free-models?label=release)](https://github.com/Lexus2016/deepl-on-free-models/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

A two-pane translation app in the spirit of DeepL, powered by the local
**Hy-MT2 7B** model or a cloud provider. Works offline by default; supports
Ollama, Ollama Cloud, OpenRouter, Groq, Cerebras, LM Studio, oMLX, llama.cpp
and any OpenAI-compatible server.

> Not affiliated with DeepL SE. “DeepL-oFM” describes the interface style
> (“on Free Models”); it is an independent open-source project.

![Translation](docs/screenshot.png)

![Settings](docs/settings.png)

## Features

- Two-pane translation with a progress indicator. The finished text appears
  only when every line has been checked — no partial or repeated garbage.
- Automatic translation while typing (configurable delay).
- Two global hotkeys:
  - **⌥⌘T** — translate the clipboard;
  - **⌥⌘C** — copy the selected text in any app, open DeepL-oFM and translate it.
- 33 Hy-MT2 languages (38 variants in the picker) with language search.
- Styles **Auto / Literal / Natural** and tones **Default / Formal / Casual**,
  matching the Hy-MT2 model card.
- Model catalog, a **Connect** button, provider model list and name filter.
- Visible **Copy** button: puts Markdown, HTML and RTF on the clipboard at once.
- **Automatic updates** through Sparkle 2: a daily signed-feed check, a manual
  **Check for Updates…** button, and an optional fully automatic install.
- History with search, copy and delete.
- System text-to-speech for the original and the translation.
- Interface in **English, Ukrainian and Russian** (follows the system by default).
- Menu-bar icon and quick clipboard translation from there.

## Providers

| Provider | Type | API key | Notes |
|---|---|---|---|
| Ollama | local | not needed | local models and `-cloud` models via `ollama signin` |
| Ollama Cloud | cloud | required | direct `https://ollama.com/v1` |
| LM Studio | local | usually not needed | local server |
| oMLX | local | usually not needed | MLX server for Apple Silicon |
| llama.cpp | local | usually not needed | `llama-server --api` |
| OpenRouter | cloud | required | free models use the `:free` suffix |
| Groq | cloud | required | free tier with rate limits |
| Cerebras | cloud | required | free tier with limits |
| Custom | any | optional | any OpenAI-compatible endpoint |

The API-key field is available for **every** provider: leave it empty for a
local server unless your proxy/LM Studio requires a token. Keys are stored in
the **macOS Keychain** and never written to the repository.

## Models

### Local via Ollama

| Model | ID | Size | Languages |
|---|---|---|---|
| Hy-MT2 7B | `hy-mt2:7b` | ≈4.6 GB | 33 |
| Hy-MT2 1.8B | `hy-mt2:1.8b` | light | 33 |
| Hy-MT2 30B-A3B | `hy-mt2:30b` | large, MoE | 33 |
| TranslateGemma 4B | `translategemma:4b` | ≈3 GB | 55 |
| TranslateGemma 12B | `translategemma:12b` | ≈8 GB | 55 |
| Qwen3.5-MT 2B | `qwen3.5-mt:2b` | 2B | translation |
| Aya Expanse 8B | `aya-expanse:8b` | 8B | 23 |
| Qwen3 8B | `qwen3:8b` | 8B | general |

```bash
ollama pull maternion/hy-mt2:7b
ollama cp maternion/hy-mt2:7b hy-mt2:7b
```

The **Model catalog…** button in Settings shows install commands with a copy
button.

### Ollama Cloud — both modes

1. **Through the local Ollama daemon.** Sign in and use `-cloud` models:

   ```bash
   ollama signin
   ollama run gpt-oss:120b-cloud
   ```

   Choose **Ollama** in the app, press **Connect**, and the list includes both
   local and `-cloud` models. The app needs no key here; the daemon
   authenticates.

2. **Direct Ollama Cloud API.** Choose **Ollama Cloud**, paste a key from
   [ollama.com/settings/keys](https://ollama.com/settings/keys). Base URL:
   `https://ollama.com/v1`; no local server required.

### Cloud providers

- **OpenRouter** ([keys](https://openrouter.ai/keys)): `tencent/hy-mt2-7b`,
  `tencent/hy-mt2-1.8b`, `tencent/hy-mt2-30b-a3b`; free models such as
  `google/gemma-4-31b-it:free`, `google/gemma-4-26b-a4b-it:free`,
  `nvidia/nemotron-3-ultra-550b-a55b:free`, `inclusionai/ling-3.2-flash:free`;
  fast paid options such as `google/gemini-3.1-flash-lite`,
  `qwen/qwen3.7-flash`, `openai/gpt-5-mini`.
- **Groq** ([keys](https://console.groq.com/keys)): `openai/gpt-oss-120b`
  (~500 t/s), `openai/gpt-oss-20b` (~1000 t/s),
  `llama-3.3-70b-versatile`, `qwen/qwen3.8-27b` (preview).
- **Cerebras** ([keys](https://cloud.cerebras.ai)): `gpt-oss-120b`
  (~3000 t/s), `qwen-3.8-27b` (~1850 t/s).

Provider catalogs change; **Connect** always fetches the live list from the
server.

## Install

### Ready-built app

Download the notarized DMG from
[Releases](https://github.com/Lexus2016/deepl-on-free-models/releases), open it
and drag **DeepL-oFM** onto the **Applications** folder in the same window. The
disk image is signed and notarized; it contains the app and an Applications
shortcut, so installation is the usual drag-and-drop. Gatekeeper accepts the app
without a right-click workaround.

### From source

Requirements: macOS 14+, Xcode Command Line Tools,
[Ollama](https://ollama.com).

```bash
git clone https://github.com/Lexus2016/deepl-on-free-models.git
cd deepl-on-free-models

./setup.sh          # model, test translation, build
# or manually:
ollama pull maternion/hy-mt2:7b
ollama cp maternion/hy-mt2:7b hy-mt2:7b
./build.sh

open build/DeepL-oFM.app
cp -R build/DeepL-oFM.app /Applications/
```

The app lives in the menu bar; closing the window keeps the hotkeys alive.
Add it to **Login Items** if it should start after a reboot.

## First connection

1. **Settings → Model and provider**.
2. Choose a provider. Local Ollama defaults to `http://127.0.0.1:11434`.
3. Enter an API key if the provider needs one.
4. Press **Connect**: the server is checked and its models are listed.
5. Filter by part of the name and choose a model.
6. **Model catalog…** offers curated translation models with install commands.

## Hotkeys and Accessibility

| Shortcut | Action |
|---|---|
| **⌥⌘T** | translate the clipboard and bring the app forward |
| **⌥⌘C** | copy the selected text, open DeepL-oFM and translate |

Both are configurable in **Settings → Hot key**; at least one of ⌘, ⌥ or ⌃ is
required. The field shows the actual key you pressed (for example `⌥'`, `⌥є`,
`⌥⌘T`).

The selected-text shortcut needs **Accessibility** access: the app sends `⌘C`
to the active app. The status and an **Open System Settings** button are in
Settings. If access was granted to an older build, remove DeepL-oFM from the
Accessibility list, add the current app and enable it. The app shows its
current path.

`build.sh` signs with your **Developer ID Application** or **Apple Development**
identity when one is in the Keychain, so Accessibility survives rebuilds. With
ad-hoc signing it may need to be granted again. Force an identity with:

```bash
HYMT_SIGN_IDENTITY="Developer ID Application: …" ./build.sh
```

## Interface language

**Settings → Behavior → Interface language**: System, English, Ukrainian,
Russian. Changes apply immediately, without a restart. Model prompts remain in
English — the language Hy-MT2 was trained on.

## Updates

![Updates](docs/updates.png)

The app uses **Sparkle 2** with a signed appcast:

- checks for updates once a day (`SUScheduledCheckInterval = 86400`);
- **Settings → About → Check for Updates…** and the app menu check on demand;
- **Automatically download and install updates** is opt-in (off by default);
- the feed is
  [appcast.xml](https://raw.githubusercontent.com/Lexus2016/deepl-on-free-models/main/appcast.xml);
- every update enclosure is signed with EdDSA (`SUPublicEDKey` in the app) and
  the DMG is signed and notarized. Sparkle refuses an update whose signature or
  code signature does not match.

The appcast is generated with Sparkle’s `generate_appcast` and committed to the
repository, so the update history is auditable.

## Formatting and progress

The text is split into **lines**: every non-empty line is translated separately;
blank lines are preserved. Very long lines are split by sentences and rejoined
into one line. Windows (`CRLF`) and old Mac (`CR`) line endings are normalized.

- `#` headings, `-`/`1.` list markers, block quotes and task-list markers are
  kept; the prefix is reattached after translation.
- Short lines use a neutral instruction: the literal style made Hy-MT2 talk to
  itself and leak role tokens. Longer fragments use the selected style.
- Long fragments that contain Markdown get one extra sentence in the
  instruction, before the final colon: preserve headings, lists, bold, italic,
  links and inline code. Short fragments skip it — on a short line the extra
  instruction sometimes made the model rewrite the link instead of translating
  it.
- URLs, e-mail addresses, model IDs and inline code are protected and restored
  exactly (`console.groq.com/keys`, `tencent/hy-mt2-7b`, `` `qwen3:8b` ``).
  A URL at the end of a sentence does not swallow the full stop.
- Trailing `:`, `;`, `.`, `!`, `?` are preserved; if the model changes the final
  punctuation, the source punctuation wins.
- Each block is checked for empty output, repetition, CJK or Cyrillic characters
  that do not belong to the target script, role tokens, instruction echoes,
  first-person meta answers and excessive length. A translation into a
  non-Latin language must contain at least one character of that script, so an
  English sentence cannot silently pass as Ukrainian. Failed blocks are retried
  with lower temperature and a different prompt. If a long paragraph still
  fails, the app translates it sentence by sentence and rejoins the line; known
  wrappers (“Here is the translation:”) are stripped. If a line still cannot be
  translated, it is left in the source language and a warning is shown — the
  rest of the document is still translated.

While translating, the pane shows **progress** (`X of Y`) instead of partial
text. The completed translation appears at once.

## Copy and Markdown

The **Copy** button places three formats on the clipboard:

- **Markdown** — for chats, GitHub and plain editors;
- **HTML** — for Notes, Word, browsers;
- **RTF** — for rich-text apps.

Markdown headings, lists, block quotes, `**bold**`, `*italic*`, links and
`` `code` `` are preserved when present; the HTML/RTF version renders them.
Links are rendered only for `http`, `https`, `mailto` and relative URLs; a
`javascript:` target is dropped. Inline formatting that TextEditor did not
retain on paste (for example bold text copied from a browser) cannot be
reconstructed. Fenced code blocks are translated as ordinary lines, not as
code. `⇧⌘C` also copies the translation.

## Prompts

Hy-MT2 has no default system prompt: the instruction and the source text travel
in one message.

| Style | Instruction |
|---|---|
| Auto | `Translate the following text into {target_language}. Note that you should only output the translated result without any additional explanation:` |
| Literal | `Please translate the following text into {target_language}. Note that the translation style must strictly conform to [literal, word for word]:` |
| Natural | `Please translate the following text into {target_language}. Note that the translation style must strictly conform to [natural and idiomatic, conveying the meaning rather than the wording]:` |

Tone suffix: `; formal and professional` or `; casual and conversational`.
Auto + Default gives the base instruction. The generated prompt is shown in
**Settings → System prompt**.

## Parameters

Tencent’s defaults for Hy-MT2 7B are used:

```
temperature    = 0.7
top_p          = 0.6
top_k          = 20
repeat_penalty = 1.05
num_ctx        = 8192
```

All are editable. If the source language is auto-detected and equals the target,
the app selects another language (interface language or the other side of the
pair) instead of translating text into itself.

## Security and privacy

- API keys live in the **macOS Keychain**, one item per provider. They are not
  written to UserDefaults, logs, history or the repository.
- The repo contains no keys, tokens, `.env` files or models; `.gitignore`
  excludes `build/`, `.build/`, `.env*`, `*.key`, `*.pem`, `*.gguf`, logs and
  sqlite files.
- Local models (Ollama, LM Studio, oMLX, llama.cpp) keep the text on the machine.
- Cloud providers receive the translated text under their own terms.
- No telemetry, analytics or background connection to the authors’ servers.
- Accessibility is used only to send `⌘C` before translating selected text.

See [SECURITY.md](SECURITY.md). If a key leaks, revoke it in the provider’s panel
immediately.

## Troubleshooting

- **Model not found** — check `ollama list`; press **Connect** to see the live
  list. The name must match exactly.
- **Server unavailable** — start `ollama serve` or the relevant server and check
  the URL.
- **HTTP 401/403** — verify the cloud API key.
- **Some lines remain in the source language** — press **Retry** or switch the
  style/model. The model occasionally produces unstable output; the app rejects
  repetition and role tokens.
- **Selected text does not copy** — grant Accessibility; if it was granted to an
  older build, remove the old entry and add the current app.
- **Hotkey does not work** — the combination may be taken; record another one.
- **Brand names or abbreviations look wrong** — the 7B model may mistranslate
  domain terms; use Natural style or a different model.
- Debug run:

  ```bash
  DEEPLOFM_DEBUG=1 ./build/DeepL-oFM.app/Contents/MacOS/DeepL-oFM --prefill "Hello world"
  ```

## Architecture

```
Sources/HyMT/
  DeepL-oFMApp.swift        app entry, menu, AppDelegate
  AppState.swift            state, debounce, history, hotkeys, progress
  Models/                   languages, prompts, settings, providers, catalog
  Services/                 translation (Ollama/OpenAI streaming), probe,
                            hotkeys, history
  Views/                    SwiftUI interface
  Support/                  localization, Keychain, clipboard, sanitizers
Tests/HyMTTests/            unit tests (prompts, chunker, tokens, clipboard)
```

Data: `~/Library/Application Support/DeepL-oFM/history.json`; settings in
`UserDefaults` (`ua.admin.hymt`); keys in the Keychain (`ua.admin.hymt`). The
internal bundle identifier is kept so Accessibility, settings and existing API
keys survive the rename from HyMT; the history file is migrated once from the
old `Application Support/HyMT` folder.

## Status and limitations

- The bundled 7B model is small. It can mistranslate abbreviations and brand
  names (for example `т/с` as “tons per second”), and on rare short fragments it
  still produces unstable output. The app rejects degenerate blocks and leaves
  the source line with a warning; press **Retry**, switch to **Natural**, or use
  a larger/cloud model.
- Formatting is line-based: every source line is a translation unit. A paragraph
  hard-wrapped across several lines keeps those line breaks; it is not reflowed.
- Inline formatting that arrives as rich text (bold/links pasted from a browser
  into TextEditor) is not available to the app. Markdown syntax typed or pasted
  as characters is preserved.
- No glossary or terminology memory yet. This is deliberate: the app stays a
  transparent client for the model you choose.

## Building a signed release

`build.sh` signs the bundle with **Developer ID Application** when the identity
is in the Keychain, otherwise with Apple Development, otherwise ad-hoc. The
Developer ID path enables the hardened runtime and a secure timestamp, which is
required for notarization. The script also embeds and signs
`Sparkle.framework` from SwiftPM, adds the `@executable_path/../Frameworks`
rpath, and verifies the whole bundle.

```bash
./build.sh
ditto -c -k --keepParent build/DeepL-oFM.app build/DeepL-oFM.zip

xcrun notarytool submit build/DeepL-oFM.zip \
  --keychain-profile "your-notary-profile" --wait
xcrun stapler staple build/DeepL-oFM.app

# DMG with an Applications shortcut for drag-and-drop install
STAGE=build/dmg-stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto build/DeepL-oFM.app "$STAGE/DeepL-oFM.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DeepL-oFM" -srcfolder "$STAGE" \
  -ov -format UDZO build/DeepL-oFM.dmg

codesign --force --timestamp --sign "Developer ID Application: …" build/DeepL-oFM.dmg
xcrun notarytool submit build/DeepL-oFM.dmg \
  --keychain-profile "your-notary-profile" --wait
xcrun stapler staple build/DeepL-oFM.dmg
```

Then generate and sign the Sparkle feed:

```bash
mkdir -p build/appcast
cp build/DeepL-oFM.dmg build/appcast/
cp release-notes.md build/appcast/DeepL-oFM.md
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --account deepl-ofm \
  --download-url-prefix "https://github.com/Lexus2016/deepl-on-free-models/releases/download/vX.Y.Z/" \
  build/appcast
```

Commit the generated `appcast.xml` and upload the DMG and appcast to the GitHub
release. The EdDSA private key stays in the login Keychain; only the public key
is in `Info.plist`.

`notarytool` uses a profile created once with
`xcrun notarytool store-credentials`; no password belongs in the repository.

## License

Code: MIT. Hy-MT2 7B is distributed by Tencent under its own license; see
[huggingface.co/tencent/Hy-MT2-7B](https://huggingface.co/tencent/Hy-MT2-7B).
