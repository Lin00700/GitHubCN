import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()

    var body: some View {
        Group {
            if app.loggedIn {
                MainTabs().environmentObject(app)
            } else {
                LoginView().environmentObject(app)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var device = DeviceLogin()
    @State private var token = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.gradient)
                        .shadow(color: Theme.cyan.opacity(0.6), radius: 14)
                    Text("GitHub 中文")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.gradient)
                    Text("原生 · 翻译 · AI 助手")
                        .font(.subheadline)
                        .foregroundColor(Theme.textDim)
                }
                .padding(.top, 50)

                // Google / 网页登录
                VStack(alignment: .leading, spacing: 12) {
                    Label("Google / 网页登录", systemImage: "globe")
                        .font(.headline)
                    Text("通过 GitHub 官方登录页授权，页面上可以选择「Continue with Google」（需要你的 GitHub 账号已绑定 Google 邮箱）。首次使用需填入你自己创建的 OAuth App 的 Client ID，并在该 App 里勾选 Enable Device Flow。")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                    TextField("OAuth App Client ID", text: $device.clientID)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .neonField()
                    if let c = device.userCode {
                        Text(c)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.gradient)
                    }
                    if let s = device.status {
                        Text(s).font(.caption).foregroundColor(Theme.cyan)
                    }
                    Button {
                        device.start(app: app)
                    } label: {
                        HStack {
                            if device.running { ProgressView() }
                            Image(systemName: "g.circle.fill")
                            Text("使用 Google 登录")
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                    .disabled(device.running)
                    if device.running {
                        Button("取消") { device.cancel() }
                            .font(.footnote)
                    }
                    if let u = URL(string: "https://github.com/settings/applications/new") {
                        Link("去创建 OAuth App", destination: u).font(.footnote)
                    }
                }
                .neonCard()

                // 令牌登录
                VStack(alignment: .leading, spacing: 12) {
                    Label("使用个人访问令牌", systemImage: "key.horizontal")
                        .font(.headline)
                    Text("令牌只保存在本机钥匙串。创建时勾选 repo、workflow、notifications、read:user。")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                    SecureField("ghp_… 或 github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .neonField()
                    Button {
                        Task { await app.login(token: token) }
                    } label: {
                        HStack {
                            if app.loading { ProgressView() }
                            Text("登录")
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || app.loading)
                    if let u = URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,notifications,read:user&description=GitHubCN") {
                        Link("去 GitHub 创建令牌", destination: u).font(.footnote)
                    }
                }
                .neonCard()

                if let e = app.error {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
            }
            .padding()
        }
        .neonBackground()
        .sheet(isPresented: $device.showBrowser) {
            if let u = device.verificationURL {
                SafariView(url: u)
            }
        }
    }
}

// MARK: - 主界面

struct MainTabs: View {
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("工作台", systemImage: "square.grid.2x2") }
            ReposView().tabItem { Label("仓库", systemImage: "books.vertical") }
            IssuesView().tabItem { Label("议题", systemImage: "exclamationmark.circle") }
            NavigationView { AIChatView() }
                .navigationViewStyle(.stack)
                .tabItem { Label("AI", systemImage: "sparkles") }
            MeView().tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
