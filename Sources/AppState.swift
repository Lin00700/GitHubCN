import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var loggedIn = false
    @Published var user: GHUser?
    @Published var loading = false
    @Published var error: String?

    init() {
        if let t = Keychain.load(), !t.isEmpty {
            API.shared.token = t
            loggedIn = true
            Task { await refreshUser() }
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
    }
}
