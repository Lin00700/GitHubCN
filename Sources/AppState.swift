import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var loggedIn = false
    @Published var user: GHUser?
    @Published var loading = false
    @Published var error: String?
    @Published var unreadCount = 0

    init() {
        if let t = Keychain.load(), !t.isEmpty {
            API.shared.token = t
            loggedIn = true
            Task {
                await refreshUser()
                await refreshUnread()
            }
        }
    }

    func refreshUnread() async {
        guard loggedIn else { unreadCount = 0; return }
        if let notes: [Note] = try? await API.shared.get("/notifications?per_page=50") {
            unreadCount = notes.count
        }
    }

    func refreshUser() async {
        do {
            let u: GHUser = try await API.shared.get("/user")
            user = u
        } catch {
            if case APIError.http(401, _) = error { logout() }
        }
    }

    func login(token: String) async {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        self.error = nil
        API.shared.token = t
        do {
            let u: GHUser = try await API.shared.get("/user")
            Keychain.save(t)
            user = u
            loggedIn = true
            await refreshUnread()
        } catch {
            API.shared.token = ""
            self.error = errText(error) ?? "登录失败"
        }
        loading = false
    }

    func logout() {
        Keychain.delete()
        API.shared.token = ""
        user = nil
        loggedIn = false
        unreadCount = 0
    }
}
