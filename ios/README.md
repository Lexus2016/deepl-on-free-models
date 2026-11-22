# DeepL-oFM for iPhone

A native SwiftUI iPhone app that uses the same translation core as the macOS
app: the same providers, prompts, Markdown preservation and nine interface
languages.

## Build and run

Requirements: Xcode 16 or newer, iOS 17 or newer, and an Apple ID for signing.

```bash
cd ios
xcodegen generate
open DeepL-oFM.xcodeproj
```

Select the **DeepL-oFM** target, choose your team under *Signing &
Capabilities*, pick an iPhone or a simulator, and press Run.

A simulator build can be verified without signing:

```bash
xcodebuild -project DeepL-oFM.xcodeproj -scheme DeepL-oFM \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Providers

- **Groq, OpenRouter, Cerebras, Ollama Cloud** work over HTTPS with your own API
  key, stored in the iOS Keychain.
- **Custom** accepts a Mac on the same Wi-Fi network (for example
  `http://192.168.1.10:11434`). The app allows local networking, and macOS will
  ask for Local Network permission on first use.
- A local `127.0.0.1` server is the phone itself, so it is not offered.

## App Store

The target builds and runs, but publishing requires:

1. An Apple Developer Program membership.
2. An App Store Connect record for `ua.admin.hymt.ios`.
3. An Apple Distribution certificate and a provisioning profile (Xcode can
   create them from your account).
4. A privacy policy and App Privacy answers: text is sent only to the provider
   you choose; API keys stay in the Keychain.
5. Screenshots, an app icon and App Review.

Without App Store Connect access the app can still be installed on a registered
iPhone through Xcode (a paid team signs for one year; a free Apple ID for seven
days).
