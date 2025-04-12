import AVFoundation
import Foundation

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var speechQueue: [String] = []
    private var _isSpeaking = false

    var isSpeaking: Bool {
        return _isSpeaking
    }

    var onQueueEmpty: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func addToQueue(_ text: String) {
        speechQueue.append(text)
        processSpeechQueue()
    }

    func clearQueueAndSpeak(_ text: String) {
        speechQueue.removeAll()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        addToQueue(text)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speechQueue.removeAll()
        _isSpeaking = false
    }

    func addObstacleWarning(_ text: String) {

        if !_isSpeaking {
            speechQueue.append(text)
            processSpeechQueue()
        } else {
            print("Speech in progress, obstacle warning skipped: \(text)")
        }
    }

    private func processSpeechQueue() {
        guard !_isSpeaking, !speechQueue.isEmpty else {
            return
        }

        _isSpeaking = true
        let text = speechQueue.removeFirst()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.55
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.speak(utterance)
    }
    
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self._isSpeaking = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.speechQueue.isEmpty {
                    self.onQueueEmpty?()
                } else {
                    self.processSpeechQueue()
                }
            }
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self._isSpeaking = false
            self.processSpeechQueue()
        }
    }
}
