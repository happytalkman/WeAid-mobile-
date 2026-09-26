import SwiftUI
import EventKit
import EventKitUI
import MessageUI
import UserNotifications
import MapKit

struct DeviceDraft: Identifiable {
    let id = UUID()
    var kind: Kind = .reminder
    var text = ""
    var minutes = 10
    enum Kind: String, CaseIterable, Identifiable {
        case reminder = "미리 알림", calendar = "일정", notification = "예약 알림", phone = "전화", message = "문자", map = "지도", shortcut = "단축어"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .reminder: return "checklist"
            case .calendar: return "calendar"
            case .notification: return "bell.badge"
            case .phone: return "phone"
            case .message: return "message"
            case .map: return "map"
            case .shortcut: return "square.stack.3d.up"
            }
        }
    }
    static func parse(_ raw: String) -> DeviceDraft? {
        let aliases: [(String, Kind)] = [("미리 알림", .reminder), ("미리알림", .reminder), ("일정", .calendar), ("전화", .phone), ("문자", .message), ("지도", .map), ("단축어", .shortcut)]
        for (prefix, kind) in aliases where raw.hasPrefix(prefix + " ") || raw.hasPrefix(prefix + ":") {
            let text = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
            return DeviceDraft(kind: kind, text: text)
        }
        if let regex = try? NSRegularExpression(pattern: "^알림\\s+(\\d+)분\\s*후\\s+(.+)$"),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let n = Range(match.range(at: 1), in: raw), let body = Range(match.range(at: 2), in: raw),
           let minutes = Int(raw[n]), (1...10080).contains(minutes) {
            return DeviceDraft(kind: .notification, text: String(raw[body]), minutes: minutes)
        }
        return nil
    }
}

struct DeviceActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind: DeviceDraft.Kind
    @State private var text: String
    @State private var phone = ""
    @State private var date: Date
    @State private var hasDueDate = true
    @State private var status: String?
    @State private var busy = false
    @State private var showCalendar = false
    @State private var showMessage = false
    @State private var confirm = false
    @State private var saved = false
    private let store = EKEventStore()

    init(draft: DeviceDraft) {
        _kind = State(initialValue: draft.kind)
        _text = State(initialValue: draft.text)
        _date = State(initialValue: Date().addingTimeInterval(Double(draft.minutes) * 60))
    }
    private var titleLabel: String {
        switch kind {
        case .phone: return "전화번호를 직접 입력해 주세요"
        case .map: return "장소 또는 주소"
        case .shortcut: return "아이폰에 저장된 단축어의 정확한 이름"
        case .message: return "보낼 문자 내용"
        default: return "제목 또는 내용"
        }
    }
    private var cleanPhone: String { text.filter { "0123456789+".contains($0) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("실행할 기능", selection: $kind) {
                        ForEach(DeviceDraft.Kind.allCases) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
                    }
                    TextField(titleLabel, text: $text, axis: .vertical).lineLimit(2...4)
                    if kind == .message { TextField("받는 사람 전화번호", text: $phone).keyboardType(.phonePad) }
                    if kind == .reminder { Toggle("기한 지정", isOn: $hasDueDate) }
                    if kind == .calendar || kind == .notification || (kind == .reminder && hasDueDate) {
                        DatePicker("날짜와 시간", selection: $date)
                    }
                } header: { Label("아이폰에서 실행", systemImage: "iphone") }
                Section {
                    Button {
                        confirm = true
                    } label: {
                        HStack { Image(systemName: kind.symbol); Text(busy ? "처리 중…" : "내용 확인 후 실행") }
                    }.disabled(busy || saved || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
                    if saved { Button("새 작업 작성") { saved = false; status = nil; text = "" } }
                }
                if kind == .shortcut {
                    Section("단축어 연결 방법") {
                        Text("Apple 단축어 앱에서 원하는 동작을 만들고, 이 화면에 같은 이름을 입력하세요. 실행 여부와 권한은 단축어 앱에서 확인합니다.")
                        Text("예: ‘손전등 켜기’ → 손전등 설정\n‘밝기 50’ → 밝기 설정 50%\n‘음량 30’ → 음량 설정 30%\n‘카메라 열기’ → 앱 열기: 카메라")
                        Button("Apple 단축어 앱 열기") { launchURL(URL(string: "shortcuts://")!) }
                    }.font(.caption)
                }
                Section("지원하는 명령 예시") {
                    Text("미리알림 우유 사기\n일정 다음 회의\n알림 10분 후 물 마시기\n지도 강남역\n전화 01012345678\n문자 조금 늦겠습니다\n단축어 손전등 켜기")
                    Text("채팅창에 입력하거나 마이크로 말하면 이 확인 화면이 열립니다. 날짜·수신자 등 세부 정보는 여기에서 확인해 주세요. 위 형식의 기기 명령은 Gemini로 전송하지 않습니다.")
                }.font(.caption)
                Section {
                    Text("다른 앱의 화면을 자동으로 누르거나 잠금·보안 설정을 우회하지 않습니다. 문자 전송은 Apple 작성 화면에서 직접 확인합니다. 예약 알림은 시계 앱의 알람이 아니며 집중 모드와 알림 설정의 영향을 받습니다.")
                }.font(.caption)
            }
            .navigationTitle("아이폰 제어")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() }.disabled(busy) } }
            .confirmationDialog("\(kind.rawValue): \(text)", isPresented: $confirm, titleVisibility: .visible) {
                Button("실행") { Task { await execute() } }
                Button("취소", role: .cancel) {}
            } message: {
                Text((kind == .calendar || kind == .notification || (kind == .reminder && hasDueDate)) ? "시간: \(date.formatted(date: .abbreviated, time: .shortened))" : (kind == .message ? "받는 사람: \(phone)" : "입력한 내용을 확인해 주세요."))
            }
            .sheet(isPresented: $showCalendar) {
                CalendarEditor(title: text, date: date) { didSave in
                    showCalendar = false; saved = didSave
                    status = didSave ? "일정을 저장했습니다." : "일정 작성을 취소했습니다."
                }
            }
            .sheet(isPresented: $showMessage) {
                MessageEditor(recipient: phone, messageBody: text) { result in
                    showMessage = false
                    switch result {
                    case .sent: status = "메시지를 전송했습니다."; saved = true
                    case .cancelled: status = "메시지 작성을 취소했습니다."
                    default: status = "메시지를 전송하지 못했습니다."
                    }
                }
            }
            .onChange(of: kind) { _ in saved = false; status = nil }
            .onChange(of: text) { _ in saved = false }
        }
    }
    @MainActor private func execute() async {
        busy = true; status = nil
        defer { busy = false }
        do {
            switch kind {
            case .reminder:
                let allowed = try await store.requestFullAccessToReminders()
                guard allowed else { throw AppFailure(message: "설정에서 미리 알림 접근을 허용해 주세요.") }
                guard let calendar = store.defaultCalendarForNewReminders() else { throw AppFailure(message: "미리 알림 앱에 기본 목록을 먼저 만들어 주세요.") }
                let reminder = EKReminder(eventStore: store)
                reminder.title = text; reminder.calendar = calendar
                if hasDueDate {
                    var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    components.timeZone = TimeZone.current
                    reminder.dueDateComponents = components
                    reminder.addAlarm(EKAlarm(absoluteDate: date))
                }
                try store.save(reminder, commit: true)
                status = "미리 알림에 저장했습니다."; saved = true
            case .calendar: showCalendar = true
            case .notification:
                guard date.timeIntervalSinceNow > 1 else { throw AppFailure(message: "미래 시간을 선택해 주세요.") }
                let center = UNUserNotificationCenter.current()
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw AppFailure(message: "설정에서 MARK의 알림을 허용해 주세요.") }
                let content = UNMutableNotificationContent(); content.title = "MARK 알림"; content.body = text; content.sound = .default
                let request = UNNotificationRequest(identifier: "mark-" + UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
                try await center.add(request)
                status = "알림을 예약했습니다. \(date.formatted())"; saved = true
            case .phone:
                guard text.allSatisfy({ "0123456789+- ()".contains($0) }), cleanPhone.filter({ $0.isNumber }).count >= 3,
                      let url = URL(string: "tel:" + cleanPhone) else { throw AppFailure(message: "이름 대신 실제 전화번호를 입력해 주세요.") }
                launchURL(url)
            case .message:
                guard MFMessageComposeViewController.canSendText() else { throw AppFailure(message: "이 기기에서 문자 작성 기능을 사용할 수 없습니다.") }
                guard phone.filter({ $0.isNumber }).count >= 3, phone.allSatisfy({ "0123456789+- ()".contains($0) }) else { throw AppFailure(message: "받는 사람 전화번호를 확인해 주세요.") }
                showMessage = true
            case .map:
                var parts = URLComponents(string: "https://maps.apple.com/")!
                parts.queryItems = [URLQueryItem(name: "q", value: text)]
                if let url = parts.url { launchURL(url) }
            case .shortcut:
                var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"
                parts.queryItems = [URLQueryItem(name: "name", value: text.trimmingCharacters(in: .whitespacesAndNewlines))]
                if let url = parts.url { launchURL(url) }
            }
        } catch { status = error.localizedDescription }
    }
    private func launchURL(_ url: URL) {
        openURL(url) { accepted in
            status = accepted ? "실행 요청을 전달했습니다. 열린 앱에서 결과를 확인해 주세요." : "앱을 열 수 없습니다. 설치 여부와 설정을 확인해 주세요."
        }
    }
}

struct CalendarEditor: UIViewControllerRepresentable {
    let title: String
    let date: Date
    let completion: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        let store = EKEventStore()
        vc.eventStore = store
        let event = EKEvent(eventStore: store); event.title = title; event.startDate = date; event.endDate = date.addingTimeInterval(3600)
        vc.event = event; vc.editViewDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let completion: (Bool) -> Void
        init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { completion(action == .saved) }
    }
}

struct MessageEditor: UIViewControllerRepresentable {
    let recipient: String
    let messageBody: String
    let completion: (MessageComposeResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController(); vc.recipients = [recipient]; vc.body = messageBody; vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let completion: (MessageComposeResult) -> Void
        init(_ completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { completion(result) }
    }
}
