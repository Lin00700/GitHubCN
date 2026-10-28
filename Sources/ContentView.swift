import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scene

    var body: some View {
        Group {
            if app.loggedIn {
                MainTabs()
            } else {
                LoginView()
            }
        }
        .environmentObject(app)
        .onChange(of: scene) { phase in
            if phase == .active, app.loggedIn {
                Task { await app.refreshUnread() }
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var device = DeviceLogin()
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GitHub 中文")
                            .font(.largeTitle.bold())
                        Text("仓库、问题、拉取请求、Actions 和动态。界面为简体中文，支持翻译和 AI 助手。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    TextField("OAuth App Client ID", text: $device.clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let c = device.userCode {
                        Text(c)
                            .font(.title2.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                    }
                    if let s = device.status {
                        Text(s).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        device.start(app: app)
                    } label: {
                        HStack {
                            if device.running { ProgressView() }
                            Text("使用 GitHub 登录")
                        }
                    }
                    .disabled(device.running)
                    if device.running {
                        Button("取消", role: .cancel) { device.cancel() }
                    }
                } header: {
                    Text("网页登录")
                } footer: {
                    Text("在 GitHub 官方页面登录（可选 Continue with Google）。OAuth App 需要启用 Device Flow。")
                }

                Section {
                    SecureField("ghp_… 或 github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await app.login(token: token) }
                    } label: {
                        HStack {
                            if app.loading { ProgressView() }
                            Text("使用令牌登录")
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || app.loading)
                } header: {
                    Text("个人访问令牌")
                } footer: {
                    Text("令牌只保存在本机钥匙串。建议范围：repo、workflow、gist、notifications、user、project、read:org。代码空间、软件包和安全警报还需要 codespace、read:packages、security_events。")
                }

                Section {
                    if let u = URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,gist,notifications,user,project,read:org&description=GitHubCN") {
                        Link("创建个人访问令牌", destination: u)
                    }
                    if let u = URL(string: "https://github.com/settings/applications/new") {
                        Link("创建 OAuth App", destination: u)
                    }
                }

                if let e = app.error {
                    Section {
                        Text(e).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $device.showBrowser) {
            if let u = device.verificationURL {
                SafariView(url: u)
            }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("首页", systemImage: "house") }
            NavigationStack { InboxView() }
                .badge(app.unreadCount)
                .tabItem { Label("通知", systemImage: "bell") }
            NavigationStack { ExploreView() }
                .tabItem { Label("探索", systemImage: "magnifyingglass") }
            NavigationStack { ProfileView() }
                .tabItem { Label("我的", systemImage: "person") }
        }
    }
}
