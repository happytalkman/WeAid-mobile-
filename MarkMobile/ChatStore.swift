import SwiftUI
import AVFoundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var deviceDraft: DeviceDraft?
    @Published var draft = ""
    @Published var photo: Data?
    @Published var busy = false
    @Published var error: String?
    @Published var model = UserDefaults.standard.string(forKey: "model") ?? ""
    @Published var readAloud = UserDefaults.standard.bool(forKey: "readAloud")
    @Published var hasKey = !KeyStore.read().isEmpty
    private let speaker = AVSpeechSynthesizer()
    private var job: Task<Void, Never>?
    private let historyURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        historyURL = folder.appendingPathComponent("conversation.json")
        if let data = try? Data(contentsOf: historyURL), let old = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = old
        }
    }
    func save() {
        do {
            // Keep text locally; selected photos are used for the current request only.
            let textOnly = messages.map { ChatMessage(id: $0.id, role: $0.role, text: $0.text) }
            let data = try JSONEncoder().encode(textOnly)
            try data.write(to: historyURL, options: [.atomic, .completeFileProtection])
            var url = historyURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch { self.error = "대화를 기기에 저장하지 못했습니다." }
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty || photo != nil else { return }
        if photo == nil, let action = DeviceDraft.parse(text) {
            deviceDraft = action; draft = ""; return
        }
        let key = KeyStore.read()
        guard !key.isEmpty, !model.isEmpty else { error = "설정에서 API 키를 저장하고 모델을 선택해 주세요."; return }
        stopSpeaking()
        let pending = ChatMessage(role: "user", text: text.isEmpty ? "이 사진을 설명해 주세요." : text, photo: photo)
        let prior = Array(messages.suffix(20))
        draft = ""; photo = nil; busy = true; error = nil
        messages.append(pending)
        job = Task {
            defer { busy = false; job = nil }
            do {
                let answer = try await GeminiClient().reply(messages: prior + [pending], key: key, model: model)
                try Task.checkCancellation()
                if let index = messages.firstIndex(where: { $0.id == pending.id }) { messages[index].photo = nil }
                messages.append(ChatMessage(role: "model", text: answer))
                save()
                if readAloud { speak(answer) }
            } catch {
                messages.removeAll { $0.id == pending.id }
                draft = pending.text; photo = pending.photo
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { job?.cancel(); stopSpeaking() }
    func clear() {
        guard !busy else { return }
        stopSpeaking(); messages = []; save()
    }
    func speak(_ text: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
            speaker.speak(utterance)
        } catch { self.error = "음성 출력을 시작하지 못했습니다." }
    }
    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }
}
