# DeepL-oFM for Windows / DeepL-oFM для Windows

The Windows application uses Rust and Tauri. It translates text and documents with local Ollama models or configured cloud providers. It includes a writing tool, a translation history, and shortcuts for translating the clipboard or a text selection.

Версія для Windows використовує Rust і Tauri. Вона перекладає текст і документи через локальні моделі Ollama або налаштовані хмарні сервіси. У програмі є редактор тексту, історія перекладів і комбінації клавіш для перекладу вмісту буфера обміну або виділеного тексту.

## Install and test / Встановлення й перевірка

- Use the x64 test installer from the [Windows Rust workflow](https://github.com/Lexus2016/deepl-on-free-models/actions/workflows/rust.yml). It uses Microsoft WebView2. See [build and signing instructions](packaging/README.md).
- Завантажте тестовий інсталятор x64 із [перевірок Windows Rust](https://github.com/Lexus2016/deepl-on-free-models/actions/workflows/rust.yml). Програма використовує Microsoft WebView2. Дивіться [інструкцію зі складання й підпису](packaging/README.md).

### Text selection / Виділений текст

The selection shortcut reads text exposed by Windows UI Automation and leaves the clipboard intact. If the source application does not expose the selection, copy it normally and use **Translate clipboard**.

Комбінація читатиме виділення, якщо програма-джерело надає його через Windows UI Automation. Вміст буфера обміну збережеться. Якщо програма не надає виділення, скопіюйте текст звичним способом і виберіть **Перекласти буфер обміну**.

### Files / Файли

Translate TXT, Markdown, PDF and DOCX. Scanned PDFs require text recognition first. Exported PDFs retain the original text layer. In DOCX, headers, footers, footnotes and comments stay in the original language.

Підтримуються TXT, Markdown, PDF і DOCX. Для сканованих PDF спершу розпізнайте текст. Експортований PDF зберігає оригінальний текстовий шар. У DOCX колонтитули, виноски й коментарі залишаються мовою оригіналу.

## Development / Розробка

Use the current stable Rust toolchain. The core and command-line tool are separate from the Windows WebView. Run from `rust/`:

Використовуйте актуальну стабільну версію Rust. Ядро й інструмент командного рядка працюють окремо від інтерфейсу Windows. Запускайте з `rust/`:

```sh
cargo test --locked
cargo build --locked --release -p ofm-cli
python3 scripts/gen_i18n.py --check
python3 scripts/check_i18n_keys.py
python3 scripts/check_shell_contract.py
```

See [module contracts](CONTRACTS.md) and the [interface preview](ui/README.md). Port contributed by [acipat](https://github.com/Lexus2016/deepl-on-free-models/pull/2).

Дивіться [контракти модулів](CONTRACTS.md) і [попередній перегляд інтерфейсу](ui/README.md). Порт створив [acipat](https://github.com/Lexus2016/deepl-on-free-models/pull/2).
