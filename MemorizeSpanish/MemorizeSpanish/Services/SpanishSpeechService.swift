import AVFoundation
import Foundation

/// 使用系统 TTS 朗读西语单词（无需联网）。优先西/墨/美等 `es-*` 语音包。
@MainActor
final class SpanishSpeechService: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var didConfigureSession = false

    func speakSpanish(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !didConfigureSession {
            didConfigureSession = true
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true, options: [])
        }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.preferredSpanishVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func preferredSpanishVoice() -> AVSpeechSynthesisVoice? {
        for code in ["es-ES", "es-MX", "es-US", "es-419", "es"] {
            if let v = AVSpeechSynthesisVoice(language: code) { return v }
        }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("es") }
    }
}
