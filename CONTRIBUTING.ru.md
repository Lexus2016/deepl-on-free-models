# Участие в разработке

[English](CONTRIBUTING.md) · [Українська](CONTRIBUTING.uk.md) · **Русский**

Спасибо, что помогаете DeepL-oFM. Изменения должны быть небольшими,
проверенными и задокументированными на трёх языках.

## Сборка и тесты

Нужны macOS 14+, Xcode Command Line Tools и Ollama для локальных моделей.

```bash
swift test
./build.sh
open build/DeepL-oFM.app
```

`./setup.sh` загружает модель Hy-MT2 по умолчанию, делает тестовый перевод и
собирает приложение. `./build.sh` встраивает и подписывает Sparkle, поэтому для
бандла всегда используйте его, а не голый `swift build`.

## Код

- Swift 5.9+, SwiftUI, macOS 14+.
- Все строки интерфейса — в `Sources/HyMT/Support/Localization.swift`; не
  вписывайте английский текст в UI напрямую.
- Ключи провайдеров — только в Keychain
  (`Sources/HyMT/Support/Keychain.swift`). Никогда не пишите их в UserDefaults,
  логи, историю или репозиторий.
- Сохраняйте слои: `Models/` — данные, `Services/` — сеть и история,
  `Views/` — интерфейс, `Support/` — вспомогательные средства.
- Добавляйте регрессионный тест на каждое исправление, если поведение можно
  проверить без живой модели.

## Документация и скриншоты

- `README.md` — канонический; `README.uk.md` и `README.ru.md` — его переводы.
  Держите одинаковые разделы, числа и утверждения во всех трёх.
- Скриншоты — в `docs/screenshots/{en,uk,ru}/` и только из реального
  приложения на соответствующем языке: `translation.png`, `settings.png`,
  `updates.png`.
- `SECURITY.md` и `CONTRIBUTING.md` также имеют файлы `.uk.md` и `.ru.md`.
- Пишите простым языком. Не добавляйте маркетинговых утверждений, которых нет
  в коде.

## Pull request

- Одно сфокусированное изменение на PR; опишите видимый пользователю эффект.
- Запустите `swift test` и `./build.sh`.
- Обновите changelog для релиза, а README/скриншоты — если изменился UI.
- Перед пушем проверьте staged-файлы на секреты, локальные пути и e-mail:

  ```bash
  git diff --cached --name-only
  git grep -nE "(api[_-]?key|token|secret)\s*[:=]\s*['\"][A-Za-z0-9_-]{16,}"
  ```

- Не коммитьте `.env`, `*.key`, `*.pem`, модели, build-артефакты или локальные
  пути.

## Релизы

Релиз — это тег **и** GitHub Release с файлами, а не только тег:

1. Поднимите `CFBundleShortVersionString` и `CFBundleVersion` в
   `Resources/Info.plist`; добавьте запись в `CHANGELOG.md`.
2. Запустите тесты и `./build.sh`; закоммитьте и запушьте.
3. Соберите, подпишите и нотаризуйте DMG с ярлыком `Applications`, сделайте
   staple и проверьте через `spctl`.
4. Сгенерируйте и подпишите EdDSA `appcast.xml` инструментами Sparkle
   `generate_appcast`/`sign_update`.
5. `gh release create` с DMG, ZIP и `appcast.xml`; проверьте живой канал и
   реальное обновление.

## Лицензия

Участвуя, вы соглашаетесь, что ваш вклад лицензируется по MIT из
[LICENSE](LICENSE).
