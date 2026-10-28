import SwiftUI
import SafariServices

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int?
}

struct DeviceTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// GitHub Device Flow：在 GitHub 官方登录页完成登录（页面上可以选 Google），应用轮询拿到令牌
@MainActor
final class DeviceLogin: ObservableObject {
    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "gh_client_id") }
    }
    @Published var userCode: String?
    @Published var status: String?
    @Published var running = false
    @Published var showBrowser = false
    var verificationURL: URL?
    private var task: Task<Void, Never>?

    init() {
        clientID = UserDefaults.standard.string(forKey: "gh_client_id") ?? ""
    }

    func start(app: AppState) {
        let cid = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if cid.isEmpty {
            status = "请先填写 OAuth App 的 Client ID"
            return
        }
        running = true
        userCode = nil
        status = "正在请求验证码…"
        task = Task {
            do {
                let dc: DeviceCodeResponse = try await self.form(
                    "https://github.com/login/device/code",
                    ["client_id": cid, "scope": "repo workflow gist notifications user project read:org"]
                )
                self.userCode = dc.userCode
                UIPasteboard.general.string = dc.userCode
                self.verificationURL = URL(string: dc.verificationUri)
                self.status = "验证码已复制。在打开的页面里用 Google 或密码登录 GitHub，粘贴验证码并授权。"
                self.showBrowser = true

                let token = try await self.poll(cid, dc)
                self.showBrowser = false
                await app.login(token: token)
                if !app.loggedIn { self.status = app.error }
            } catch is DecodingError {
                self.status = "Client ID 无效，或该 OAuth App 没有启用 Device Flow"
            } catch {
                self.status = errText(error) ?? "已取消"
            }
            self.running = false
            self.showBrowser = false
        }
    }

    func cancel() {
        task?.cancel()
        running = false
        showBrowser = false
        userCode = nil
        status = nil
    }

    private func poll(_ cid: String, _ dc: DeviceCodeResponse) async throws -> String {
        var interval = max(dc.interval ?? 5, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(dc.expiresIn))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let r: DeviceTokenResponse = try await form(
                "https://github.com/login/oauth/access_token",
                [
                    "client_id": cid,
                    "device_code": dc.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )
            if let t = r.accessToken, !t.isEmpty { return t }
            switch r.error ?? "" {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "expired_token":
                throw APIError.http(0, "验证码已过期，请重试")
            case "access_denied":
                throw APIError.http(0, "你拒绝了授权")
            default:
                throw APIError.http(0, r.error ?? "未知错误")
            }
        }
        throw APIError.http(0, "等待超时，请重试")
    }

    private func form<T: Decodable>(_ url: String, _ params: [String: String]) async throws -> T {
        guard let u = URL(string: url) else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = params.map { "\($0.key)=\(enc($0.value))" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: data)
    }
}
