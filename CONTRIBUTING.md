# Contributing

**English** · [Українська](CONTRIBUTING.uk.md) · [Русский](CONTRIBUTING.ru.md)

Thanks for helping DeepL-oFM. Keep changes small, tested and documented in all
three languages.

## Build and test

Requirements: macOS 14+, Xcode Command Line Tools, and Ollama for local models.

```bash
swift test
./build.sh
open build/DeepL-oFM.app
```

`./setup.sh` pulls the default Hy-MT2 model, runs a test translation and builds
the app. `./build.sh` embeds and signs Sparkle, so always use it for a bundle,
not a bare `swift build`.

## Code

- Swift 5.9+, SwiftUI, macOS 14+.
- Keep user-facing strings in `Sources/HyMT/Support/Localization.swift`; never
  hard-code English UI text.
- Provider credentials go to the Keychain (`Sources/HyMT/Support/Keychain.swift`).
  Never write keys to UserDefaults, logs, history or the repository.
- Preserve the existing layering: `Models/` data, `Services/` networking and
  history, `Views/` UI, `Support/` utilities.
- Add a regression test for every bug fix when the behavior is testable without
  a live model.

## Documentation and screenshots

- `README.md` is canonical; `README.uk.md` and `README.ru.md` are siblings. Keep
  the same sections, numbers and claims in all three.
- Screenshots live in `docs/screenshots/{en,uk,ru}/` and must come from the real
  app in that language: `translation.png`, `settings.png`, `updates.png`.
- `SECURITY.md` and `CONTRIBUTING.md` also have `.uk.md` and `.ru.md` siblings.
- Use plain language. No marketing claims that the code does not prove.

## Pull requests

- One focused change per PR; describe the user-visible effect.
- Run `swift test` and `./build.sh`.
- Update the changelog for a release, and the READMEs/screenshots if the UI
  changed.
- Scan staged files for secrets, local paths and e-mail addresses before pushing:

  ```bash
  git diff --cached --name-only
  git grep -nE "(api[_-]?key|token|secret)\s*[:=]\s*['\"][A-Za-z0-9_-]{16,}"
  ```

- Do not commit `.env`, `*.key`, `*.pem`, models, build output or local paths.

## Releases

A release is a tag **and** a GitHub Release with assets, not just a tag:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`; add a `CHANGELOG.md` entry.
2. Run tests and `./build.sh`; commit and push.
3. Build/sign/notarize the DMG with an `Applications` shortcut, staple it and
   verify with `spctl`.
4. Regenerate and EdDSA-sign `appcast.xml` with Sparkle's
   `generate_appcast`/`sign_update`.
5. `gh release create` with the DMG, ZIP and `appcast.xml`; verify the live
   feed and a real update.

## License

By contributing you agree that your contribution is licensed under the MIT
License in [LICENSE](LICENSE).
