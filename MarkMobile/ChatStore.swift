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
    // Jauvex (JauvexClient.swift): with an agent chosen, the chat is that agent's; with none, MARK answers through Gemini as before.
    @Published var jauvexAgent: JauvexAgent?
    @Published var jauvexFolders: [JauvexFolder] = []
    @Published var jauvexAgents: [JauvexAgent] = []
    @Published var jauvexConnected = JauvexSettings.configured
    @Published var jauvexAsk: JauvexAsk?   // a tool the agent asks to use: allowed or denied here
    @Published var jauvexLive = ""        // the answer as it is written
    private var jauvexChat = ""           // this chat's id with the Jauvex server
    private var jauvexAsked = ""          // what the running turn was asked, for the triage and the summary
    private var jauvexQueue: [String] = []
    private var jauvexPending: (order: [String: Any], text: String)?
    private var jauvexBye = ""
    private var jauvexEvents: Task<Void, Never>?
    private var markMessages: [ChatMessage] = [] // MARK's own conversation, kept while an agent's is on screen
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
        guard jauvexAgent == nil else { return } // an agent's conversation lives in Jauvex, not in MARK's file
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
        guard !busy || jauvexAgent != nil, !text.isEmpty || photo != nil else { return } // an agent at work takes what is said (steered in)
        if photo == nil, let action = DeviceDraft.parse(text) {
            deviceDraft = action; draft = ""; return
        }
        if jauvexAgent != nil || (jauvexConnected && jauvexPending != nil) { draft = ""; Task { await sendJauvex(text) }; return }
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
    func cancel() {
        if jauvexAgent != nil, !jauvexChat.isEmpty, let client = JauvexClient() { let id = jauvexChat; Task { await client.stop(chatId: id) } }
        job?.cancel(); stopSpeaking()
    }
    func clear() {
        guard !busy else { return }
        stopSpeaking(); messages = []; save()
    }
    func speak(_ text: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            // each line in its own language: Jauvex's agents often answer in English, and a Korean voice reads English poorly
            utterance.voice = AVSpeechSynthesisVoice(language: text.range(of: "[가-힣]", options: .regularExpression) != nil ? "ko-KR" : "en-US")
            speaker.speak(utterance)
        } catch { self.error = "음성 출력을 시작하지 못했습니다." }
    }
    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }

    // ---- Jauvex
    func loadJauvex() async {
        guard let client = JauvexClient() else { jauvexConnected = false; return }
        do { (jauvexFolders, jauvexAgents) = try await client.agents(); jauvexConnected = true; listenJauvex() }
        catch { self.error = error.localizedDescription }
    }
    /// Opens an agent's conversation (nil: back to MARK's own, through Gemini).
    func openJauvex(_ agent: JauvexAgent?) async {
        guard !busy || jauvexAgent != nil else { return }
        if jauvexAgent == nil, agent != nil { markMessages = messages }
        jauvexAgent = agent; jauvexChat = "mark-\(UUID().uuidString)"; jauvexQueue = []; jauvexPending = nil; jauvexLive = ""; jauvexAsk = nil; busy = false; error = nil
        guard let agent else { messages = markMessages; return }
        messages = []
        if let sid = agent.sessionId, let client = JauvexClient() {
            do { messages = try await client.lines(projectId: agent.projectId, sessionId: sid).map { ChatMessage(role: $0.role, text: $0.text) } }
            catch { self.error = error.localizedDescription }
        }
    }
    func newJauvexAgent(in folder: JauvexFolder, provider: String) async {
        await openJauvex(JauvexAgent(sessionId: nil, projectId: folder.id, folder: folder.name, title: "새 \(JauvexProviders.label(provider)) 에이전트", provider: provider))
        await startJauvex(JauvexClient.kickoff(folder: folder))
    }
    func answerJauvex(allow: Bool) {
        guard let ask = jauvexAsk, let client = JauvexClient() else { return }
        jauvexAsk = nil; let id = jauvexChat; Task { await client.answer(chatId: id, requestId: ask.requestId, allow: allow) }
    }
    private func note(_ line: String) { messages.append(ChatMessage(role: "app", text: line)); if readAloud { speak(line) } }

    /// One thing said or typed: an answer to the app's question, an order for the app (Jauvex's own reading, Korean too), words for the
    /// running turn (steer, queue, stop, replace), or a new turn. The same order as Jauvex's phone screen (web/src/Mobile.tsx).
    private func sendJauvex(_ said: String) async {
        guard let client = JauvexClient() else { error = "설정에서 Jauvex 연결 링크를 저장해 주세요."; return }
        let korean = said.range(of: "[가-힣]", options: .regularExpression) != nil
        var order: [String: Any]?
        if let was = jauvexPending {
            jauvexPending = nil
            switch JauvexClient.answerIs(said) {
            case true?: order = was.order
            case false?: await forward(was.text); return
            case nil: await forward(was.text + "\n\n" + said); return
            }
        } else {
            order = try? await client.command(said, folders: jauvexFolders, currentId: jauvexAgent?.projectId ?? jauvexFolders.first?.id ?? "")
        }
        if let order, let type = order["type"] as? String {
            let say = order["say"] as? String ?? ""
            messages.append(ChatMessage(role: "user", text: said))
            switch type {
            case "confirm": if let pending = order["pending"] as? [String: Any] { jauvexPending = (pending, order["text"] as? String ?? said) }; note(say); return
            case "hold": note(say); return
            case "goodbye": if order["after"] as? Bool != true { note(say); return }; jauvexBye = say; messages.removeLast()
            case "reload-ui": note(korean ? "화면 새로고침은 컴퓨터의 Jauvex에서 해 주세요." : "Reload the interface on the computer."); return
            case "restart-app": note(korean ? "앱 재시작은 컴퓨터에서 해 주세요. 여기서 하면 폰에서 다시 켤 수 없어요." : "Restart the app on the computer: from here, the phone could not start it again."); return
            case "new-agent":
                let provider = order["provider"] as? String ?? jauvexAgent?.provider ?? "claude"
                if provider == "jev" { note(korean ? "제브 에이전트는 컴퓨터 화면에서 열어 주세요." : "Open a Jev agent on the computer."); return }
                guard let folder = jauvexFolders.first(where: { $0.id == (order["projectId"] as? String ?? jauvexAgent?.projectId) }) ?? jauvexFolders.first else { return }
                await openJauvex(JauvexAgent(sessionId: nil, projectId: folder.id, folder: folder.name, title: order["name"] as? String ?? "새 \(JauvexProviders.label(provider)) 에이전트", provider: provider))
                note(say)
                await startJauvex(order["kickoff"] as? String ?? JauvexClient.kickoff(folder: folder)); return
            default: break
            }
        }
        await forward(said)
    }
    private func forward(_ said: String) async {
        guard let agent = jauvexAgent, let client = JauvexClient() else { note("먼저 왼쪽 위 메뉴에서 Jauvex 에이전트를 고르세요."); return }
        if !busy {
            Task { let line = await client.ack(said); if readAloud, !line.isEmpty { speak(line) } } // Jev's quick line, in the language it was said in
            await startJauvex(said); return
        }
        // the agent is working: handed to it at once unless they ask to wait, stop or replace (Jauvex decides, Jev first)
        let r = await client.triage(said, provider: agent.provider, task: jauvexAsked)
        let action = r?["action"] as? String ?? "steer"
        messages.append(ChatMessage(role: "user", text: said))
        switch action {
        case "queue": jauvexQueue.append(said)
        case "stop": await client.stop(chatId: jauvexChat)
        case "replace": jauvexQueue.insert(said, at: 0); await client.stop(chatId: jauvexChat)
        default: if !(await client.steer(chatId: jauvexChat, text: said)) { jauvexQueue.append(said) }
        }
        if readAloud, let line = r?["say"] as? String, !line.isEmpty { speak(line) }
    }
    private func startJauvex(_ text: String) async {
        guard let agent = jauvexAgent, let client = JauvexClient() else { return }
        listenJauvex(); stopSpeaking()
        busy = true; error = nil; jauvexAsked = text; jauvexLive = ""
        messages.append(ChatMessage(role: "user", text: text))
        do { try await client.start(chatId: jauvexChat, projectId: agent.projectId, sessionId: agent.sessionId, provider: agent.provider, text: text) }
        catch { busy = false; self.error = error.localizedDescription }
    }
    /// The server's events, for as long as the app is connected: this chat's turn, as it goes.
    private func listenJauvex() {
        guard jauvexEvents == nil, let client = JauvexClient() else { return }
        jauvexEvents = Task { [weak self] in
            while !Task.isCancelled {
                do { for try await event in client.chatEvents() { await self?.onJauvex(event) } } catch { }
                try? await Task.sleep(nanoseconds: 2_000_000_000) // the server restarted or the Wi-Fi dropped: try again
            }
        }
    }
    private func onJauvex(_ event: [String: Any]) async {
        guard event["chatId"] as? String == jauvexChat, var agent = jauvexAgent else { return }
        switch event["type"] as? String {
        case "init":
            if let sid = event["sessionId"] as? String, agent.sessionId == nil { agent = JauvexAgent(sessionId: sid, projectId: agent.projectId, folder: agent.folder, title: agent.title, provider: agent.provider); jauvexAgent = agent }
        case "delta": jauvexLive += event["text"] as? String ?? ""
        case "permission":
            let raw = event["input"] ?? [String: Any]()
            let input = JSONSerialization.isValidJSONObject(raw) ? (try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted])).flatMap { String(data: $0, encoding: .utf8) } ?? "" : String(describing: raw)
            jauvexAsk = JauvexAsk(requestId: event["requestId"] as? String ?? "", tool: event["toolName"] as? String ?? "", input: String(input.prefix(400)))
        case "done":
            busy = false; jauvexLive = ""; jauvexAsk = nil
            if event["ok"] as? Bool == false, let why = event["error"] as? String { error = why }
            guard let client = JauvexClient(), let sid = (event["sessionId"] as? String) ?? agent.sessionId else { return }
            if let lines = try? await client.lines(projectId: agent.projectId, sessionId: sid) { messages = lines.map { ChatMessage(role: $0.role, text: $0.text) } }
            if readAloud, let answer = messages.last(where: { $0.role == "model" })?.text {
                let summary = await client.summarize(asked: jauvexAsked, answer: answer, provider: agent.provider)
                speak(summary.isEmpty ? String(answer.prefix(240)) : summary)
            }
            if !jauvexBye.isEmpty { note(jauvexBye); jauvexBye = "" }
            if !jauvexQueue.isEmpty { await startJauvex(jauvexQueue.removeFirst()) }
            if let list = try? await client.agents() { jauvexFolders = list.0; jauvexAgents = list.1 }
        default: break
        }
    }
}

/// A tool the agent asks to use, shown as a card: its name and what it would do.
struct JauvexAsk: Identifiable { let requestId: String; let tool: String; let input: String; var id: String { requestId } }
