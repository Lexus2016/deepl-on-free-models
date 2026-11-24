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

## Use DeepL-oFM as the default translator

On iOS 18.4 or later, set up your provider in DeepL-oFM, then go to
**Settings → Apps → Default Apps → Translation** and choose **DeepL-oFM**.
Select text in an app such as Notes or Safari and choose **Translate**. The
translation sheet uses your configured provider and sends the selected text
when you tap **Translate** in the sheet. If iOS asks whether to pass the selected
text to DeepL-oFM, tap **Continue** to open the sheet. You can copy the result
or replace the original selection when the other app supports replacement.

## Translate text from the share sheet

Open DeepL-oFM once and configure your translation provider. In another app,
select or open a text message, choose **Share**, then tap **Translate with
DeepL-oFM** in the system actions. Scroll the actions if needed. Check the text
and target language, tap **Translate now**, then **Copy** or **Done**. The share
sheet sends text to your configured provider only when you tap **Translate now**.

In WhatsApp this works when the message offers the iOS **Share** sheet with
text. WhatsApp’s **Forward** action sends messages within WhatsApp. If the
message only offers **Copy**, use that and paste into DeepL-oFM.

## Build for the simulator

Use Xcode 16.3 or later. The main app requires iOS 17 or later and the system
extension requires iOS 18.4 or later.

```bash
cd ios
open DeepL-oFM.xcodeproj
```

Select **DeepL-oFM** and an iPhone simulator. Run `xcodegen generate` from
`ios/` after changing `project.yml`.

```bash
xcodebuild -project DeepL-oFM.xcodeproj -scheme DeepL-oFM \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Install on a physical iPhone

1. Connect and unlock the iPhone. If iOS asks whether to trust this Mac,
   confirm on the phone. Enable **Settings → Privacy & Security → Developer Mode**
   and confirm it after restarting the phone.
2. On the Mac, sign in under **Xcode → Settings → Apple Accounts** with an
   account that belongs to the Apple Developer team for this project.
3. Open `ios/DeepL-oFM.xcodeproj`. Under **Signing & Capabilities**, select the
   same team and enable **Automatically manage signing** for all three targets.
   Use `ua.admin.hymt.ios` for `DeepL-oFM`,
   `ua.admin.hymt.ios.translation-provider` for `TranslationProvider`, and
   `ua.admin.hymt.ios.share-translation` for `ShareTranslation`. The main app
   needs the **Translation** capability. All three targets use **Keychain
   Sharing** with group `ua.admin.hymt.ios.translation` under the same team prefix.
4. Choose the **DeepL-oFM** scheme and the connected iPhone in Xcode. Press
   **Run** (`⌘R`) and register the device if Xcode asks. After the app opens,
   configure a provider and try [the system translation flow](#use-deepl-ofm-as-the-default-translator).

For `No Accounts` or `No profiles`, check the Apple account and team in Xcode.
If signed keychain groups differ between targets, check that their profiles
use the same App ID prefix.
[Apple’s device setup guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) · [Keychain Sharing](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing)

## TestFlight and App Store

1. **Prepare the Apple account.** Use an active Apple Developer Program team.
   Register the main app and both extension identifiers with the capabilities above.
   In App Store Connect, create one iOS app record using `ua.admin.hymt.ios`.
   Both extensions are included in that app. [Create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
2. **Clear the release requirements.** Use a public name and icon you are
   authorized to publish. For the name **DeepL-oFM**, obtain permission to use
   the DeepL name or choose a distinct public name before submission. In both
   the main app and the system translation sheet, disclose which provider
   receives the text and obtain explicit permission before sending personal
   data to a third party, including an AI service. Complete App Privacy answers
   based on the app and providers’ actual data handling. [App Review Guidelines §§ 4.1, 5.1.2, 5.2](https://developer.apple.com/app-store/review/guidelines/) · [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
3. **Upload a signed build.** Set matching version and build numbers for the app
   and both extensions in `ios/project.yml`, regenerate the project, and increment the
   build number for each new upload. In Xcode, select **Any iOS Device** and
   run **Product → Archive**. In Organizer, use **Distribute App → App Store
   Connect → Upload**. Build with an SDK Apple currently accepts.
   [Upload requirements](https://developer.apple.com/news/upcoming-requirements/) · [Distribution in Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
4. **Test the uploaded build.** Use internal TestFlight testing to verify
   installation on an iPhone, provider setup, and selecting DeepL-oFM as the
   default translator. Test translating, copying, and replacing selected text
   in another app. Test the **Share** action with text in Safari and WhatsApp.
   External testing requires Apple to review the first build.
   [TestFlight](https://developer.apple.com/testflight/)
5. **Submit for review.** Add the description, screenshots, age rating,
   support URL, privacy policy, and export compliance answers. Select the
   processed build and add review notes explaining how to test the default
   translation flow. Give Apple a working test provider reachable outside your
   local network and the access needed to translate. Submit for App Review.
   After approval, release manually if you selected manual release.
   [Project privacy policy](https://lexus2016.github.io/deepl-on-free-models/privacy.html) ·
   [Submit an app for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app-for-review/)

## Українською

### Встановлення на iPhone через Xcode

1. Під’єднайте й розблокуйте iPhone. Якщо телефон попросить довіряти Mac,
   підтвердьте. Увімкніть **Параметри → Приватність і безпека → Режим розробника**
   та підтвердьте його після перезапуску телефона.
2. На Mac відкрийте **Xcode → Settings → Apple Accounts** і увійдіть у
   свій обліковий запис Apple Developer. Відкрийте `ios/DeepL-oFM.xcodeproj`.
3. У розділі **Signing & Capabilities** виберіть ту саму команду для
   `DeepL-oFM`, `TranslationProvider` і `ShareTranslation` та ввімкніть
   **Automatically manage signing**. Для основного застосунку потрібна
   можливість **Translation**. Усі три цілі
   використовують **Keychain Sharing** із групою `ua.admin.hymt.ios.translation`
   та однаковим префіксом команди.
4. У верхній панелі Xcode виберіть схему **DeepL-oFM** і підключений iPhone.
   Натисніть **Run** (`⌘R`). Якщо Xcode запропонує зареєструвати iPhone,
   підтвердьте. За помилок `No Accounts` чи `No profiles` перевірте обліковий
   запис і команду в Xcode. Якщо підписані групи Keychain різняться, перевірте,
   чи обидва профілі мають однаковий префікс ідентифікатора.
5. У DeepL-oFM налаштуйте провайдера й модель. На iOS 18.4 або новішій
   відкрийте **Параметри → Програми → Типові програми → Переклад → DeepL-oFM**.
   Виділіть текст у Safari або «Нотатках» і виберіть **Перекласти**. Якщо iOS
   запитає, чи передати виділений текст до DeepL-oFM, натисніть **Продовжити**.

### Переклад із меню «Поділитися»

Спочатку відкрийте DeepL-oFM і налаштуйте сервіс перекладу. В іншій програмі
виділіть текст або відкрийте меню повідомлення, виберіть **Поділитися**, а потім
**Перекласти в DeepL-oFM** у списку системних дій. За потреби прокрутіть список.
Перевірте текст і мову перекладу, натисніть **Перекласти зараз**. Результат можна
скопіювати й повернутися до попередньої програми. Текст надсилається до сервісу
лише після натискання кнопки перекладу.

У WhatsApp цей сценарій доступний для повідомлень, текст яких програма передає
через системне меню «Поділитися». «Переслати» всередині WhatsApp працює з чатами
WhatsApp. Якщо для повідомлення доступне лише копіювання, вставте текст у
DeepL-oFM.

### Публікація в App Store

1. **Обліковий запис і підпис.** Підготуйте активне членство в Apple Developer
   Program. Зареєструйте три ідентифікатори й можливості з інструкції вище.
   В App Store Connect створіть один запис iOS-застосунку для `ua.admin.hymt.ios`.
2. **Назва і приватність.** Для публікації під назвою **DeepL-oFM** отримайте
   дозвіл на використання назви DeepL або виберіть власну назву. У застосунку
   й системному вікні перекладу поясніть, якому провайдеру передається текст,
   і отримайте явну згоду перед передаванням персональних даних сторонньому
   сервісу, зокрема сервісу ШІ. Відповіді в розділі App Privacy мають
   відповідати фактичній обробці даних.
3. **Архів і завантаження.** У `ios/project.yml` узгодьте версію та номер
   збірки між застосунком і двома розширеннями. Підвищуйте номер для кожного нового
   завантаження. Згенеруйте проєкт заново, виберіть **Any iOS Device** і
   виконайте **Product → Archive**. В Organizer виберіть **Distribute App →
   App Store Connect → Upload**. Використовуйте версію Xcode та набір засобів
   розробки iOS, які зараз приймає Apple.
4. **TestFlight.** Встановіть завантажену збірку на реальний iPhone. Перевірте
   налаштування провайдера, вибір типового перекладача, переклад, копіювання
   та заміну виділеного тексту. Перевірте дію «Поділитися» з текстом у Safari
   та WhatsApp. Для зовнішніх тестувальників першу збірку
   перевіряє Apple.
5. **Перевірка і публікація.** Заповніть опис, знімки екрана, віковий рейтинг,
   адресу підтримки, політику приватності й відомості про шифрування. Додайте
   збірку та в примітках для Apple поясніть, як перевірити системний переклад.
   Надайте тестового провайдера, доступного поза вашою локальною мережею,
   і дані для входу, якщо вони потрібні для перекладу. Надішліть застосунок
   на перевірку.
   Якщо обрали ручну публікацію, опублікуйте після схвалення.

## UI tests

Run the shared scheme on an iPhone simulator to check Settings. To also test
translation and cancellation, set `DEEPL_TEST_SERVER` to a local
OpenAI-compatible fixture. The fixture should accept model `test`, translate
`Bonjour.` as `Good morning.`, and wait several seconds before translating
`Attendez.` as `Please wait.`.
