import AVFoundation
import Foundation

/// System speech with an explicit voice choice and a real stop control.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    var onFinish: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    @discardableResult
    func speak(_ text: String, language: Language, voiceID: String?) -> Bool {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let code = language.bcp47 else { return false }

        let utterance = AVSpeechUtterance(string: String(trimmed.prefix(4000)))
        if let voiceID, !voiceID.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: code) {
            utterance.voice = voice
        } else {
            return false
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        let code = languageCode == "auto"
            ? (Locale.current.language.languageCode?.identifier ?? "en")
            : languageCode
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(code.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        onFinish?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        onFinish?()
    }
}
