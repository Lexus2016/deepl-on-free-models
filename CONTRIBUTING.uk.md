# Участь у розробці

[English](CONTRIBUTING.md) · **Українська** · [Русский](CONTRIBUTING.ru.md)

Дякуємо, що допомагаєте DeepL-oFM. Зміни мають бути невеликими, перевіреними
й задокументованими трьома мовами.

## Збірка та тести

Потрібні macOS 14+, Xcode Command Line Tools і Ollama для локальних моделей.

```bash
swift test
./build.sh
open build/DeepL-oFM.app
```

`./setup.sh` завантажує типову модель Hy-MT2, робить тестовий переклад і збирає
застосунок. `./build.sh` вбудовує й підписує Sparkle, тому для бандла завжди
використовуйте його, а не голий `swift build`.

## Код

- Swift 5.9+, SwiftUI, macOS 14+.
- Усі рядки інтерфейсу — у `Sources/HyMT/Support/Localization.swift`; не
  вписуйте англійський текст у UI напряму.
- Ключі провайдерів — лише в Keychain
  (`Sources/HyMT/Support/Keychain.swift`). Ніколи не пишіть їх у UserDefaults,
  логи, історію чи репозиторій.
- Зберігайте шари: `Models/` — дані, `Services/` — мережа та історія,
  `Views/` — інтерфейс, `Support/` — допоміжні засоби.
- Додавайте регресійний тест на кожне виправлення, якщо поведінку можна
  перевірити без живої моделі.

## Документація та скріншоти

- `README.md` — канонічний; `README.uk.md` і `README.ru.md` — його переклади.
  Тримайте однакові розділи, числа й твердження в усіх трьох.
- Скріншоти — у `docs/screenshots/{en,uk,ru}/` і лише з реального застосунку
  відповідною мовою: `translation.png`, `settings.png`, `updates.png`.
- `SECURITY.md` і `CONTRIBUTING.md` також мають файли `.uk.md` і `.ru.md`.
- Пишіть простою мовою. Не додавайте маркетингових тверджень, яких не
  підтверджує код.

## Pull request

- Одна сфокусована зміна на PR; опишіть видимий для користувача ефект.
- Запустіть `swift test` і `./build.sh`.
- Оновіть changelog для релізу, а README/скріншоти — якщо змінився UI.
- Перед пушем перевірте staged-файли на секрети, локальні шляхи та e-mail:

  ```bash
  git diff --cached --name-only
  git grep -nE "(api[_-]?key|token|secret)\s*[:=]\s*['\"][A-Za-z0-9_-]{16,}"
  ```

- Не комітьте `.env`, `*.key`, `*.pem`, моделі, build-артефакти чи локальні
  шляхи.

## Релізи

Реліз — це тег **і** GitHub Release з файлами, а не лише тег:

1. Підніміть `CFBundleShortVersionString` і `CFBundleVersion` у
   `Resources/Info.plist`; додайте запис у `CHANGELOG.md`.
2. Запустіть тести й `./build.sh`; закомітьте та запуште.
3. Зберіть, підпишіть і нотарізуйте DMG із ярликом `Applications`, зробіть
   staple і перевірте через `spctl`.
4. Згенеруйте й підпишіть EdDSA `appcast.xml` інструментами Sparkle
   `generate_appcast`/`sign_update`.
5. `gh release create` з DMG, ZIP і `appcast.xml`; перевірте живий канал і
   реальне оновлення.

## Ліцензія

Долучаючись, ви погоджуєтеся, що ваш внесок ліцензується за MIT з
[LICENSE](LICENSE).
