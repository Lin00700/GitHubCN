import SwiftUI
import Combine
import GoogleSignIn

struct AIChatMessage: Identifiable, Codable {
    let id: UUID = UUID()
    let role: String
    let content: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var issues: [Issue] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = "swift"
    @Published var selectedSort: String = "stars"
    @Published var isDarkMode: Bool = true
    @Published var favorites: Set<Int> = []
    
    @Published var isAuthenticated: Bool = false
    @Published var userEmail: String? = nil
    @Published var userName: String? = nil
    @Published var userAvatarURL: String? = nil
    
    @Published var selectedAIModel: String = "OpenAI GPT-4o"
    @Published var aiChatHistory: [AIChatMessage] = [
        AIChatMessage(role: "assistant", content: "您好！我是您的专属 AI 开发助手。您可以在设置中切换内置模型或配置任意【自定义 AI 入口】。")
    ]
    @Published var isAILoading: Bool = false
    @Published var customAPIEndpoint: String = "https://api.openai.com/v1/chat/completions"
    @Published var customModelName: String = "gpt-4o-mini"
    @Published var customAPIKey: String = ""

    func checkExistingSession() {
        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                guard let self = self, let user = user else { return }
                self.isAuthenticated = true
                self.userEmail = user.profile?.email
                self.userName = user.profile?.name
                self.userAvatarURL = user.profile?.imageURL(withDimension: 200)?.absoluteString
            }
        }
    }
    
    func signInWithGoogle() async {
        isLoading = true
        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw APIError.invalidURL
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            let user = result.user
            self.isAuthenticated = true
            self.userEmail = user.profile?.email
            self.userName = user.profile?.name
            self.userAvatarURL = user.profile?.imageURL(withDimension: 200)?.absoluteString
        } catch {
            self.errorMessage = "登录失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isAuthenticated = false
        userEmail = nil
        userName = nil
        userAvatarURL = nil
    }
    
    func searchRepositories() async {
        guard !searchText.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            self.repositories = try await APIClient.shared.fetchRepositories(query: searchText, sort: selectedSort)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func toggleFavorite(for repoID: Int) {
        if favorites.contains(repoID) { favorites.remove(repoID) }
        else { favorites.insert(repoID) }
    }
    
    func sendAIMessage(prompt: String) async {
        guard !prompt.isEmpty else { return }
        let userMsg = AIChatMessage(role: "user", content: prompt)
        aiChatHistory.append(userMsg)
        isAILoading = true
        
        do {
            let aiResponse = try await AIService.shared.queryAI(
                model: selectedAIModel,
                prompt: prompt,
                endpoint: customAPIEndpoint,
                customModel: customModelName,
                apiKey: customAPIKey
            )
            let assistantMsg = AIChatMessage(role: "assistant", content: aiResponse)
            aiChatHistory.append(assistantMsg)
        } catch {
            let errorMsg = AIChatMessage(role: "assistant", content: "⚠️ AI 调用出错: \(error.localizedDescription)")
            aiChatHistory.append(errorMsg)
        }
        isAILoading = false
    }
}
