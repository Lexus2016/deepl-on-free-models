# DeepL-oFM for iPhone

Translate text with a cloud provider or an OpenAI-compatible server on your
network. Read the result as formatted text, plain text or Markdown. You can
copy or share it from the result panel.

## Set up translation

1. Open **Settings** and choose your provider.
2. Enter its API key and the name of a model available on your account.
3. Return to the translator, paste or type text, and choose a target language.

To use a server that runs on your Mac, choose **Custom**. Enter the Mac’s
address and port, for example `http://mac.local:11434/v1`, and the model name.
Connect both devices to the same Wi-Fi network and allow Local Network access
when iOS asks. Addresses starting with `127.0.0.1` point to the iPhone itself.
Use HTTPS for a server outside your local network.

## Build and run

Use Xcode 16 or later. The app requires iOS 17 or later.

```bash
cd ios
xcodegen generate
open DeepL-oFM.xcodeproj
```

Select **DeepL-oFM** and an iPhone simulator. To run on a physical iPhone,
select your Apple developer team under **Signing & Capabilities** first.

```bash
xcodebuild -project DeepL-oFM.xcodeproj -scheme DeepL-oFM \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## App Store submission

The bundle identifier is `ua.admin.hymt.ios`. Use the App Store Connect record
and distribution profile that match it. Add the privacy policy and complete
Apple’s privacy questions before uploading a signed archive.

[Privacy policy](https://lexus2016.github.io/deepl-on-free-models/privacy.html)

## UI tests

Run the shared scheme on an iPhone simulator to check Settings. To also test
translation and cancellation, set `DEEPL_TEST_SERVER` to a local
OpenAI-compatible fixture. The fixture should accept model `test`, translate
`Bonjour.` as `Good morning.`, and wait several seconds before translating
`Attendez.` as `Please wait.`.
