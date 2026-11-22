import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case uk
    case ru
    case en

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system: return AppLanguage.systemResolved.localeIdentifier
        case .uk: return "uk_UA"
        case .ru: return "ru_RU"
        case .en: return "en_US"
        }
    }

    var resolved: AppLanguage {
        self == .system ? AppLanguage.systemResolved : self
    }

    static var systemResolved: AppLanguage {
        let code = Locale.preferredLanguages.first?
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? "en"
        switch code {
        case "uk": return .uk
        case "ru": return .ru
        case "en": return .en
        default: return .en
        }
    }

    func pickerTitle(current: AppLanguage) -> String {
        switch self {
        case .system: return L10n.t("System", current)
        case .uk: return "Українська"
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

/// Small runtime dictionary instead of .strings bundles: the interface language
/// can change without relaunching, and the app is built as a single binary.
enum L10n {

    static func t(_ key: String, _ language: AppLanguage) -> String {
        switch language.resolved {
        case .uk: return ukrainian[key] ?? key
        case .ru: return russian[key] ?? key
        default: return key
        }
    }

    static func format(_ key: String, _ language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: t(key, language), arguments: arguments)
    }

    static func characters(_ count: Int, _ language: AppLanguage) -> String {
        switch language.resolved {
        case .uk:
            let word = (count % 10 == 1 && count % 100 != 11) ? "символ" : "символів"
            return "\(count) \(word)"
        case .ru:
            let word = (count % 10 == 1 && count % 100 != 11) ? "символ" : "символов"
            return "\(count) \(word)"
        default:
            return "\(count) " + (count == 1 ? "character" : "characters")
        }
    }

    static func seconds(_ value: Double, _ language: AppLanguage) -> String {
        let formatted = String(format: "%.1f", value)
        return language.resolved == .en ? "\(formatted) s" : "\(formatted) с"
    }

    static func speed(_ value: Double, _ language: AppLanguage) -> String {
        let formatted = String(format: "%.0f", value)
        return language.resolved == .en ? "\(formatted) tok/s" : "\(formatted) т/с"
    }

    // MARK: - Tables

    private static let ukrainian: [String: String] = [
        // Core
        "Translate text": "Перекласти текст",
        "History": "Історія",
        "Settings": "Налаштування",
        "Translation": "Переклад",
        "Translate now": "Перекласти зараз",
        "Translate clipboard": "Перекласти буфер обміну",
        "Swap languages": "Обміняти мови",
        "Copy translation": "Скопіювати переклад",
        "Copy translation (Markdown + formatting)": "Скопіювати переклад (Markdown + форматування)",
        "Copy": "Копіювати",
        "Settings…": "Налаштування…",
        "Connection status": "Стан підключення",
        "Check connection": "Перевірити з'єднання",
        "Open HyMT": "Відкрити HyMT",
        "Quit": "Вийти",
        "Translate clipboard (%@)": "Перекласти буфер обміну (%@)",

        // Languages, styles, tones
        "Auto-detect": "Автовизначення",
        "Style": "Стиль",
        "Tone": "Тон",
        "Auto": "Авто",
        "Literal": "Дослівний",
        "Natural": "Природний",
        "Default": "За замовчуванням",
        "Formal": "Офіційний",
        "Casual": "Розмовний",
        "The model picks a natural style": "Модель сама обирає природний стиль",
        "Word for word, without free paraphrase": "Точно за словами, без вільного перефразування",
        "Conveys meaning rather than wording": "Передає смисл, а не окремі слова",
        "No extra tone": "Без додаткового тону",
        "Formal and professional": "Формальний, професійний",
        "Casual and conversational": "Невимушений, розмовний",

        // Translate pane
        "Enter or paste text…": "Введіть або вставте текст…",
        "Translation will appear here": "Тут з'явиться переклад",
        "Translating…": "Перекладаю…",
        "Translating… %d of %d": "Перекладаю… %d з %d",
        "Retry": "Повторити",
        "Clear": "Очистити",
        "Listen to the original": "Прослухати оригінал",
        "Copy the original": "Скопіювати оригінал",
        "Listen to the translation": "Прослухати переклад",
        "Translate again": "Перекласти ще раз",
        "Swap languages (⇧⌘S)": "Обміняти мови (⇧⌘S)",

        // Status and hot key
        "Checking connection…": "Перевіряю з'єднання…",
        "Server unavailable": "Сервер недоступний",
        "Model “%@” not found": "Модель «%@» не знайдена",
        "Not checked yet": "Ще не перевірено",
        "Connection works. Model “%@” is available.": "З'єднання працює. Модель «%@» доступна.",
        "Server responds, but model “%@” is missing. Available: %@.": "Сервер відповідає, але моделі «%@» немає. Доступні: %@.",
        "Connection works.": "З'єднання працює.",
        "%@ — translate clipboard": "%@ — перекласти буфер",
        "%@ — active": "%@ — активна",
        "Could not register %@. The shortcut may be taken.": "Не вдалося зареєструвати %@. Можливо, комбінація вже зайнята.",
        "Press a combination…": "Натисніть комбінацію…",
        "Reset": "Скинути",
        "At least one modifier is required — ⌘, ⌥ or ⌃. Press Esc to cancel.": "Потрібен щонайменше один модифікатор — ⌘, ⌥ або ⌃. Натисніть Esc, щоб скасувати.",
        "Hot key": "Гаряча клавіша",
        "Copy text anywhere and press the shortcut — HyMT opens and translates the clipboard.": "Скопіюйте текст у будь-якому застосунку та натисніть комбінацію — HyMT відкриється й одразу перекладе вміст буфера обміну.",
        "Select text in any app and press the shortcut — HyMT copies it and translates.": "Виділіть текст у будь-якому застосунку та натисніть комбінацію — HyMT скопіює його й перекладе.",
        "Translate selection": "Перекласти виділене",
        "Translate selection (%@)": "Перекласти виділене (%@)",
        "Selected text": "Виділений текст",
        "Accessibility access": "Доступ до Accessibility",
        "Granted": "Надано",
        "Not granted": "Не надано",
        "Open System Settings": "Відкрити системні налаштування",
        "Check access": "Перевірити доступ",
        "Delete": "Видалити",
        "Forward Delete": "Видалити вперед",
        "Examples: ⌥⌘T or ⌥⌘C.": "Наприклад: ⌥⌘T або ⌥⌘C.",
        "If access is already granted, remove HyMT from the Accessibility list and add the current app again — a permission from an older build does not apply.": "Якщо доступ уже надано, видаліть HyMT зі списку Accessibility і додайте поточний застосунок знову — дозвіл від старої збірки не діє.",
        "Accessibility access is required to copy the selected text.": "Для копіювання виділеного тексту потрібен доступ до Accessibility.",
        "Could not copy the selected text. Check Accessibility access.": "Не вдалося скопіювати виділений текст. Перевірте доступ до Accessibility.",
        "Space": "Пробіл",
        "key %d": "клавіша %d",
        "Can be empty for local servers. Stored in the macOS Keychain, never in the repository.": "Може бути порожнім для локального сервера. Ключ зберігається в Keychain macOS і ніколи не потрапляє в репозиторій.",
        "HyMT — local translation": "HyMT — локальний переклад",
        "Other": "Інший",
        "Ollama Cloud through a direct API key. No local server is needed.": "Ollama Cloud через прямий API-ключ. Локальний сервер не потрібен.",
        "Connect": "Під'єднатися",
        "Models on the server": "Моделі на сервері",
        "Filter by name": "Фільтр за назвою",
        "Refresh": "Оновити",
        "The server returned no models.": "Сервер не повернув жодної моделі.",
        "Select a model from the list or type its ID.": "Оберіть модель зі списку або введіть її ідентифікатор.",
        "Models: %d": "Моделей: %d",
        "Cloud": "Хмара",
        "Gemma 4 in Ollama Cloud. Fast and strong for general translation.": "Gemma 4 в Ollama Cloud. Швидка й сильна для загального перекладу.",
        "A fast cloud model from DeepSeek with a large context.": "Швидка хмарна модель DeepSeek із великим контекстом.",
        "Mistral's general-purpose model in Ollama Cloud.": "Універсальна модель Mistral в Ollama Cloud.",
        "NVIDIA's high-throughput model for difficult texts.": "Високопродуктивна модель NVIDIA для складних текстів.",

        // Settings
        "Model and provider": "Модель і провайдер",
        "Local models run offline and for free. Cloud models answer faster but need a key.": "Локальні моделі працюють офлайн і безкоштовно. Хмарні відповідають швидше, але потребують ключа.",
        "API key": "Ключ API",
        "Get key ↗": "Отримати ключ ↗",
        "Server address": "Адреса сервера",
        "Model": "Модель",
        "Model catalog…": "Каталог моделей…",
        "Generation parameters": "Параметри генерації",
        "Defaults match Tencent’s recommendations for Hy-MT2 7B.": "Значення за замовчуванням відповідають рекомендаціям Tencent для Hy-MT2 7B.",
        "Temperature": "Температура",
        "Repetition": "Повторення",
        "Only this many most likely tokens are considered while decoding.": "Під час декодування розглядається стільки найімовірніших токенів.",
        "Context": "Контекст",
        "Behavior": "Поведінка",
        "Translate automatically while typing": "Перекладати автоматично під час введення",
        "Delay": "Затримка",
        "Keep translation history": "Зберігати історію перекладів",
        "Menu bar icon": "Іконка в меню-барі",
        "Interface language": "Мова інтерфейсу",
        "System": "Системна",
        "System prompt": "Системний промпт",
        "Hy-MT2 has no system prompt: instruction and text go in one message. Wording follows the model card.": "Hy-MT2 не має системного промпту: інструкція та текст ідуть одним повідомленням. Формулювання збігаються з карткою моделі.",
        "About": "Про програму",
        "local translator for macOS": "локальний перекладач для macOS",
        "Model: Hy-MT2 7B (Tencent Hy). License and model card on Hugging Face.": "Модель: Hy-MT2 7B (Tencent Hy). Ліцензія та картка моделі — на Hugging Face.",
        "Project repository": "Репозиторій проєкту",
        "HyMT on GitHub": "HyMT на GitHub",

        // Providers
        "Local Ollama server. The model must be pulled with ollama pull.": "Локальний сервер Ollama. Модель має бути завантажена командою ollama pull.",
        "LM Studio with its local server enabled. The model ID is shown in LM Studio.": "LM Studio з увімкненим локальним сервером. Ідентифікатор моделі видно в LM Studio.",
        "oMLX — an MLX server for Apple Silicon. Enable the OpenAI-compatible API.": "oMLX — MLX-сервер для Apple Silicon. Увімкніть OpenAI-сумісний API.",
        "llama-server with --api. The default address is port 8080.": "llama-server з прапорцем --api. Адреса за замовчуванням — порт 8080.",
        "Hundreds of models with one key. Free models are marked :free.": "Сотні моделей через один ключ. Є безкоштовні моделі з позначкою :free.",
        "Very fast cloud. Has a free tier with request limits.": "Дуже швидка хмара. Є безкоштовний тариф із лімітами на кількість запитів.",
        "Fastest inference for open models. Has a free tier with limits.": "Найшвидший inference для відкритих моделей. Є безкоштовний тариф із лімітами.",
        "Any OpenAI-compatible server: your proxy, vLLM, LocalAI, Together, and so on.": "Будь-який OpenAI-сумісний сервер: свій проксі, vLLM, LocalAI, Together тощо.",

        // Catalog
        "Model catalog": "Каталог моделей",
        "Ready translators for local use and cloud options with free tiers.": "Готові перекладачі для локального запуску й хмарні варіанти з безкоштовними тарифами.",
        "Search model": "Пошук моделі",
        "Free only": "Лише безкоштовні",
        "Fetch from server": "Отримати з сервера",
        "Nothing found": "Нічого не знайдено",
        "Found on the server": "Знайдені на сервері",
        "Recommended": "Рекомендовані",
        "Models": "Моделі",
        "Need another model? Type its ID into the Model field — any model your server supports will work.": "Інша модель? Введіть її ідентифікатор у полі «Модель» — підійде будь-яка модель, яку підтримує ваш сервер.",
        "Choose": "Обрати",
        "Copy install command": "Скопіювати команду встановлення",
        "Enter the API key for %@ in Settings first.": "Спочатку введіть ключ API для %@ у налаштуваннях.",

        // History
        "Search in history": "Пошук в історії",
        "Search language": "Пошук мови",
        "Clear history?": "Очистити історію?",
        "Cancel": "Скасувати",
        "All saved translations will be deleted permanently.": "Усі збережені переклади буде видалено без можливості відновлення.",
        "History is empty": "Історія порожня",
        "Translations will be saved here automatically.": "Переклади зберігатимуться тут автоматично.",
        "Try another query.": "Спробуйте інший запит.",
        "Delete entry": "Видалити запис",

        // Errors
        "Invalid server URL: %@": "Некоректна адреса сервера: %@",
        "No model name in settings.": "Не вказано назву моделі в налаштуваннях.",
        "Could not connect to %@. Check that the server is running.": "Не вдалося підключитися до %@. Перевірте, чи запущений сервер.",
        "Server returned error %@.": "Сервер повернув помилку %@.",
        "Server returned error %@: %@": "Сервер повернув помилку %@: %@",
        "Model “%@” not found on the server.": "Модель «%@» не знайдена на сервері.",
        "The model returned an empty translation. Try again.": "Модель повернула порожній переклад. Спробуйте ще раз.",
        "The model could not produce a stable translation. Try again or switch the style/model.": "Модель не змогла стабільно перекласти фрагмент. Спробуйте ще раз або змініть стиль/модель.",
        "Some lines could not be translated (%d); they are left in the source language.": "Деякі рядки не вдалося перекласти (%d); їх залишено мовою оригіналу.",
        "Server returned an unexpected response.": "Сервер повернув неочікувану відповідь.",

        // Catalog entries
        "Tencent's specialised translation model. The default for this app.": "Спеціалізована модель перекладу Tencent. Базова для застосунку.",
        "The same model in a lighter size: fast even on weaker Macs.": "Легка версія тієї ж моделі: швидко працює навіть на слабких Mac.",
        "The highest-quality MoE version. Needs a lot of memory.": "MoE-версія найвищої якості. Потребує багато пам'яті.",
        "Google's translation model built on Gemma 3.": "Перекладацька модель Google на базі Gemma 3.",
        "A larger TranslateGemma for stronger machines.": "Якісніша версія TranslateGemma для сильніших машин.",
        "A compact model tuned only to translate — no explanations or reasoning.": "Компактна модель, донавчена лише перекладати — без пояснень і міркувань.",
        "Cohere's multilingual model with a good speed-quality balance.": "Багатомовна модель Cohere з добрим балансом швидкості та якості.",
        "A general model; translates well but may add explanations.": "Універсальна модель; добре перекладає, але може додавати пояснення.",
        "The same translation model in the cloud. Very cheap, no download.": "Та сама перекладацька модель у хмарі. Дуже дешева, без завантаження.",
        "The cheapest Hy-MT2 option on OpenRouter.": "Найдешевший варіант Hy-MT2 через OpenRouter.",
        "The highest-quality Hy-MT2 version on OpenRouter.": "Найякісніша версія Hy-MT2 через OpenRouter.",
        "Google's free model with a large context. Good general translation.": "Безкоштовна модель Google з великим контекстом. Гарний загальний переклад.",
        "A free MoE version of Gemma 4: faster than 31B.": "Безкоштовна MoE-версія Gemma 4: швидша за 31B.",
        "A large free NVIDIA model for difficult texts.": "Велика безкоштовна модель NVIDIA для складних текстів.",
        "A free fast model with a 1M-token context.": "Безкоштовна швидка модель із контекстом 1M токенів.",
        "Cheap and very fast general translation from Google.": "Дешевий і дуже швидкий загальний переклад від Google.",
        "The cheapest fast Qwen model for bulk translation.": "Найдешевша швидка модель Qwen для масових перекладів.",
        "Reliable general translation from OpenAI.": "Надійний загальний переклад від OpenAI.",
        "OpenAI's flagship open model on Groq's fast inference.": "Флагманська відкрита модель OpenAI на швидкому inference Groq.",
        "The fastest option for short texts.": "Найшвидший варіант для коротких текстів.",
        "Meta's proven general-purpose model.": "Перевірена універсальна модель Meta.",
        "A fresh Qwen with strong translation; preview status.": "Свіжа Qwen із сильним перекладом; статус preview.",
        "Around 3000 tokens per second — the fastest option for long texts.": "Близько 3000 токенів за секунду — найшвидший варіант для довгих текстів.",
        "A fast Qwen with good multilingual translation.": "Швидка Qwen із добрим багатомовним перекладом.",

        // Badges
        "33 languages": "33 мови",
        "55 languages": "55 мов",
        "23 languages": "23 мови",
        "recommended": "рекомендовано",
        "light": "легка",
        "fast": "швидка",
        "large": "велика",
        "specialised": "спеціалізована",
        "cheap": "дешева",
        "cheapest": "найдешевша",
        "universal": "універсальна",
        "slower": "повільніша",
        "Free": "Безкоштовно",
        "Free tier": "Free-тариф",
        "preview": "preview",
        "MoE": "MoE",
        "translation": "переклад",
        "Local": "Локально",
        "≈4.6 GB": "≈4,6 ГБ",
        "≈3 GB": "≈3 ГБ",
        "≈8 GB": "≈8 ГБ",
        "~500 t/s": "~500 т/с",
        "~1000 t/s": "~1000 т/с",
        "~280 t/s": "~280 т/с",
        "~450 t/s": "~450 т/с",
        "~3000 t/s": "~3000 т/с",
        "~1850 t/s": "~1850 т/с"
    ]

    private static let russian: [String: String] = [
        // Core
        "Translate text": "Перевести текст",
        "History": "История",
        "Settings": "Настройки",
        "Translation": "Перевод",
        "Translate now": "Перевести сейчас",
        "Translate clipboard": "Перевести буфер обмена",
        "Swap languages": "Поменять языки",
        "Copy translation": "Скопировать перевод",
        "Copy translation (Markdown + formatting)": "Скопировать перевод (Markdown + форматирование)",
        "Copy": "Копировать",
        "Settings…": "Настройки…",
        "Connection status": "Состояние подключения",
        "Check connection": "Проверить соединение",
        "Open HyMT": "Открыть HyMT",
        "Quit": "Выйти",
        "Translate clipboard (%@)": "Перевести буфер обмена (%@)",

        // Languages, styles, tones
        "Auto-detect": "Автоопределение",
        "Style": "Стиль",
        "Tone": "Тон",
        "Auto": "Авто",
        "Literal": "Дословный",
        "Natural": "Естественный",
        "Default": "По умолчанию",
        "Formal": "Официальный",
        "Casual": "Разговорный",
        "The model picks a natural style": "Модель сама выбирает естественный стиль",
        "Word for word, without free paraphrase": "Точно по словам, без свободного перефразирования",
        "Conveys meaning rather than wording": "Передаёт смысл, а не отдельные слова",
        "No extra tone": "Без дополнительного тона",
        "Formal and professional": "Формальный, профессиональный",
        "Casual and conversational": "Непринуждённый, разговорный",

        // Translate pane
        "Enter or paste text…": "Введите или вставьте текст…",
        "Translation will appear here": "Здесь появится перевод",
        "Translating…": "Перевожу…",
        "Translating… %d of %d": "Перевожу… %d из %d",
        "Retry": "Повторить",
        "Clear": "Очистить",
        "Listen to the original": "Прослушать оригинал",
        "Copy the original": "Скопировать оригинал",
        "Listen to the translation": "Прослушать перевод",
        "Translate again": "Перевести ещё раз",
        "Swap languages (⇧⌘S)": "Поменять языки (⇧⌘S)",

        // Status and hot key
        "Checking connection…": "Проверяю соединение…",
        "Server unavailable": "Сервер недоступен",
        "Model “%@” not found": "Модель «%@» не найдена",
        "Not checked yet": "Ещё не проверено",
        "Connection works. Model “%@” is available.": "Соединение работает. Модель «%@» доступна.",
        "Server responds, but model “%@” is missing. Available: %@.": "Сервер отвечает, но модели «%@» нет. Доступны: %@.",
        "Connection works.": "Соединение работает.",
        "%@ — translate clipboard": "%@ — перевести буфер обмена",
        "%@ — active": "%@ — активна",
        "Could not register %@. The shortcut may be taken.": "Не удалось зарегистрировать %@. Возможно, комбинация уже занята.",
        "Press a combination…": "Нажмите комбинацию…",
        "Reset": "Сбросить",
        "At least one modifier is required — ⌘, ⌥ or ⌃. Press Esc to cancel.": "Нужен хотя бы один модификатор — ⌘, ⌥ или ⌃. Нажмите Esc, чтобы отменить.",
        "Hot key": "Горячая клавиша",
        "Copy text anywhere and press the shortcut — HyMT opens and translates the clipboard.": "Скопируйте текст в любом приложении и нажмите комбинацию — HyMT откроется и сразу переведёт содержимое буфера обмена.",
        "Select text in any app and press the shortcut — HyMT copies it and translates.": "Выделите текст в любом приложении и нажмите комбинацию — HyMT скопирует его и переведёт.",
        "Translate selection": "Перевести выделенное",
        "Translate selection (%@)": "Перевести выделенное (%@)",
        "Selected text": "Выделенный текст",
        "Accessibility access": "Доступ к Accessibility",
        "Granted": "Предоставлен",
        "Not granted": "Не предоставлен",
        "Open System Settings": "Открыть системные настройки",
        "Check access": "Проверить доступ",
        "Delete": "Удалить",
        "Forward Delete": "Удалить вперёд",
        "Examples: ⌥⌘T or ⌥⌘C.": "Например: ⌥⌘T или ⌥⌘C.",
        "If access is already granted, remove HyMT from the Accessibility list and add the current app again — a permission from an older build does not apply.": "Если доступ уже предоставлен, удалите HyMT из списка Accessibility и добавьте текущее приложение снова — разрешение от старой сборки не действует.",
        "Accessibility access is required to copy the selected text.": "Для копирования выделенного текста нужен доступ к Accessibility.",
        "Could not copy the selected text. Check Accessibility access.": "Не удалось скопировать выделенный текст. Проверьте доступ к Accessibility.",
        "Space": "Пробел",
        "key %d": "клавиша %d",
        "Can be empty for local servers. Stored in the macOS Keychain, never in the repository.": "Может быть пустым для локального сервера. Ключ хранится в Keychain macOS и никогда не попадает в репозиторий.",
        "HyMT — local translation": "HyMT — локальный перевод",
        "Other": "Другой",
        "Ollama Cloud through a direct API key. No local server is needed.": "Ollama Cloud через прямой API-ключ. Локальный сервер не нужен.",
        "Connect": "Подключиться",
        "Models on the server": "Модели на сервере",
        "Filter by name": "Фильтр по названию",
        "Refresh": "Обновить",
        "The server returned no models.": "Сервер не вернул ни одной модели.",
        "Select a model from the list or type its ID.": "Выберите модель из списка или введите её идентификатор.",
        "Models: %d": "Моделей: %d",
        "Cloud": "Облако",
        "Gemma 4 in Ollama Cloud. Fast and strong for general translation.": "Gemma 4 в Ollama Cloud. Быстрая и сильная для общего перевода.",
        "A fast cloud model from DeepSeek with a large context.": "Быстрая облачная модель DeepSeek с большим контекстом.",
        "Mistral's general-purpose model in Ollama Cloud.": "Универсальная модель Mistral в Ollama Cloud.",
        "NVIDIA's high-throughput model for difficult texts.": "Высокопроизводительная модель NVIDIA для сложных текстов.",

        // Settings
        "Model and provider": "Модель и провайдер",
        "Local models run offline and for free. Cloud models answer faster but need a key.": "Локальные модели работают офлайн и бесплатно. Облачные отвечают быстрее, но требуют ключа.",
        "API key": "Ключ API",
        "Get key ↗": "Получить ключ ↗",
        "Server address": "Адрес сервера",
        "Model": "Модель",
        "Model catalog…": "Каталог моделей…",
        "Generation parameters": "Параметры генерации",
        "Defaults match Tencent’s recommendations for Hy-MT2 7B.": "Значения по умолчанию соответствуют рекомендациям Tencent для Hy-MT2 7B.",
        "Temperature": "Температура",
        "Repetition": "Повторение",
        "Only this many most likely tokens are considered while decoding.": "При декодировании рассматривается столько самых вероятных токенов.",
        "Context": "Контекст",
        "Behavior": "Поведение",
        "Translate automatically while typing": "Переводить автоматически во время ввода",
        "Delay": "Задержка",
        "Keep translation history": "Сохранять историю переводов",
        "Menu bar icon": "Иконка в меню-баре",
        "Interface language": "Язык интерфейса",
        "System": "Системная",
        "System prompt": "Системный промпт",
        "Hy-MT2 has no system prompt: instruction and text go in one message. Wording follows the model card.": "У Hy-MT2 нет системного промпта: инструкция и текст идут одним сообщением. Формулировки совпадают с карточкой модели.",
        "About": "О программе",
        "local translator for macOS": "локальный переводчик для macOS",
        "Model: Hy-MT2 7B (Tencent Hy). License and model card on Hugging Face.": "Модель: Hy-MT2 7B (Tencent Hy). Лицензия и карточка модели — на Hugging Face.",
        "Project repository": "Репозиторий проекта",
        "HyMT on GitHub": "HyMT на GitHub",

        // Providers
        "Local Ollama server. The model must be pulled with ollama pull.": "Локальный сервер Ollama. Модель должна быть загружена командой ollama pull.",
        "LM Studio with its local server enabled. The model ID is shown in LM Studio.": "LM Studio с включённым локальным сервером. Идентификатор модели виден в LM Studio.",
        "oMLX — an MLX server for Apple Silicon. Enable the OpenAI-compatible API.": "oMLX — MLX-сервер для Apple Silicon. Включите OpenAI-совместимый API.",
        "llama-server with --api. The default address is port 8080.": "llama-server с флагом --api. Адрес по умолчанию — порт 8080.",
        "Hundreds of models with one key. Free models are marked :free.": "Сотни моделей через один ключ. Есть бесплатные модели с пометкой :free.",
        "Very fast cloud. Has a free tier with request limits.": "Очень быстрое облако. Есть бесплатный тариф с лимитами на количество запросов.",
        "Fastest inference for open models. Has a free tier with limits.": "Самый быстрый inference для открытых моделей. Есть бесплатный тариф с лимитами.",
        "Any OpenAI-compatible server: your proxy, vLLM, LocalAI, Together, and so on.": "Любой OpenAI-совместимый сервер: свой прокси, vLLM, LocalAI, Together и т. п.",

        // Catalog
        "Model catalog": "Каталог моделей",
        "Ready translators for local use and cloud options with free tiers.": "Готовые переводчики для локального запуска и облачные варианты с бесплатными тарифами.",
        "Search model": "Поиск модели",
        "Free only": "Только бесплатные",
        "Fetch from server": "Получить с сервера",
        "Nothing found": "Ничего не найдено",
        "Found on the server": "Найдены на сервере",
        "Recommended": "Рекомендуемые",
        "Models": "Модели",
        "Need another model? Type its ID into the Model field — any model your server supports will work.": "Нужна другая модель? Введите её идентификатор в поле «Модель» — подойдёт любая модель, которую поддерживает ваш сервер.",
        "Choose": "Выбрать",
        "Copy install command": "Скопировать команду установки",
        "Enter the API key for %@ in Settings first.": "Сначала введите ключ API для %@ в настройках.",

        // History
        "Search in history": "Поиск в истории",
        "Search language": "Поиск языка",
        "Clear history?": "Очистить историю?",
        "Cancel": "Отмена",
        "All saved translations will be deleted permanently.": "Все сохранённые переводы будут удалены без возможности восстановления.",
        "History is empty": "История пуста",
        "Translations will be saved here automatically.": "Переводы будут сохраняться здесь автоматически.",
        "Try another query.": "Попробуйте другой запрос.",
        "Delete entry": "Удалить запись",

        // Errors
        "Invalid server URL: %@": "Некорректный адрес сервера: %@",
        "No model name in settings.": "Не указано название модели в настройках.",
        "Could not connect to %@. Check that the server is running.": "Не удалось подключиться к %@. Проверьте, запущен ли сервер.",
        "Server returned error %@.": "Сервер вернул ошибку %@.",
        "Server returned error %@: %@": "Сервер вернул ошибку %@: %@",
        "Model “%@” not found on the server.": "Модель «%@» не найдена на сервере.",
        "The model returned an empty translation. Try again.": "Модель вернула пустой перевод. Попробуйте ещё раз.",
        "The model could not produce a stable translation. Try again or switch the style/model.": "Модель не смогла стабильно перевести фрагмент. Попробуйте ещё раз или смените стиль/модель.",
        "Some lines could not be translated (%d); they are left in the source language.": "Некоторые строки не удалось перевести (%d); они оставлены на языке оригинала.",
        "Server returned an unexpected response.": "Сервер вернул неожиданный ответ.",

        // Catalog entries
        "Tencent's specialised translation model. The default for this app.": "Специализированная модель перевода Tencent. Базовая для приложения.",
        "The same model in a lighter size: fast even on weaker Macs.": "Лёгкая версия той же модели: быстро работает даже на слабых Mac.",
        "The highest-quality MoE version. Needs a lot of memory.": "MoE-версия наивысшего качества. Требует много памяти.",
        "Google's translation model built on Gemma 3.": "Переводческая модель Google на базе Gemma 3.",
        "A larger TranslateGemma for stronger machines.": "Более качественная версия TranslateGemma для сильных машин.",
        "A compact model tuned only to translate — no explanations or reasoning.": "Компактная модель, дообученная только переводить — без пояснений и рассуждений.",
        "Cohere's multilingual model with a good speed-quality balance.": "Многоязычная модель Cohere с хорошим балансом скорости и качества.",
        "A general model; translates well but may add explanations.": "Универсальная модель; хорошо переводит, но может добавлять пояснения.",
        "The same translation model in the cloud. Very cheap, no download.": "Та же переводческая модель в облаке. Очень дешёвая, без загрузки.",
        "The cheapest Hy-MT2 option on OpenRouter.": "Самый дешёвый вариант Hy-MT2 через OpenRouter.",
        "The highest-quality Hy-MT2 version on OpenRouter.": "Самая качественная версия Hy-MT2 через OpenRouter.",
        "Google's free model with a large context. Good general translation.": "Бесплатная модель Google с большим контекстом. Хороший общий перевод.",
        "A free MoE version of Gemma 4: faster than 31B.": "Бесплатная MoE-версия Gemma 4: быстрее, чем 31B.",
        "A large free NVIDIA model for difficult texts.": "Большая бесплатная модель NVIDIA для сложных текстов.",
        "A free fast model with a 1M-token context.": "Бесплатная быстрая модель с контекстом 1M токенов.",
        "Cheap and very fast general translation from Google.": "Дешёвый и очень быстрый общий перевод от Google.",
        "The cheapest fast Qwen model for bulk translation.": "Самая дешёвая быстрая модель Qwen для массовых переводов.",
        "Reliable general translation from OpenAI.": "Надёжный общий перевод от OpenAI.",
        "OpenAI's flagship open model on Groq's fast inference.": "Флагманская открытая модель OpenAI на быстром inference Groq.",
        "The fastest option for short texts.": "Самый быстрый вариант для коротких текстов.",
        "Meta's proven general-purpose model.": "Проверенная универсальная модель Meta.",
        "A fresh Qwen with strong translation; preview status.": "Свежая Qwen с сильным переводом; статус preview.",
        "Around 3000 tokens per second — the fastest option for long texts.": "Около 3000 токенов в секунду — самый быстрый вариант для длинных текстов.",
        "A fast Qwen with good multilingual translation.": "Быстрая Qwen с хорошим многоязычным переводом.",

        // Badges
        "33 languages": "33 языка",
        "55 languages": "55 языков",
        "23 languages": "23 языка",
        "recommended": "рекомендуется",
        "light": "лёгкая",
        "fast": "быстрая",
        "large": "большая",
        "specialised": "специализированная",
        "cheap": "дешёвая",
        "cheapest": "самая дешёвая",
        "universal": "универсальная",
        "slower": "медленнее",
        "Free": "Бесплатно",
        "Free tier": "Free-тариф",
        "preview": "preview",
        "MoE": "MoE",
        "translation": "перевод",
        "Local": "Локально",
        "≈4.6 GB": "≈4,6 ГБ",
        "≈3 GB": "≈3 ГБ",
        "≈8 GB": "≈8 ГБ",
        "~500 t/s": "~500 т/с",
        "~1000 t/s": "~1000 т/с",
        "~280 t/s": "~280 т/с",
        "~450 t/s": "~450 т/с",
        "~3000 t/s": "~3000 т/с",
        "~1850 t/s": "~1850 т/с"
    ]
}
