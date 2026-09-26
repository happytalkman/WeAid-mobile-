import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}


@main
struct MarkMobileApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var delegate
    @StateObject private var chat = ChatStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(chat).preferredColorScheme(.dark) }
    }
}
