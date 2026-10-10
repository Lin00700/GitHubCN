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
        .tint(NeonTheme.cyan)
    }
}

// MARK: - Neon visual system

enum NeonTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.085)
    static let panel = Color(red: 0.075, green: 0.09, blue: 0.15)
    static let cyan = Color(red: 0.22, green: 0.92, blue: 0.96)
    static let violet = Color(red: 0.62, green: 0.38, blue: 1.0)
    static let green = Color(red: 0.25, green: 0.92, blue: 0.62)
}

struct NeonBackground: View {
    var body: some View {
        ZStack {
            NeonTheme.background.ignoresSafeArea()
            RadialGradient(colors: [NeonTheme.violet.opacity(0.22), .clear], center: .topTrailing, startRadius: 5, endRadius: 360)
                .ignoresSafeArea()
            RadialGradient(colors: [NeonTheme.cyan.opacity(0.10), .clear], center: .bottomLeading, startRadius: 5, endRadius: 320)
                .ignoresSafeArea()
        }
    }
}

struct NeonCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(LinearGradient(colors: [NeonTheme.panel.opacity(0.98), NeonTheme.panel.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.09), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var token = ""
    @State private var googleBusy = false
    @State private var googleMessage: String?

    var body: some View {
        ZStack {
            NeonBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 42)
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 25, weight: .black))
                            .foregroundStyle(NeonTheme.cyan)
                            .frame(width: 58, height: 58)
                            .background(NeonTheme.cyan.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("GITHUB CN").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(3).foregroundStyle(NeonTheme.cyan)
                            Text("开发者控制台").font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("代码 · 自动化 · AI").font(.system(size: 34, weight: .black, design: .rounded))
                        Text("把 GitHub 工作流装进口袋。随时管理仓库、追踪构建，并调用你自己的 AI 模型。")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.62)).lineSpacing(5)
                    }
                    NeonCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("安全连接 GitHub", systemImage: "lock.shield.fill").font(.headline).foregroundStyle(NeonTheme.cyan)
                            SecureField("粘贴 GitHub Personal Access Token", text: $token)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(14).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 13))
                            Text("令牌通过 HTTPS 请求 GitHub，并使用系统钥匙串保存。请勿将令牌发给他人。")
                                .font(.caption).foregroundStyle(.white.opacity(0.5))
                            Button {
                                Task { await app.login(token: token) }
                            } label: {
                                HStack {
                                    Spacer()
                                    if app.loading { ProgressView().tint(.black) }
                                    else { Text("连接 GitHub").fontWeight(.bold); Image(systemName: "arrow.up.right") }
                                    Spacer()
                                }
                                .padding(15).foregroundStyle(.black)
                                .background(LinearGradient(colors: [NeonTheme.cyan, NeonTheme.green], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.loading)
                            if let e = app.error { Text(e).font(.footnote).foregroundStyle(.red) }
                            HStack {
                                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                                Text("或使用其他账号").font(.caption).foregroundStyle(.white.opacity(0.45)).fixedSize()
                                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                            }.padding(.vertical, 2)
                            Button {
                                googleBusy = true
                                googleMessage = nil
                                Task {
                                    do {
                                        let profile = try await GoogleSignInManager.shared.signIn()
                                        googleMessage = "Google 已登录：\(profile.email ?? profile.name ?? "账号")。注意：GitHub 仓库操作仍需连接 GitHub。"
                                    } catch {
                                        googleMessage = error.localizedDescription
                                    }
                                    googleBusy = false
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if googleBusy { ProgressView().tint(.white) }
                                    else {
                                        Image(systemName: "g.circle.fill").font(.system(size: 22, weight: .semibold))
                                    }
                                    Text(googleBusy ? "正在连接 Google…" : "使用 Google 登录")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption.bold())
                                }
                                .foregroundStyle(.white).padding(15)
                                .frame(maxWidth: .infinity)
                                .background(.white.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }.disabled(googleBusy)
                            if let googleMessage {
                                Text(googleMessage).font(.caption).foregroundStyle(googleMessage.hasPrefix("Google 已登录") ? NeonTheme.green : .orange).fixedSize(horizontal: false, vertical: true)
                            }
                            if let u = URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,notifications,read:user&description=GitHubCN") {
                                Link(destination: u) { Label("创建 GitHub 访问令牌", systemImage: "arrow.up.right.square").font(.subheadline) }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        featurePill("仓库管理", "shippingbox")
                        featurePill("Actions", "bolt.fill")
                        featurePill("AI 接口", "sparkles")
                    }
                    Spacer(minLength: 30)
                }
                .padding(22)
            }
        }
    }

    private func featurePill(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(.white.opacity(0.06)).clipShape(Capsule())
    }
}

// MARK: - 主导航与工作台

struct MainTabs: View {
    @State private var selected = 0
    var body: some View {
        TabView(selection: $selected) {
            DashboardView(selectedTab: $selected).tabItem { Label("工作台", systemImage: "square.grid.2x2.fill") }.tag(0)
            ReposView().tabItem { Label("仓库", systemImage: "shippingbox.fill") }.tag(1)
            AIChatView().tabItem { Label("AI 助手", systemImage: "sparkles") }.tag(2)
            IssuesView().tabItem { Label("议题", systemImage: "checklist") }.tag(3)
            ActionsHubView().tabItem { Label("Actions", systemImage: "bolt.fill") }.tag(4)
            MoreHubView().tabItem { Label("更多", systemImage: "square.grid.3x3.fill") }.tag(5)
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @Binding var selectedTab: Int
    @State private var greeting = "准备好继续构建了吗？"

    var body: some View {
        NavigationView {
            ZStack {
                NeonBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DEVELOPER SPACE").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(2.5).foregroundStyle(NeonTheme.cyan)
                                Text("你好，\(app.user?.name ?? app.user?.login ?? "开发者")")
                                    .font(.system(size: 27, weight: .bold, design: .rounded))
                                Text(greeting).font(.subheadline).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            AsyncImage(url: URL(string: app.user?.avatarUrl ?? "")) { image in image.resizable().scaledToFill() } placeholder: {
                                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(NeonTheme.cyan.opacity(0.7))
                            }
                            .frame(width: 48, height: 48).clipShape(Circle())
                            .overlay(Circle().stroke(NeonTheme.cyan.opacity(0.6), lineWidth: 1.5))
                        }
                        NeonCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("GITHUB CONTROL CENTER").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(NeonTheme.cyan)
                                        Text("你的代码宇宙") .font(.title2.bold())
                                        Text("仓库、自动化和 AI，一屏掌控。") .font(.caption).foregroundStyle(.white.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "atom").font(.system(size: 42, weight: .light)).foregroundStyle(NeonTheme.violet)
                                }
                                HStack(spacing: 10) {
                                    Button { selectedTab = 1 } label: { dashboardAction("浏览仓库", icon: "shippingbox.fill", color: NeonTheme.cyan) }
                                    Button { selectedTab = 4 } label: { dashboardAction("运行记录", icon: "bolt.fill", color: NeonTheme.green) }
                                }
                            }
                        }
                        Text("快捷入口").font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            shortcut("AI 编程助手", detail: "解释代码 · 生成方案", icon: "sparkles", color: NeonTheme.violet) { selectedTab = 2 }
                            shortcut("仓库中心", detail: "浏览文件与 README", icon: "folder.fill", color: NeonTheme.cyan) { selectedTab = 1 }
                            shortcut("Issues / PR", detail: "跟踪协作与问题", icon: "arrow.triangle.pull", color: .orange) { selectedTab = 3 }
                            shortcut("Actions 构建", detail: "检查 IPA 构建记录", icon: "gearshape.2.fill", color: NeonTheme.green) { selectedTab = 4 }
                        }
                        NeonCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("推荐工作流", systemImage: "wand.and.stars").font(.headline)
                                recommendation("01", "让 AI 解释失败日志", "复制 Actions 错误日志到 AI 助手，获取排查步骤。")
                                recommendation("02", "构建前先检查变更", "先查看提交和差异，再触发构建，降低回归风险。")
                                recommendation("03", "保护 API 密钥", "不要把 GitHub Token 或 AI Key 写进源码和仓库。")
                            }
                        }
                        Text("GitHub 数据在打开相应页面后实时加载；AI 功能需先配置兼容接口。")
                            .font(.caption2).foregroundStyle(.white.opacity(0.38)).padding(.horizontal, 4)
                    }.padding(18)
                }
            }
            .navigationBarHidden(true)
        }.navigationViewStyle(.stack)
    }

    private func dashboardAction(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) { Image(systemName: icon); Text(title).font(.subheadline.bold()) }
            .frame(maxWidth: .infinity).padding(12).foregroundStyle(color)
            .background(color.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func shortcut(_ title: String, detail: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.system(size: 21, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 42, height: 42).background(color.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 13))
                Text(title).font(.headline).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.5)).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, minHeight: 118, alignment: .leading).padding(15)
                .background(NeonTheme.panel.opacity(0.9)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }

    private func recommendation(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.bold()).foregroundStyle(NeonTheme.cyan).padding(8).background(NeonTheme.cyan.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MoreHubView: View {
    var body: some View {
        NavigationView {
            ZStack {
                NeonBackground()
                List {
                    Section("协作") {
                        NavigationLink(destination: NotificationsView()) { Label("通知中心", systemImage: "bell.badge") }
                        NavigationLink(destination: SearchView()) { Label("搜索 GitHub", systemImage: "magnifyingglass") }
                        NavigationLink(destination: StarredView()) { Label("我的星标仓库", systemImage: "star.fill") }
                    }
                    Section("项目与账户") {
                        NavigationLink(destination: ReleasesHubView()) { Label("Releases 发布", systemImage: "tag.fill") }
                        NavigationLink(destination: MeView()) { Label("个人资料与设置", systemImage: "person.crop.circle") }
                    }
                    Section("小提示") {
                        Label("在 AI 设置里可配置不同厂商的兼容 API。", systemImage: "sparkles")
                        Label("高权限 Token 只给必要权限，避免泄露。", systemImage: "lock.shield")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("更多功能")
        }.navigationViewStyle(.stack)
    }
}

// 选择仓库后查看对应的 Actions / Releases，避免对某个固定仓库写死。
struct ActionsHubView: View {
    @State private var repos: [Repo] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var query = ""

    private var filtered: [Repo] {
        guard !query.isEmpty else { return repos }
        return repos.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationView {
            List {
                if let errorMsg = errorMsg { Text(errorMsg).foregroundStyle(.red).font(.footnote) }
                ForEach(filtered) { repo in
                    NavigationLink(destination: ActionsView(repo: repo)) { RepoRow(repo: repo) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NeonTheme.background)
            .overlay { if loading { ProgressView("正在加载仓库…") } else if repos.isEmpty && errorMsg == nil { Text("没有可用仓库").foregroundStyle(.secondary) } }
            .searchable(text: $query, prompt: "选择要查看构建的仓库")
            .navigationTitle("Actions 构建中心")
            .task { await load() }
            .refreshable { await load() }
        }.navigationViewStyle(.stack)
    }

    private func load() async {
        loading = true; errorMsg = nil
        do { repos = try await API.shared.get("/user/repos?sort=updated&per_page=100") }
        catch { errorMsg = errText(error) }
        loading = false
    }
}

struct ReleasesHubView: View {
    @State private var repos: [Repo] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var query = ""

    private var filtered: [Repo] {
        guard !query.isEmpty else { return repos }
        return repos.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationView {
            List {
                if let errorMsg = errorMsg { Text(errorMsg).foregroundStyle(.red).font(.footnote) }
                ForEach(filtered) { repo in
                    NavigationLink(destination: ReleasesView(repo: repo)) { RepoRow(repo: repo) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NeonTheme.background)
            .overlay { if loading { ProgressView("正在加载仓库…") } else if repos.isEmpty && errorMsg == nil { Text("没有可用仓库").foregroundStyle(.secondary) } }
            .searchable(text: $query, prompt: "选择要查看发行版的仓库")
            .navigationTitle("Releases 发布中心")
            .task { await load() }
            .refreshable { await load() }
        }.navigationViewStyle(.stack)
    }

    private func load() async {
        loading = true; errorMsg = nil
        do { repos = try await API.shared.get("/user/repos?sort=updated&per_page=100") }
        catch { errorMsg = errText(error) }
        loading = false
    }
}

// MARK: - 通知

struct NotificationsView: View {
    @State private var notes: [Note] = []
    @State private var loading = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            List {
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
                ForEach(notes) { n in
                    NavigationLink(destination: NoteLoader(note: n)) { NoteRow(note: n) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && notes.isEmpty {
                    ProgressView()
                } else if !loading && notes.isEmpty && errorMsg == nil {
                    Text("没有未读通知").foregroundColor(.secondary)
                }
            }
            .navigationTitle("通知")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("全部已读") { Task { await markAll() } }
                        .disabled(notes.isEmpty)
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private func load() async {
        loading = true
        errorMsg = nil
        do {
            let n: [Note] = try await API.shared.get("/notifications?per_page=50")
            notes = n
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }

    private func markAll() async {
        do {
            try await API.shared.post("/notifications", body: [:], method: "PUT")
            notes = []
        } catch {
            errorMsg = errText(error)
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(note.unread ? Color.blue : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Image(systemName: icon).foregroundColor(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.subject.title).font(.subheadline.bold()).lineLimit(2)
                Text("\(note.repository.fullName) · \(reasonText) · \(relTime(note.updatedAt))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var icon: String {
        switch note.subject.type {
        case "Issue": return "exclamationmark.circle"
        case "PullRequest": return "arrow.triangle.branch"
        case "Release": return "tag"
        case "CheckSuite": return "gearshape.2"
        default: return "bell"
        }
    }

    private var reasonText: String {
        switch note.reason {
        case "assign": return "指派给你"
        case "mention": return "提及了你"
        case "review_requested": return "请求你审阅"
        case "subscribed": return "你订阅的"
        case "author": return "你创建的"
        case "comment": return "有新评论"
        case "ci_activity": return "CI 动态"
        case "state_change": return "状态变更"
        case "team_mention": return "团队被提及"
        default: return note.reason
        }
    }
}

struct NoteLoader: View {
    let note: Note
    @State private var issue: Issue?
    @State private var errorMsg: String?

    var body: some View {
        Group {
            if let i = issue {
                IssueDetailView(repoFullName: note.repository.fullName, issue: i)
            } else if let e = errorMsg {
                VStack(spacing: 12) {
                    Text(e).foregroundColor(.secondary)
                    if let u = URL(string: "https://github.com/" + note.repository.fullName) {
                        Link("在 Safari 打开仓库", destination: u)
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard note.subject.type == "Issue" || note.subject.type == "PullRequest",
              let url = note.subject.url else {
            errorMsg = "此类通知暂不支持应用内查看（\(note.subject.type)）"
            return
        }
        do {
            let i: Issue = try await API.shared.get(url)
            issue = i
            _ = try? await API.shared.action("/notifications/threads/\(note.id)", method: "PATCH")
        } catch {
            errorMsg = errText(error)
        }
    }
}

// MARK: - 搜索

struct SearchView: View {
    @State private var query = ""
    @State private var results: [Repo] = []
    @State private var loading = false
    @State private var errorMsg: String?
    @State private var searched = false

    var body: some View {
        NavigationView {
            List {
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
                ForEach(results) { r in
                    NavigationLink(destination: RepoDetailView(repo: r)) { RepoRow(repo: r) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading {
                    ProgressView()
                } else if results.isEmpty {
                    Text(searched ? "没有找到仓库" : "输入关键词，搜索 GitHub 仓库")
                        .foregroundColor(.secondary)
                }
            }
            .searchable(text: $query, prompt: "搜索仓库，例如 sing-box")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("搜索")
        }
        .navigationViewStyle(.stack)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return }
        loading = true
        errorMsg = nil
        do {
            let r: RepoSearch = try await API.shared.get("/search/repositories?q=\(enc(q))&per_page=30")
            results = r.items
            searched = true
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}

// MARK: - 我的

struct MeView: View {
    @EnvironmentObject var app: AppState
    @State private var confirmLogout = false

    var body: some View {
        NavigationView {
            List {
                if let u = app.user {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: u.avatarUrl ?? "")) { img in
                            img.resizable()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(u.name ?? u.login).font(.title3.bold())
                            Text("@\(u.login)").foregroundColor(.secondary)
                            if let b = u.bio, !b.isEmpty {
                                Text(b).font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        statView("仓库", u.publicRepos ?? 0)
                        Spacer()
                        statView("关注者", u.followers ?? 0)
                        Spacer()
                        statView("正在关注", u.following ?? 0)
                    }
                    .padding(.vertical, 2)
                }
                Section {
                    NavigationLink(destination: StarredView()) {
                        Label("我的星标", systemImage: "star")
                    }
                    if let u = URL(string: "https://github.com") {
                        Link(destination: u) {
                            Label("在 Safari 中打开 GitHub", systemImage: "safari")
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("我的")
            .alert("退出登录？", isPresented: $confirmLogout) {
                Button("退出", role: .destructive) { app.logout() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会清除本机保存的令牌。")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func statView(_ title: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }
}

struct StarredView: View {
    @State private var repos: [Repo] = []
    @State private var loading = true
    @State private var errorMsg: String?

    var body: some View {
        List {
            if let e = errorMsg {
                Text(e).font(.footnote).foregroundColor(.red)
            }
            ForEach(repos) { r in
                NavigationLink(destination: RepoDetailView(repo: r)) { RepoRow(repo: r) }
            }
        }
        .listStyle(.plain)
        .overlay { if loading { ProgressView() } }
        .navigationTitle("我的星标")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let r: [Repo] = try await API.shared.get("/user/starred?per_page=100")
            repos = r
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}
