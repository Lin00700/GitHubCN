import SwiftUI

struct AIChatMessage: Identifiable, Codable {
    let id: UUID = UUID()
    let role: String
    let content: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var loggedIn = false
    @Published var user: GHUser?
    @Published var loading = false
    @Published var error: String?
    
    @Published var selectedAIModel: String = "OpenAI GPT-4o"
    @Published var aiChatHistory: [AIChatMessage] = [
        AIChatMessage(role: "assistant", content: "您好！我是您的专属 AI 开发助手。您可以在"我的"页面配置任意【自定义 AI 入口】或切换主流模型。")
    ]
    @Published var isAILoading = false
    @Published var customAPIEndpoint: String = "https://api.openai.com/v1/chat/completions"
    @Published var customModelName: String = "gpt-4o-mini"
    @Published var customAPIKey: String = ""

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
    
    func sendAIMessage(prompt: String) async {
        guard !prompt.isEmpty else { return }
        aiChatHistory.append(AIChatMessage(role: "user", content: prompt))
        isAILoading = true
        do {
            let res = try await AIService.shared.queryAI(
                model: selectedAIModel,
                prompt: prompt,
                endpoint: customAPIEndpoint,
                customModel: customModelName,
                apiKey: customAPIKey
            )
            aiChatHistory.append(AIChatMessage(role: "assistant", content: res))
        } catch {
            aiChatHistory.append(AIChatMessage(role: "assistant", content: "⚠️ AI 调用出错: \(error.localizedDescription)"))
        }
        isAILoading = false
    }
}
