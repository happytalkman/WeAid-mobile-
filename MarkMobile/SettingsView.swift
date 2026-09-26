import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var chat: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = KeyStore.read()
    @State private var models: [String] = []
    @State private var loading = false
    @State private var status: String?
    private var version: String { return (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown" }
    private var build: String { return (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown" }
    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini 연결") {
                    SecureField("개인 Gemini API 키", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(loading ? "모델 확인 중…" : "키 저장 · 모델 불러오기") { Task { await connect() } }.disabled(loading || chat.busy)
                    if !chat.model.isEmpty {
                        Text("선택된 모델: \(chat.model)").font(.caption).textSelection(.enabled)
                    }
                    if !models.isEmpty {
                        Picker("모델", selection: $chat.model) {
                            Text("선택해 주세요").tag("")
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }.disabled(chat.busy)
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    Link("Google AI Studio에서 키 발급", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    Button("저장된 키 삭제", role: .destructive) {
                        do { try KeyStore.save(""); key = ""; chat.hasKey = false; status = "키를 삭제했습니다." }
                        catch { status = error.localizedDescription }
                    }.disabled(chat.busy || loading)
                }
                Section {
                    Toggle("답변을 한국어 음성으로 읽기", isOn: $chat.readAloud)
                } header: { Text("음성") } footer: {
                    Text("마이크를 눌러 녹음하고, 인식된 내용을 확인한 뒤 전송합니다. 항상 듣기 및 Gemini Live 실시간 음성 스트리밍은 이 버전에 포함되지 않습니다.")
                }
                Section("데이터 안내") {
                    Text("전송 시 질문·사진·최근 20개 메시지가 Google Gemini에 전달됩니다. API 비용과 한도는 본인 계정 설정을 따릅니다. 음성 인식은 Apple 서버를 사용할 수 있습니다.")
                    Text("API 키는 기기 Keychain에, 대화 텍스트는 기기 내 파일에 저장됩니다. 사진과 음성 파일은 대화 기록에 저장하지 않습니다. 대화는 상단 메뉴에서 삭제할 수 있습니다.")
                }.font(.caption)
                Section("프로젝트") {
                    Text("MARK Mobile · iOS 17 이상")
                    Text("버전 \(version) · 빌드 \(build)")
                    Text("베타 테스트: 아이폰 제어는 API 키 없이 사용할 수 있습니다. AI 대화는 개인 Gemini 키가 필요합니다.")
                    Text("Based on fatihmakes/mark-lii · FatihMakes\n원본 CC BY-NC 4.0 · 비상업용\niOS 전환: SwiftUI 독립 클라이언트")
                    Link("원본 저장소", destination: URL(string: "https://github.com/fatihmakes/mark-lii")!)
                }.font(.caption)
            }
            .navigationTitle("설정")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .onChange(of: chat.model) { UserDefaults.standard.set($0, forKey: "model") }
            .onChange(of: chat.readAloud) { UserDefaults.standard.set($0, forKey: "readAloud") }
        }
    }
    @MainActor private func connect() async {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { status = "API 키를 입력해 주세요."; return }
        loading = true
        defer { loading = false }
        do {
            let result = try await GeminiClient().models(key: cleaned)
            guard !result.isEmpty else { throw AppFailure(message: "사용 가능한 텍스트 모델이 없습니다.") }
            try KeyStore.save(cleaned); chat.hasKey = true; models = result
            if !result.contains(chat.model) { chat.model = "" }
            status = "연결 확인 완료. 사용할 모델을 직접 선택해 주세요."
        } catch { status = error.localizedDescription }
    }
}
