# Platform parity / Узгодженість платформ

DeepL-oFM uses the same product flows on desktop and mobile. Native menus, permissions and distribution follow the operating system. Linux is a later target.

DeepL-oFM використовує однакові сценарії на комп’ютерах і мобільних пристроях. Системні меню, дозволи та поширення відповідають можливостям ОС. Linux заплановано на наступний етап.

| Flow / Сценарій | macOS | Windows | iPhone / iPad |
| --- | --- | --- | --- |
| Text / Текст | Swift translation, Markdown, language swap / Переклад, Markdown, обмін мов | Rust translation, Markdown, language swap / Переклад, Markdown, обмін мов | Shared Swift translation and mobile controls / Спільний переклад Swift і мобільні елементи керування |
| Documents / Документи | Select a file, choose languages, translate, save / Вибір файла й мов, переклад, збереження | The same sequence, with PDF and DOCX notices / Та сама послідовність і повідомлення щодо PDF та DOCX | File import, translation and export still need implementation / Імпорт, переклад і експорт ще потрібно реалізувати |
| Writing / Редагування | Write tab / Вкладка редагування | Write tab / Вкладка редагування | Shared writing service, with copy and share / Спільна служба редагування, копіювання й поширення |
| History / Історія | Local history with search and removal / Локальна історія з пошуком і видаленням | Local history with search and removal / Локальна історія з пошуком і видаленням | Shared Swift storage and search, copy, remove / Спільне сховище Swift, пошук, копіювання, видалення |
| Selected text / Виділений текст | System Services action and hotkey / Системна служба й комбінація клавіш | System-wide keyboard shortcut in compatible apps / Глобальна комбінація клавіш у сумісних програмах | Share action for text on iOS 17+, plus default Translate on iOS 18.4+ / Дія «Поділитися» для тексту з iOS 17 і типовий переклад з iOS 18.4 |
| Updates / Оновлення | Sparkle, daily checks, opt-in install / Sparkle, щоденні перевірки, встановлення за згодою | Tauri and signed installer, daily checks, opt-in install / Tauri й підписаний інсталятор, щоденні перевірки, встановлення за згодою | App Store or TestFlight / App Store або TestFlight |
| Support / Підтримка | About links to Buy Me a Coffee / Посилання в розділі «Про програму» | Same About link / Те саме посилання в розділі «Про програму» | Same About link / Те саме посилання в розділі «Про програму» |

## Next parity checks / Наступні перевірки узгодженості

- Align provider setup and fallback behavior, one-request translation, searchable language choices, file format warnings and keyboard behavior across desktop. Check equivalent actions on iPhone and iPad in their native layouts.
- Узгодити налаштування сервісів і резервування, переклад одним запитом, пошук мов, попередження про формати файлів та керування клавішами на комп’ютері. Перевірити відповідні дії на iPhone та iPad з урахуванням мобільного інтерфейсу.
- Verify the macOS Services action in Safari and other apps that expose Services. Windows browser context menu support requires a browser extension and a tested handoff of the selection.
- Перевірити службу macOS у Safari та інших програмах із підтримкою «Служб». Для меню браузера Windows потрібні розширення і перевірене передавання виділеного тексту.
- Verify Windows release signing and the installed upgrade from one version to the next. For iPhone and iPad, verify the App Store or TestFlight build and system translation on a physical device.
- Перевірити цифровий підпис випуску Windows і оновлення встановленої програми. Для iPhone та iPad перевірити збірку App Store або TestFlight і системний переклад на фізичному пристрої.
