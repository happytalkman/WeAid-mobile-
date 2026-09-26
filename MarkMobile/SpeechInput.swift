import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechInput: ObservableObject {
    @Published var recording = false
    @Published var starting = false
    @Published var transcript = ""
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    private var generation = UUID()

    func start() async {
        guard !recording, !starting else { return }
        starting = true
        defer { starting = false }
        let current = UUID(); generation = current
        let auth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == current else { return }
        guard auth == .authorized, mic else { error = "아이폰 설정에서 마이크와 음성 인식 권한을 허용해 주세요."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")), recognizer.isAvailable else {
            error = "한국어 음성 인식을 현재 사용할 수 없습니다."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AppFailure(message: "사용할 수 있는 마이크가 없습니다.") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            tapped = true; request = req; transcript = ""; error = nil
            task = recognizer.recognitionTask(with: req) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if result?.isFinal == true || failure != nil {
                        if failure != nil && self.transcript.isEmpty { self.error = "음성을 인식하지 못했습니다. 다시 시도해 주세요." }
                        self.stop()
                    }
                }
            }
            engine.prepare(); try engine.start(); recording = true
        } catch { stop(); self.error = error.localizedDescription }
    }
    func stop() {
        generation = UUID()
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
