import Foundation

final class AIService {
    static let shared = AIService()
    private init() {}
    
    func queryAI(model: String, prompt: String, endpoint: String, customModel: String, apiKey: String) async throws -> String {
        if model == "自定义 AI (Custom API)" {
            guard let url = URL(string: endpoint) else {
                throw APIError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            let payload: [String: Any] = [
                "model": customModel,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw APIError.serverError(code)
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            } else {
                return "🔗 [自定义 API 返回成功，但未能解析标准 JSON 结构]"
            }
            
        } else {
            try await Task.sleep(nanoseconds: 800_000_000)
            switch model {
            case "OpenAI GPT-4o":
                return "🤖 [GPT-4o 分析回复]:\n针对您提出的问题「\(prompt)」，建议采用现代 Swift 异步并发与结构化错误捕获。"
            case "Claude 3.5 Sonnet":
                return "🧠 [Claude 3.5 Sonnet 深度审阅]:\n基于您的代码逻辑，建议强化类型安全与 Codable 容错。"
            case "Google Gemini 1.5 Pro":
                return "✨ [Gemini 1.5 Pro 智能建议]:\n代码结构非常清晰！建议对网络请求增加本地缓存双级支持。"
            default:
                return "💬 [AI 默认答复]: 已收到您的请求：「\(prompt)」。"
            }
        }
    }
}
