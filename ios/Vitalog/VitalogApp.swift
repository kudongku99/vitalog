import SwiftUI

@main
struct VitalogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var isSignedIn: Bool?

    var body: some View {
        Group {
            switch isSignedIn {
            case .none:
                ProgressView()
            case .some(true):
                BackfillView()
            case .some(false):
                LoginView()
            }
        }
        .tint(Theme.accent)
        .task {
            for await (_, session) in supabase.auth.authStateChanges {
                isSignedIn = session != nil
            }
        }
    }
}
