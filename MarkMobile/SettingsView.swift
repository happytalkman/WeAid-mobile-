import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var chat: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = KeyStore.read()
    @State private var models: [String] = []
    @State private var loading = false
    @State private var status: String?
    @State private var jauvexLink = ""
    @State private var jauvexStatus: String?
    @State private var jauvexChecking = false
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
                    TextField("http://컴퓨터주소:4343/mobile?token=…", text: $jauvexLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button(jauvexChecking ? "연결 확인 중…" : "링크 저장 · 연결 확인") { Task { await connectJauvex() } }.disabled(jauvexChecking || jauvexLink.isEmpty)
                    if chat.jauvexConnected { Text("연결됨: \(JauvexSettings.url) · 폴더 \(chat.jauvexFolders.count)개 · 에이전트 \(chat.jauvexAgents.count)개").font(.caption).textSelection(.enabled) }
                    if let jauvexStatus { Text(jauvexStatus).font(.caption).foregroundStyle(.secondary) }
                    if chat.jauvexConnected {
                        Button("Jauvex 연결 해제", role: .destructive) {
                            try? JauvexSettings.save(url: "", token: ""); chat.jauvexConnected = false; Task { await chat.openJauvex(nil) }; jauvexStatus = "연결을 해제했습니다."
                        }.disabled(chat.busy)
                    }
                } header: { Text("Jauvex 연결") } footer: {
                    Text("컴퓨터에서 Jauvex 웹 버전을 CVC_WEB_LAN=1 npm run web 으로 시작하면 폰용 링크가 출력됩니다. 그 링크를 붙여 넣으면 왼쪽 위 메뉴에서 Jauvex의 폴더와 에이전트(Claude, Codex, ZCode, Claw)를 고를 수 있습니다. 같은 Wi-Fi에서만 연결되며, 토큰이 일반 HTTP로 오가므로 믿을 수 있는 네트워크에서만 사용하세요.")
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
    @MainActor private func connectJauvex() async {
        guard let parsed = JauvexSettings.parse(link: jauvexLink) else { jauvexStatus = "링크에 주소와 token이 있어야 합니다. 서버가 출력한 링크를 그대로 붙여 넣으세요."; return }
        jauvexChecking = true
        defer { jauvexChecking = false }
        do {
            guard let client = JauvexClient(url: parsed.url, token: parsed.token) else { throw AppFailure(message: "주소를 읽을 수 없습니다.") }
            let (folders, agents) = try await client.agents()
            try JauvexSettings.save(url: parsed.url, token: parsed.token)
            chat.jauvexConnected = true; await chat.loadJauvex(); jauvexLink = ""
            jauvexStatus = "연결 확인 완료: 폴더 \(folders.count)개, 에이전트 \(agents.count)개."
        } catch { jauvexStatus = error.localizedDescription }
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
