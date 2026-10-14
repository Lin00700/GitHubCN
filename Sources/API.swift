import Foundation
import Security
import SwiftUI

// MARK: - 错误

enum APIError: LocalizedError {
    case http(Int, String)
    case badURL

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg):
            if code == 401 { return "令牌无效或已过期，请重新登录" }
            if code == 404 { return "未找到，或没有权限访问（404）" }
            if code == 403 { return "没有权限或请求过于频繁（403）：\(msg)" }
            return "GitHub 返回 \(code)：\(msg)"
        case .badURL:
            return "地址无效"
        }
    }
}

func errText(_ e: Error) -> String? {
    if e is CancellationError { return nil }
    if (e as? URLError)?.code == .cancelled { return nil }
    return e.localizedDescription
}

// MARK: - 小工具

private let isoFormatter = ISO8601DateFormatter()

func relTime(_ iso: String?) -> String {
    guard let iso = iso, let d = isoFormatter.date(from: iso) else { return "" }
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

/// 用于查询参数
func enc(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

/// 用于路径（保留 /）
func encPath(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
}

func sizeText(_ n: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 钥匙串

enum Keychain {
    private static let service = "com.lin.githubcn"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func fallbackKey(_ account: String) -> String { "kc_fb_" + account }

    static func save(_ value: String, account: String = "token") {
        SecItemDelete(baseQuery(account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(account))
        if value.isEmpty { return }
        var q = baseQuery(account)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(value, forKey: fallbackKey(account))
        }
    }

    static func load(account: String = "token") -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let d = out as? Data,
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return UserDefaults.standard.string(forKey: fallbackKey(account))
    }

    static func delete(account: String = "token") {
        SecItemDelete(baseQuery(account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(account))
    }
}

// MARK: - 重定向捕获（下载构建产物用）

final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
    var location: URL?
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        location = request.url
        completionHandler(nil)
    }
}

// MARK: - API

final class API {
    static let shared = API()
    var token: String = ""

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private func request(_ path: String, method: String = "GET",
                         body: [String: Any]? = nil,
                         accept: String = "application/vnd.github+json") throws -> URLRequest {
        let urlString = path.hasPrefix("http") ? path : "https://api.github.com" + path
        guard let url = URL(string: urlString) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var msg = ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let m = obj["message"] as? String {
                msg = m
            }
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(try request(path))
        return try decoder.decode(T.self, from: data)
    }

    func raw(_ path: String) async throws -> String {
        let data = try await send(try request(path, accept: "application/vnd.github.raw+json"))
        return String(data: data, encoding: .utf8) ?? ""
    }

    func post(_ path: String, body: [String: Any], method: String = "POST") async throws {
        _ = try await send(try request(path, method: method, body: body))
    }

    func action(_ path: String, method: String) async throws {
        var req = try request(path, method: method)
        if method == "PUT" || method == "POST" {
            req.httpBody = Data()
            req.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        _ = try await send(req)
    }

    func exists(_ path: String) async -> Bool {
        do {
            let req = try request(path)
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                return http.statusCode == 204 || http.statusCode == 200
            }
        } catch {}
        return false
    }

    /// 带返回值的写请求（Git Data API 用）
    func write<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        let data = try await send(try request(path, method: method, body: body))
        return try decoder.decode(T.self, from: data)
    }

    /// 读取某个 job 的完整日志（会先 302 跳转到临时地址）
    func jobLog(repo: String, jobId: Int) async throws -> String {
        let req = try request("/repos/\(repo)/actions/jobs/\(jobId)/logs")
        let catcher = RedirectCatcher()
        let (data0, resp) = try await session.data(for: req, delegate: catcher)
        var target: URL? = catcher.location
        if let http = resp as? HTTPURLResponse {
            if http.statusCode >= 400 { throw APIError.http(http.statusCode, "日志不可用或已过期") }
            if target == nil, let l = http.value(forHTTPHeaderField: "Location") { target = URL(string: l) }
            if target == nil, (200..<300).contains(http.statusCode) {
                return String(data: data0, encoding: .utf8) ?? ""
            }
        }
        guard let loc = target else { throw APIError.http(0, "无法获取日志地址") }
        let (data, _) = try await URLSession.shared.data(from: loc)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: 下载

    func downloadArtifact(repo: String, id: Int, name: String) async throws -> URL {
        let req = try request("/repos/\(repo)/actions/artifacts/\(id)/zip")
        let catcher = RedirectCatcher()
        let (_, resp) = try await session.data(for: req, delegate: catcher)
        var target: URL? = catcher.location
        if let http = resp as? HTTPURLResponse {
            if http.statusCode >= 400 { throw APIError.http(http.statusCode, "构建产物不可用或已过期") }
            if target == nil, let l = http.value(forHTTPHeaderField: "Location") { target = URL(string: l) }
        }
        guard let location = target else { throw APIError.http(0, "无法获取下载地址") }
        let (tmp, resp2) = try await URLSession.shared.download(from: location)
        if let http = resp2 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, "下载失败")
        }
        return try moveToTemp(tmp, name: name + ".zip")
    }

    func downloadFile(_ urlString: String, name: String) async throws -> URL {
        guard let url = URL(string: urlString) else { throw APIError.badURL }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, "下载失败")
        }
        return try moveToTemp(tmp, name: name)
    }

    private func moveToTemp(_ tmp: URL, name: String) throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}
