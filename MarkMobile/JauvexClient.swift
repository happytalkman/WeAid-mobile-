import Foundation
import Security

// Jauvex (github.com/happytalkman/code-jauvex): a desktop app that runs coding agents (Claude, Codex, ZCode, Claw) side by side.
// Its web version, started with `CVC_WEB_LAN=1 npm run web`, answers on the computer's LAN address with the same calls its own window
// makes: POST /rpc {name, args, undef} and the server-sent events of GET /events, every call with the token it prints. MARK Mobile
// talks to it here: the folders and agents, a turn, what is said during a turn, the app's own orders and Jauvex's quick lines.

struct JauvexFolder: Identifiable, Hashable { let id: String; let name: String; let path: String }
struct JauvexAgent: Identifiable, Hashable {
    let sessionId: String?   // nil: a new agent, until its first turn names it
    let projectId: String
    let folder: String
    let title: String
    let provider: String     // claude, codex, zcode, claw
    var id: String { sessionId ?? "new:\(projectId):\(provider)" }
}

enum JauvexProviders {
    static let all = ["claude", "codex", "zcode", "claw"]
    static func label(_ p: String) -> String { ["claude": "Claude", "codex": "Codex", "zcode": "ZCode", "claw": "Claw"][p] ?? p }
}

/// The server's address and token. The address in UserDefaults, the token in the Keychain (this device only), like the Gemini key.
enum JauvexSettings {
    private static let urlKey = "jauvexURL"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MarkMobile.Jauvex", kSecAttrAccount as String: "web-token"]
    }
    static var url: String { UserDefaults.standard.string(forKey: urlKey) ?? "" }
    static var token: String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static var configured: Bool { !url.isEmpty && !token.isEmpty }
    static func save(url: String, token: String) throws {
        SecItemDelete(query as CFDictionary)
        if !token.isEmpty {
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppFailure(message: "Jauvex 토큰 저장 실패: \(status)") }
        }
        UserDefaults.standard.set(url, forKey: urlKey)
    }
    /// The link the server prints for a phone, "http://192.168.0.12:4343/mobile?token=…", as an address and a token.
    static func parse(link: String) -> (url: String, token: String)? {
        guard let parts = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = parts.scheme, let host = parts.host,
              let token = parts.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else { return nil }
        return ("\(scheme)://\(host)\(parts.port.map { ":\($0)" } ?? "")", token)
    }
}

/// A line of the conversation as MARK shows it: the user's words, or the agent's answer to them.
struct JauvexLine { let role: String; let text: String }

final class JauvexClient {
    let base: URL
    let token: String
    init?(url: String = JauvexSettings.url, token: String = JauvexSettings.token) {
        guard let base = URL(string: url), !token.isEmpty else { return nil }
        self.base = base; self.token = token
    }

    // ---- the calls, by the channel names of the app's own window (web/src/webDesktop.ts)
    func rpc(_ name: String, _ args: [Any?] = [], timeout: TimeInterval = 60) async throws -> Any? {
        var req = URLRequest(url: base.appendingPathComponent("rpc"))
        req.httpMethod = "POST"; req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(token, forHTTPHeaderField: "x-jauvex-token")
        let undef = args.indices.filter { args[$0] == nil } // the server restores them as undefined, as the app's own IPC gives them
        let body: [String: Any] = ["name": name, "args": args.map { $0 ?? NSNull() }, "undef": undef]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw AppFailure(message: "Jauvex 토큰이 맞지 않습니다. 서버가 새로 출력한 링크를 설정에 다시 붙여 넣으세요.") }
        if code == 421 { throw AppFailure(message: "Jauvex 서버가 이 주소를 받지 않습니다. 컴퓨터에서 CVC_WEB_LAN=1로 시작했는지 확인하세요.") }
        guard code == 200, let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppFailure(message: "Jauvex 서버 응답 오류 (\(code))") }
        guard reply["ok"] as? Bool == true else { throw AppFailure(message: reply["error"] as? String ?? "Jauvex 요청이 실패했습니다.") }
        let value = reply["value"]; return value is NSNull ? nil : value
    }
    func api(_ method: String, _ args: [Any?] = []) async throws -> Any? { try await rpc("api", [method as Any?] + args) }

    /// The folders, and the agents kept in each (their titles from the provider's own list).
    func agents() async throws -> ([JauvexFolder], [JauvexAgent]) {
        guard let state = try await api("state") as? [String: Any], let projects = state["projects"] as? [[String: Any]] else { throw AppFailure(message: "Jauvex 상태를 읽지 못했습니다.") }
        var folders: [JauvexFolder] = []; var agents: [JauvexAgent] = []
        for p in projects where p["builtin"] == nil {
            guard let id = p["id"] as? String, let name = p["name"] as? String else { continue }
            folders.append(JauvexFolder(id: id, name: name, path: p["path"] as? String ?? ""))
            let providers = p["providers"] as? [String: String] ?? [:]
            let infos = (try? await api("sessions", [id])) as? [[String: Any]] ?? []
            for sid in p["sessions"] as? [String] ?? [] {
                let info = infos.first { $0["sessionId"] as? String == sid }
                let title = (info?["customTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (info?["summary"] as? String) ?? "새 대화"
                agents.append(JauvexAgent(sessionId: sid, projectId: id, folder: name, title: title, provider: providers[sid] ?? info?["provider"] as? String ?? "claude"))
            }
        }
        return (folders, agents)
    }

    /// A session as MARK's lines: the app's notes and the tool results a transcript files as user messages are left out, the dictation
    /// tag comes off, and the messages of one answer make one line (Jauvex's shared/mobile.ts does the same for its phone screen).
    func lines(projectId: String, sessionId: String) async throws -> [JauvexLine] {
        guard let page = try await api("messages", [projectId, sessionId, nil]) as? [String: Any], let messages = page["messages"] as? [[String: Any]] else { return [] }
        var out: [JauvexLine] = []
        for m in messages {
            if m["meta"] as? Bool == true { continue }
            let role = m["role"] as? String ?? ""
            let blocks = m["blocks"] as? [[String: Any]] ?? []
            let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                .replacingOccurrences(of: "[voice transcript] ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if role == "user" { if !text.isEmpty { out.append(JauvexLine(role: "user", text: text)) }; continue }
            guard role == "assistant", !text.isEmpty else { continue }
            if let last = out.last, last.role == "model" { out[out.count - 1] = JauvexLine(role: "model", text: last.text + "\n\n" + text) }
            else { out.append(JauvexLine(role: "model", text: text)) }
        }
        return out
    }

    func command(_ text: String, folders: [JauvexFolder], currentId: String) async throws -> [String: Any]? {
        try await rpc("voice:command", [text, folders.map { ["id": $0.id, "name": $0.name, "path": $0.path] }, currentId], timeout: 40) as? [String: Any]
    }
    func ack(_ text: String) async -> String { ((try? await rpc("voice:ack", [text], timeout: 8)) as? String) ?? "" }
    func triage(_ text: String, provider: String, task: String) async -> [String: Any]? { (try? await rpc("voice:triage", [text, provider, "", "", task], timeout: 10)) as? [String: Any] }
    func summarize(asked: String, answer: String, provider: String) async -> String { ((try? await rpc("voice:summarize", [asked, answer, provider, "", ""], timeout: 16)) as? String) ?? "" }
    func start(chatId: String, projectId: String, sessionId: String?, provider: String, text: String) async throws {
        let req: [String: Any] = ["chatId": chatId, "projectId": projectId, "sessionId": sessionId ?? NSNull(), "provider": provider, "text": text, "permissions": "ask"]
        _ = try await rpc("chat:start", [req])
    }
    func steer(chatId: String, text: String) async -> Bool { ((try? await rpc("chat:steer", [chatId, text, nil])) as? Bool) ?? false }
    func stop(chatId: String) async { _ = try? await rpc("chat:stop", [chatId]) }
    func answer(chatId: String, requestId: String, allow: Bool) async { _ = try? await rpc("chat:answer", [chatId, requestId, allow ? "allow" : "deny"]) }

    /// What the app's main process sends its window about the turns (`chat:event`), as they come.
    func chatEvents() -> AsyncThrowingStream<[String: Any], Error> {
        let url = self.base.appendingPathComponent("events"), key = self.token
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: url)
                    req.setValue(key, forHTTPHeaderField: "x-jauvex-token"); req.timeoutInterval = 24 * 3600
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppFailure(message: "Jauvex 이벤트에 연결하지 못했습니다.") }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "), let data = String(line.dropFirst(6)).data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              event["channel"] as? String == "chat:event", let payload = event["payload"] as? [String: Any] else { continue }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The first message of an agent opened from the menu: Jauvex's own (kickoffMessage in its shared/types.ts).
    static func kickoff(folder: JauvexFolder) -> String {
        ["You are a new agent, just opened by the user from the app they run their agents in, in the folder \"\(folder.name)\" (\(folder.path)).",
         "They have not said yet what you are for.",
         "Other agents may be working in this folder or in others; you only see this conversation. Do not change any file yet.",
         "In one or two lines, say you are ready and ask what they want you to do. Then wait."].joined(separator: "\n")
    }
    /// An answer to the app's question about an order (Jauvex's answerIs, shared/orders.ts): yes, no, or neither.
    static func answerIs(_ text: String) -> Bool? {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        if t.split(separator: " ").count > 8 { return nil }
        for no in ["아니", "아뇨", "싫어", "취소", "하지 마", "됐어", "그만", "no", "nope", "cancel", "don't", "not that"] where t.hasPrefix(no) { return false }
        for yes in ["네", "넵", "예", "응", "그래", "좋아", "맞아", "오케이", "열어", "만들어", "yes", "yeah", "yep", "sure", "ok", "okay", "go ahead", "do it"] where t.hasPrefix(yes) { return true }
        return nil
    }
}
