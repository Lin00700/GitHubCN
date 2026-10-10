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

// MARK: - 登录

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

// MARK: - 主界面

struct MainTabs: View {
    var body: some View {
        TabView {
            ReposView().tabItem { Label("仓库", systemImage: "books.vertical") }
            IssuesView().tabItem { Label("议题", systemImage: "exclamationmark.circle") }
            NotificationsView().tabItem { Label("通知", systemImage: "bell") }
            SearchView().tabItem { Label("搜索", systemImage: "magnifyingglass") }
            MeView().tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
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
