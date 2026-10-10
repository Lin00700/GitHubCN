import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()

    var body: some View {
        if app.loggedIn {
            MainTabs().environmentObject(app)
        } else {
            LoginView().environmentObject(app)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var token = ""

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("使用个人访问令牌登录"),
                    footer: Text("令牌只保存在本机钥匙串里。创建时勾选 repo、workflow、notifications、read:user 权限。")
                ) {
                    SecureField("ghp_… 或 github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section {
                    Button {
                        Task { await app.login(token: token) }
                    } label: {
                        if app.loading { ProgressView() } else { Text("登录") }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || app.loading)

                    if let u = URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,notifications,read:user&description=GitHubCN") {
                        Link("去 GitHub 创建令牌", destination: u)
                    }
                }
                if let e = app.error {
                    Section { Text(e).foregroundColor(.red) }
                }
            }
            .navigationTitle("GitHub 中文")
        }
        .navigationViewStyle(.stack)
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            ReposView().tabItem { Label("仓库", systemImage: "books.vertical") }
            AIAssistantView().tabItem { Label("AI 助手", systemImage: "brain.head.profile") }
            IssuesView().tabItem { Label("议题", systemImage: "exclamationmark.circle") }
            NotificationsView().tabItem { Label("通知", systemImage: "bell") }
            MeView().tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .accentColor(.purple)
    }
}

struct AIAssistantView: View {
    @EnvironmentObject var app: AppState
    @State private var inputPrompt = ""
    
    let models = ["OpenAI GPT-4o", "Claude 3.5 Sonnet", "Google Gemini 1.5 Pro", "自定义 AI (Custom API)"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(models, id: \.self) { m in
                            Button {
                                app.selectedAIModel = m
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(app.selectedAIModel == m ? Color.purple : Color.gray)
                                        .frame(width: 8, height: 8)
                                    Text(m).font(.caption.bold())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(app.selectedAIModel == m ? Color.purple.opacity(0.15) : Color(.secondarySystemBackground))
                                .foregroundColor(app.selectedAIModel == m ? .purple : .primary)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding()
                }
                .background(.ultraThinMaterial)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(app.aiChatHistory) { msg in
                                HStack {
                                    if msg.role == "user" { Spacer() }
                                    VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
                                        Text(msg.role == "user" ? "我" : app.selectedAIModel)
                                            .font(.caption2.bold())
                                            .foregroundColor(.secondary)
                                        Text(msg.content)
                                            .font(.body)
                                            .padding(12)
                                            .background(msg.role == "user" ? Color.purple : Color(.secondarySystemBackground))
                                            .foregroundColor(msg.role == "user" ? .white : .primary)
                                            .cornerRadius(16)
                                    }
                                    if msg.role == "assistant" { Spacer() }
                                }
                                .id(msg.id)
                            }
                            if app.isAILoading {
                                HStack {
                                    ProgressView().padding().background(.ultraThinMaterial).cornerRadius(12)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: app.aiChatHistory.count) { _, _ in
                        if let last = app.aiChatHistory.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    TextField("向 AI 询问架构或重构方案...", text: $inputPrompt)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    
                    Button {
                        let text = inputPrompt
                        inputPrompt = ""
                        Task { await app.sendAIMessage(prompt: text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.purple)
                    }
                    .disabled(inputPrompt.trimmingCharacters(in: .whitespaces).isEmpty || app.isAILoading)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("AI 智能助手")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
