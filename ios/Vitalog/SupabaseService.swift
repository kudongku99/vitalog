import Foundation
import Supabase

enum AppConfig {
    static var supabaseURL: URL {
        URL(string: Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "")!
    }

    static var publishableKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String ?? ""
    }
}

let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.publishableKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
    )
)
