import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var chat: ChatStore
    @StateObject private var speech = SpeechInput()
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var clearConfirmation = false
    private let cyan = Color(red: 0.3, green: 0.9, blue: 0.95)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Circle().fill(ready ? cyan : .orange).frame(width: 6, height: 6)
                    Text(chat.busy ? "답변을 준비하고 있습니다" : (ready ? "대화 준비됨" : "설정에서 API 연결이 필요합니다"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(chat.jauvexAgent.map { "JAUVEX · \(JauvexProviders.label($0.provider).uppercased())" } ?? "PERSONAL AI").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(cyan)
                }.padding(.horizontal, 20).padding(.vertical, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if chat.messages.isEmpty { welcome }
                            ForEach(chat.messages) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(label(message.role)).font(.caption.bold()).foregroundStyle(message.role == "model" ? cyan : .secondary)
                                    Text(message.text).textSelection(.enabled).font(.body).lineSpacing(5)
                                    if message.photo != nil { Label("사진 첨부", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
                                }
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "model" ? cyan.opacity(0.06) : Color.white.opacity(message.role == "app" ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 18))
                                .id(message.id)
                            }
                            if !chat.jauvexLive.isEmpty { // the agent's answer as it is written
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(label("model")).font(.caption.bold()).foregroundStyle(cyan)
                                    Text(chat.jauvexLive).font(.body).lineSpacing(5)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                            }
                            if chat.busy && chat.jauvexLive.isEmpty { ProgressView("\(label("model"))가 생각하고 있습니다…").tint(cyan).font(.caption) }
                        }.padding(20)
                    }
                    .onChange(of: chat.messages.count + chat.jauvexLive.count) { _ in
                        if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if let error = chat.error ?? speech.error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button { chat.error = nil; speech.error = nil } label: { Image(systemName: "xmark.circle") }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
                composer
            }
            .background(Color(red: 0.025, green: 0.04, blue: 0.075))
            .navigationTitle("MARK / Mobile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        if chat.jauvexConnected { jauvexMenu }
                        Button("읽어주기 중지", systemImage: "speaker.slash") { chat.stopSpeaking() }
                        Button("대화 삭제", systemImage: "trash", role: .destructive) { clearConfirmation = true }.disabled(chat.busy || chat.jauvexAgent != nil)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { speech.stop(); chat.deviceDraft = DeviceDraft() } label: { Image(systemName: "iphone") }.accessibilityLabel("아이폰 제어")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { speech.stop(); settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("설정")
                }
            }
            .sheet(item: $chat.deviceDraft) { DeviceActionsView(draft: $0) }
            .sheet(isPresented: $settings) { SettingsView().environmentObject(chat) }
            .confirmationDialog("기기에 저장한 대화를 삭제하시겠습니까?", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("대화 삭제", role: .destructive) { chat.clear() }
            }
            .onChange(of: speech.transcript) { chat.draft = $0 }
            .onChange(of: scenePhase) { phase in
                if phase != .active { speech.stop(); chat.stopSpeaking() }
            }
            .task(id: selection) { await loadPhoto() }
            .task { if chat.jauvexConnected { await chat.loadJauvex() } }
            .confirmationDialog(chat.jauvexAsk.map { "\($0.tool) 사용을 허용할까요?" } ?? "", isPresented: Binding(get: { chat.jauvexAsk != nil }, set: { _ in }), titleVisibility: .visible, presenting: chat.jauvexAsk) { _ in
                Button("허용") { chat.answerJauvex(allow: true) }
                Button("거부", role: .cancel) { chat.answerJauvex(allow: false) }
            } message: { ask in Text(ask.input) }
        }.tint(cyan)
    }
    private var ready: Bool { chat.jauvexAgent != nil || (chat.hasKey && !chat.model.isEmpty) }
    /// Who a line is from: the user, the app (Jauvex's own lines), or the agent (MARK when no Jauvex agent is chosen).
    private func label(_ role: String) -> String { role == "user" ? "나" : role == "app" ? "JAUVEX" : chat.jauvexAgent?.title ?? "MARK" }
    /// The Jauvex agents, by folder: open one, open a new one of any kind, or go back to MARK's own conversation.
    @ViewBuilder private var jauvexMenu: some View {
        Section("Jauvex 에이전트") {
            Button("MARK (Gemini)", systemImage: chat.jauvexAgent == nil ? "checkmark" : "sparkles") { Task { await chat.openJauvex(nil) } }
            ForEach(chat.jauvexFolders) { folder in
                Menu(folder.name) {
                    ForEach(chat.jauvexAgents.filter { $0.projectId == folder.id }) { agent in
                        Button(agent.title, systemImage: chat.jauvexAgent?.id == agent.id ? "checkmark" : "terminal") { speech.stop(); Task { await chat.openJauvex(agent) } }
                    }
                    Menu("새 에이전트") {
                        ForEach(JauvexProviders.all, id: \.self) { provider in
                            Button(JauvexProviders.label(provider)) { speech.stop(); Task { await chat.newJauvexAgent(in: folder, provider: provider) } }
                        }
                    }
                }
            }
            Button("에이전트 새로고침", systemImage: "arrow.clockwise") { Task { await chat.loadJauvex() } }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack {
                Circle().stroke(cyan.opacity(0.15), lineWidth: 1).frame(width: 160, height: 160)
                Circle().stroke(cyan.opacity(0.4), lineWidth: 2).frame(width: 130, height: 130)
                Image(systemName: "waveform").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(cyan)
            }.frame(maxWidth: .infinity).padding(.top, 24)
            Text("무엇을 도와드릴까요?").font(.title2.bold())
            Text("말하거나 입력하고, 사진으로 질문하세요.\n나만의 AI 비서와 하루를 시작하세요.").foregroundStyle(.secondary).lineSpacing(6)
            ForEach(["미리알림 오늘 할 일 정리", "알림 10분 후 물 마시기", "단축어 손전등 켜기"], id: \.self) { prompt in
                Button { chat.draft = prompt } label: {
                    HStack { Text(prompt).font(.subheadline); Spacer(); Image(systemName: "arrow.up.left") }
                        .padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }.foregroundStyle(.white)
            }
            Text("전송한 질문·사진·최근 대화는 Google Gemini에서 처리됩니다. 음성 인식은 Apple 서버를 사용할 수 있습니다.")
                .font(.caption2).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            if let data = chat.photo, let image = UIImage(data: data) {
                HStack {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("질문과 함께 전송할 사진").font(.caption)
                    Spacer()
                    Button { chat.photo = nil; selection = nil } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
            if speech.recording { Text("듣고 있습니다 · 마이크를 다시 누르면 종료").font(.caption).foregroundStyle(cyan) }
            if loadingPhoto { ProgressView("사진 준비 중…").font(.caption) }
            HStack(alignment: .bottom, spacing: 12) {
                PhotosPicker(selection: $selection, matching: .images) { Image(systemName: "plus.circle").font(.title2) }
                    .disabled(chat.busy || speech.recording || loadingPhoto || chat.jauvexAgent != nil).accessibilityLabel("사진 첨부")
                TextField(chat.jauvexAgent.map { "\($0.title)에게 말하기" } ?? "MARK에게 물어보세요", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...5).disabled((chat.busy && chat.jauvexAgent == nil) || speech.recording)
                Button {
                    if speech.recording { speech.stop() }
                    else { chat.stopSpeaking(); Task { await speech.start() } }
                } label: { Image(systemName: speech.recording ? "stop.circle.fill" : "mic").font(.title2).foregroundStyle(speech.recording ? .red : cyan) }
                    .disabled((chat.busy && chat.jauvexAgent == nil) || speech.starting).accessibilityLabel(speech.recording ? "녹음 종료" : "음성 입력")
                Button {
                    if chat.busy && !talksDuringTurn { chat.cancel() } else { speech.stop(); chat.send() }
                } label: { Image(systemName: chat.busy && !talksDuringTurn ? "stop.fill" : "arrow.up").font(.headline).frame(width: 36, height: 36).background(cyan, in: Circle()).foregroundStyle(.black) }
                    .disabled(!chat.busy && (speech.recording || speech.starting || loadingPhoto || (chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.photo == nil)))
                    .accessibilityLabel(chat.busy && !talksDuringTurn ? "요청 중지" : "전송")
            }
        }.padding(16).background(Color.white.opacity(0.04))
    }
    /// A Jauvex agent at work takes what is said next (Jauvex steers it in, queues it or stops the turn): the button sends it.
    private var talksDuringTurn: Bool { chat.jauvexAgent != nil && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @MainActor private func loadPhoto() async {
        guard let selection else { return }
        loadingPhoto = true
        defer { loadingPhoto = false }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw AppFailure(message: "사진을 읽을 수 없습니다.") }
            try Task.checkCancellation()
            let scale = min(1, 1600 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw AppFailure(message: "사진을 변환하지 못했습니다.") }
            chat.photo = jpeg
        } catch { if !Task.isCancelled { chat.error = error.localizedDescription } }
    }
}
