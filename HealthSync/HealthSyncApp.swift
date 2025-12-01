import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        if let app = FirebaseApp.app() {
            print("✅ Firebase configured")
            print("   projectID:", app.options.projectID ?? "nil")
            print("   apiKey:", app.options.apiKey ?? "nil")
            print("   bundleID:", Bundle.main.bundleIdentifier ?? "nil")
        } else {
            print("❌ FirebaseApp.app() is nil")
        }

        return true
    }
}

@main
struct HealthSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
    }
}
