import Foundation
import Security

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let role: String
    let text: String
    var photo: Data? = nil
}

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum KeyStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "MarkMobile.Gemini",
         kSecAttrAccount as String: "personal-api-key"]
    }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AppFailure(message: "키 삭제 실패: \(status)")
            }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppFailure(message: "키 저장 실패: \(status)") }
    }
}

struct GeminiClient {
    private let base = "https://generativelanguage.googleapis.com/v1beta/"
    private func request(_ path: String, key: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw AppFailure(message: "잘못된 API 주소입니다.") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 90
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AppFailure(message: "서버 응답을 확인할 수 없습니다.") }
        guard (200..<300).contains(http.statusCode) else {
            let hint: String
            switch http.statusCode {
            case 400: hint = "요청 또는 모델 설정을 확인해 주세요."
            case 401, 403: hint = "API 키와 모델 접근 권한을 확인해 주세요."
            case 404: hint = "모델 목록을 새로 불러와 선택해 주세요."
            case 429: hint = "사용량 한도에 도달했습니다. 잠시 후 다시 시도해 주세요."
            default: hint = "잠시 후 다시 시도해 주세요."
            }
            throw AppFailure(message: "Gemini 오류 \(http.statusCode). \(hint)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppFailure(message: "응답 형식을 읽을 수 없습니다.")
        }
        return json
    }
    func models(key: String) async throws -> [String] {
        var names: [String] = []
        var token: String? = nil
        repeat {
            let suffix = token.map { "&pageToken=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") } ?? ""
            let json = try await request("models?pageSize=1000" + suffix, key: key)
            names += (json["models"] as? [[String: Any]] ?? []).compactMap { item in
                guard (item["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
                return (item["name"] as? String)?.replacingOccurrences(of: "models/", with: "")
            }
            token = json["nextPageToken"] as? String
        } while token != nil && token != ""
        return names.sorted()
    }
    func reply(messages: [ChatMessage], key: String, model: String) async throws -> String {
        guard model.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw AppFailure(message: "모델 목록에서 사용할 모델을 선택해 주세요.")
        }
        let contents: [[String: Any]] = messages.map { message in
            var parts: [[String: Any]] = [["text": message.text]]
            if let photo = message.photo { parts.append(["inlineData": ["mimeType": "image/jpeg", "data": photo.base64EncodedString()]]) }
            return ["role": message.role, "parts": parts]
        }
        let json = try await request("models/\(model):generateContent", key: key, body: [
            "systemInstruction": ["parts": [["text": "당신은 MARK Mobile 개인 AI 비서입니다. 한국어 존댓말로 명확하게 답하세요. 실제 기기 제어 도구는 없습니다. 실행하지 않은 작업을 실행했다고 말하지 마세요."]]],
            "contents": contents
        ])
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let answer = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !answer.isEmpty else { throw AppFailure(message: "텍스트 답변이 없습니다. 질문을 바꾸거나 다른 모델을 선택해 주세요.") }
        return answer
    }
}
