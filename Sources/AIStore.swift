import Foundation

// MARK: - 服务商配置

enum AIFormat: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic

    var id: String { rawValue }
    var label: String { self == .openai ? "OpenAI 兼容" : "Anthropic" }
}

struct AIProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    var format: AIFormat = .openai
}

struct AIPreset: Identifiable {
    let id = UUID()
    let name: String
    let baseURL: String
    let model: String
    let format: AIFormat
}

/// 预设只是填个起点，模型名可以随时改，也可以点「获取模型列表」
let aiPresets: [AIPreset] = [
    AIPreset(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", format: .openai),
    AIPreset(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", format: .openai),
    AIPreset(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "openai/gpt-4o-mini", format: .openai),
    AIPreset(name: "NVIDIA NIM", baseURL: "https://integrate.api.nvidia.com/v1", model: "meta/llama-3.1-70b-instruct", format: .openai),
    AIPreset(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen2.5-72B-Instruct", format: .openai),
    AIPreset(name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", format: .openai),
    AIPreset(name: "Moonshot Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", format: .openai),
    AIPreset(name: "阿里百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", format: .openai),
    AIPreset(name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-2.0-flash", format: .openai),
    AIPreset(name: "Anthropic Claude", baseURL: "https://api.anthropic.com", model: "claude-sonnet-5-5", format: .anthropic),
    AIPreset(name: "本地 Ollama", baseURL: "http://127.0.0.1:11434/v1", model: "llama3", format: .openai)
]

// MARK: - 存储（配置存 UserDefaults，API Key 存钥匙串）

final class AIStore: ObservableObject {
    static let shared = AIStore()

    @Published var profiles: [AIProfile] {
        didSet { persist() }
    }
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "ai_selected") }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "ai_profiles"),
           let list = try? JSONDecoder().decode([AIProfile].self, from: data) {
            profiles = list
        } else {
            profiles = []
        }
        if let s = UserDefaults.standard.string(forKey: "ai_selected") {
            selectedID = UUID(uuidString: s)
        } else {
            selectedID = nil
        }
    }

    var current: AIProfile? {
        profiles.first(where: { $0.id == selectedID }) ?? profiles.first
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "ai_profiles")
        }
    }

    private func account(_ p: AIProfile) -> String { "ai-" + p.id.uuidString }

    func key(for p: AIProfile) -> String {
        Keychain.load(account: account(p)) ?? ""
    }

    func setKey(_ k: String, for p: AIProfile) {
        Keychain.save(k, account: account(p))
    }

    func remove(_ p: AIProfile) {
        Keychain.delete(account: account(p))
        profiles.removeAll { $0.id == p.id }
        if selectedID == p.id { selectedID = profiles.first?.id }
    }
}

// MARK: - 请求

struct ChatMsg: Identifiable {
    let id = UUID()
    var role: String
    var content: String
}

enum AIError: LocalizedError {
    case badURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "接口地址无效，请检查 API 地址"
        case .http(let code, let msg): return "AI 服务返回 \(code)：\(msg)"
        }
    }
}

enum AIClient {
    /// 去掉用户可能多填的 /chat/completions、/messages，统一成根地址
    static func root(_ p: AIProfile) -> String {
        var base = p.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        for suffix in ["/chat/completions", "/messages", "/completions"] {
            if base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)) }
        }
        while base.hasSuffix("/") { base.removeLast() }
        if p.format == .anthropic && !base.hasSuffix("/v1") { base += "/v1" }
        return base
    }

    private static func applyAuth(_ req: inout URLRequest, _ p: AIProfile, _ key: String) {
        switch p.format {
        case .openai:
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    static func extractMessage(_ text: String) -> String {
        if let d = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = obj["message"] as? String { return m }
            if let e = obj["error"] as? String { return e }
        }
        return String(text.prefix(200))
    }

    static func listModels(profile p: AIProfile, key: String) async throws -> [String] {
        guard let url = URL(string: root(p) + "/models") else { throw AIError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        applyAuth(&req, p, key)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, extractMessage(String(data: data, encoding: .utf8) ?? ""))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["id"] as? String }.sorted()
    }

    /// 流式对话，每收到一段文字就回调一次（回调在主线程）
    static func stream(profile p: AIProfile, key: String, messages: [ChatMsg], system: String?,
                       onDelta: @MainActor @Sendable (String) -> Void) async throws {
        guard let url = URL(string: root(p) + (p.format == .openai ? "/chat/completions" : "/messages")) else {
            throw AIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req, p, key)

        var body: [String: Any] = ["model": p.model, "stream": true]
        let history: [[String: String]] = messages.map { ["role": $0.role, "content": $0.content] }
        switch p.format {
        case .openai:
            var msgs: [[String: String]] = []
            if let s = system, !s.isEmpty { msgs.append(["role": "system", "content": s]) }
            msgs += history
            body["messages"] = msgs
        case .anthropic:
            body["max_tokens"] = 4096
            if let s = system, !s.isEmpty { body["system"] = s }
            body["messages"] = history
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var text = ""
            for try await line in bytes.lines {
                text += line
                if text.count > 800 { break }
            }
            throw AIError.http(http.statusCode, extractMessage(text))
        }

        var got = false
        var raw = ""
        for try await line in bytes.lines {
            if raw.count < 20_000 { raw += line }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let piece = deltaText(obj, p.format), !piece.isEmpty {
                got = true
                await onDelta(piece)
            }
        }
        // 有些服务忽略 stream，直接返回完整 JSON
        if !got,
           let d = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let full = fullText(obj, p.format), !full.isEmpty {
            await onDelta(full)
        }
    }

    private static func deltaText(_ obj: [String: Any], _ f: AIFormat) -> String? {
        switch f {
        case .openai:
            guard let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        case .anthropic:
            guard (obj["type"] as? String) == "content_block_delta",
                  let delta = obj["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
    }

    private static func fullText(_ obj: [String: Any], _ f: AIFormat) -> String? {
        switch f {
        case .openai:
            guard let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any] else { return nil }
            return msg["content"] as? String
        case .anthropic:
            guard let content = obj["content"] as? [[String: Any]],
                  let first = content.first else { return nil }
            return first["text"] as? String
        }
    }
}
