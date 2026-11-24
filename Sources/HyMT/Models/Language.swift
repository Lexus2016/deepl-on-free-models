import Foundation
import NaturalLanguage

/// A language supported by Hy-MT2. `englishName` is what goes into the model
/// instruction; `localName` is what the interface shows.
struct Language: Identifiable, Hashable, Codable {
    let code: String
    let englishName: String
    let localName: String
    let bcp47: String?

    var id: String { code }

    static let auto = Language(
        code: "auto",
        englishName: "",
        localName: "Автовизначення",
        bcp47: nil
    )

    static func with(code: String) -> Language? {
        all.first { $0.code == code }
    }

    func displayName(in language: AppLanguage) -> String {
        if self == .auto {
            return L10n.t("Auto-detect", language)
        }
        let locale = Locale(identifier: language.localeIdentifier)
        if let name = locale.localizedString(forIdentifier: code) {
            return name
        }
        if let name = locale.localizedString(forLanguageCode: code) {
            return name
        }
        return englishName
    }

    static func pickerOptions(in interfaceLanguage: AppLanguage, includeAuto: Bool, query: String) -> [Language] {
        let locale = Locale(identifier: interfaceLanguage.localeIdentifier)
        let folding: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let prefix = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: folding, locale: locale)
        func matches(_ language: Language) -> Bool {
            guard !prefix.isEmpty else { return true }
            let names = [
                language.displayName(in: interfaceLanguage), language.englishName,
                language.localName, language.displayName(in: .ru), language.code
            ]
            return names.contains { name in
                let folded = name.folding(options: folding, locale: locale)
                return folded.hasPrefix(prefix) || folded.split(whereSeparator: { !$0.isLetter })
                    .contains { $0.hasPrefix(prefix) }
            }
        }

        let sorted = all.filter(matches).sorted {
            let comparison = $0.displayName(in: interfaceLanguage)
                .compare($1.displayName(in: interfaceLanguage), options: [.caseInsensitive], locale: locale)
            return comparison == .orderedSame ? $0.code < $1.code : comparison == .orderedAscending
        }
        return includeAuto && matches(.auto) ? [.auto] + sorted : sorted
    }

    static let all: [Language] = [
        Language(code: "zh", englishName: "Chinese", localName: "китайська", bcp47: "zh-CN"),
        Language(code: "en", englishName: "English", localName: "англійська", bcp47: "en-US"),
        Language(code: "fr", englishName: "French", localName: "французька", bcp47: "fr-FR"),
        Language(code: "pt", englishName: "Portuguese", localName: "португальська", bcp47: "pt-PT"),
        Language(code: "es", englishName: "Spanish", localName: "іспанська", bcp47: "es-ES"),
        Language(code: "ja", englishName: "Japanese", localName: "японська", bcp47: "ja-JP"),
        Language(code: "tr", englishName: "Turkish", localName: "турецька", bcp47: "tr-TR"),
        Language(code: "ru", englishName: "Russian", localName: "російська", bcp47: "ru-RU"),
        Language(code: "ar", englishName: "Arabic", localName: "арабська", bcp47: "ar-SA"),
        Language(code: "ko", englishName: "Korean", localName: "корейська", bcp47: "ko-KR"),
        Language(code: "th", englishName: "Thai", localName: "тайська", bcp47: "th-TH"),
        Language(code: "it", englishName: "Italian", localName: "італійська", bcp47: "it-IT"),
        Language(code: "de", englishName: "German", localName: "німецька", bcp47: "de-DE"),
        Language(code: "vi", englishName: "Vietnamese", localName: "в'єтнамська", bcp47: "vi-VN"),
        Language(code: "ms", englishName: "Malay", localName: "малайська", bcp47: "ms-MY"),
        Language(code: "id", englishName: "Indonesian", localName: "індонезійська", bcp47: "id-ID"),
        Language(code: "tl", englishName: "Filipino", localName: "філіппінська", bcp47: "fil-PH"),
        Language(code: "hi", englishName: "Hindi", localName: "гінді", bcp47: "hi-IN"),
        Language(code: "zh-Hant", englishName: "Traditional Chinese", localName: "китайська (традиційна)", bcp47: "zh-TW"),
        Language(code: "pl", englishName: "Polish", localName: "польська", bcp47: "pl-PL"),
        Language(code: "cs", englishName: "Czech", localName: "чеська", bcp47: "cs-CZ"),
        Language(code: "nl", englishName: "Dutch", localName: "нідерландська", bcp47: "nl-NL"),
        Language(code: "km", englishName: "Khmer", localName: "кхмерська", bcp47: "km-KH"),
        Language(code: "my", englishName: "Burmese", localName: "бірманська", bcp47: "my-MM"),
        Language(code: "fa", englishName: "Persian", localName: "перська", bcp47: "fa-IR"),
        Language(code: "gu", englishName: "Gujarati", localName: "гуджараті", bcp47: "gu-IN"),
        Language(code: "ur", englishName: "Urdu", localName: "урду", bcp47: "ur-PK"),
        Language(code: "te", englishName: "Telugu", localName: "телугу", bcp47: "te-IN"),
        Language(code: "mr", englishName: "Marathi", localName: "маратхі", bcp47: "mr-IN"),
        Language(code: "he", englishName: "Hebrew", localName: "іврит", bcp47: "he-IL"),
        Language(code: "bn", englishName: "Bengali", localName: "бенгальська", bcp47: "bn-BD"),
        Language(code: "ta", englishName: "Tamil", localName: "тамільська", bcp47: "ta-IN"),
        Language(code: "uk", englishName: "Ukrainian", localName: "українська", bcp47: "uk-UA"),
        Language(code: "bo", englishName: "Tibetan", localName: "тибетська", bcp47: "bo-CN"),
        Language(code: "kk", englishName: "Kazakh", localName: "казахська", bcp47: "kk-KZ"),
        Language(code: "mn", englishName: "Mongolian", localName: "монгольська", bcp47: "mn-MN"),
        Language(code: "ug", englishName: "Uyghur", localName: "уйгурська", bcp47: "ug-CN"),
        Language(code: "yue", englishName: "Cantonese", localName: "кантонська", bcp47: "yue-HK")
    ]

    /// Cheap script-based detection, enough to label the interface and to swap sides.
    static func detect(_ text: String, preferred: AppLanguage = .system) -> Language? {
        let sample = text.prefix(600)
        guard !sample.isEmpty else { return nil }

        func has(_ ranges: [ClosedRange<UInt32>]) -> Bool {
            sample.unicodeScalars.contains { scalar in
                ranges.contains { $0.contains(scalar.value) }
            }
        }

        if has([0x3040...0x30FF]) { return with(code: "ja") }
        if has([0xAC00...0xD7AF, 0x1100...0x11FF]) { return with(code: "ko") }
        if has([0x0E00...0x0E7F]) { return with(code: "th") }
        if has([0x0590...0x05FF]) { return with(code: "he") }
        if has([0x0600...0x06FF, 0x0750...0x077F]) { return with(code: "ar") }
        if has([0x0900...0x097F]) { return with(code: "hi") }
        if has([0x0980...0x09FF]) { return with(code: "bn") }
        if has([0x0B80...0x0BFF]) { return with(code: "ta") }
        if has([0x0C00...0x0C7F]) { return with(code: "te") }
        if has([0x0A80...0x0AFF]) { return with(code: "gu") }
        if has([0x4E00...0x9FFF, 0x3400...0x4DBF]) { return with(code: "zh") }
        if has([0x0400...0x04FF]) {
            let lowered = sample.lowercased()
            var ukScore = 0
            var ruScore = 0
            for character in lowered {
                switch character {
                case "і", "ї", "є", "ґ": ukScore += 2
                case "ы", "э", "ё", "ъ": ruScore += 2
                case "’": ukScore += 1
                default: break
                }
            }

            let tokens = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let ukWords: Set<String> = [
                "що", "цей", "ця", "ці", "після", "або", "також", "вже", "ще",
                "рядок", "рядки", "мова", "переклад", "можна", "потрібно",
                "який", "яка", "які", "було", "цього", "мене", "тебе", "його",
                "її", "вони", "ми", "ви", "безкоштовно", "локальні", "хмарні",
                "провайдери"
            ]
            let ruWords: Set<String> = [
                "что", "это", "этот", "эта", "эти", "после", "или", "также",
                "ещё", "еще", "строка", "строки", "язык", "перевод", "можно",
                "нужно", "который", "которая", "которые", "было", "этого",
                "меня", "тебя", "его", "её", "они", "мы", "вы", "бесплатно",
                "локальные", "облачные", "провайдеры"
            ]
            ukScore += tokens.filter { ukWords.contains($0) }.count
            ruScore += tokens.filter { ruWords.contains($0) }.count

            if ukScore > ruScore { return with(code: "uk") }
            if ruScore > ukScore { return with(code: "ru") }
            switch preferred.resolved {
            case .ru: return with(code: "ru")
            default: return with(code: "uk")
            }
        }
        if has([0x0530...0x058F]) { return nil }
        if has([0x10A0...0x10FF]) { return nil }
        if has([0x0041...0x024F]), sample.unicodeScalars.contains(where: CharacterSet.letters.contains) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(sample))
            if let hypothesis = recognizer.languageHypotheses(withMaximum: 1).first,
               hypothesis.value >= 0.55,
               let language = with(code: hypothesis.key.rawValue) {
                return language
            }
            return with(code: "en")
        }
        return nil
    }
}
