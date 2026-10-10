import Foundation

final class AIService {
    static let shared = AIService()
    private init() {}
    
    func queryAI(model: String, prompt: String, endpoint: String, customModel: String, apiKey: String) async throws -> String {
        if model == "自定义 AI (Custom API)" {
            guard let url = URL(string: endpoint) else { throw APIError.badURL }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            let payload: [String: Any] = [
                "model": customModel,
                "messages": [["role": "user", "content": prompt]]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode, "自定义 AI 接口请求失败")
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let msg = first["message"] as? [String: Any],
               let content = msg["content"] as? String {
                return content
            }
            return "🔗 [自定义 API 返回成功，但未能解析标准 JSON 格式]"
        } else {
            try await Task.sleep(nanoseconds: 600_000_000)
            return "🤖 [\(model) 智能洞察]:\n针对您的提问「\(prompt)」：代码结构非常规范！建议保持纯原生架构以确保持续通过 GitHub Actions 自签编译。"
        }
    }
}
