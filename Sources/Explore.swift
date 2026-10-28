import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case repos, users, issues, code, commits, topics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .repos: return "仓库"
        case .users: return "用户"
        case .issues: return "问题"
        case .code: return "代码"
        case .commits: return "提交"
        case .topics: return "主题"
        }
    }
}

struct ExploreView: View {
    @State private var query = ""
    @State private var scope: SearchScope = .repos
    @State private var days = 7
    @State private var repos: [Repo] = []
    @State private var users: [GHUser] = []
    @State private var issues: [Issue] = []
    @State private var code: [CodeHit] = []
    @State private var commits: [CommitHit] = []
    @State private var topics: [GHTopic] = []
    @State private var trending: [Repo] = []
    @State private var loading = false
    @State private var error: String?
    @State private var searched = false
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "recent_search") ?? []

    private let suggested = ["swift", "ios", "rust", "llm", "kubernetes", "typescript"]

    var body: some View {
        List {
            Picker("类型", selection: $scope) {
                ForEach(SearchScope.allCases) { s in Text(s.title).tag(s) }
            }
            .pickerStyle(.segmented)

            if let error { InlineError(message: error) { Task { await runSearch() } } }

            if query.trimmingCharacters(in: .whitespaces).isEmpty && !searched {
                if !recent.isEmpty {
                    Section("最近搜索") {
                        ForEach(recent, id: \.self) { q in
                            Button(q) { query = q; Task { await runSearch() } }
                        }
                    }
                }
                Section {
                    Picker("窗口", selection: $days) {
                        Text("今天").tag(1)
                        Text("本周").tag(7)
                        Text("本月").tag(30)
                    }
                    .pickerStyle(.segmented)
                    Text("GitHub 没有公开的热门趋势接口。这里按所选时间内新建、星标最多的仓库排序。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if loading && trending.isEmpty { ProgressView() }
                    ForEach(trending) { r in
                        NavigationLink { RepoDetailView(repo: r) } label: { RepoRow(repo: r) }
                            .repoContext(r)
                    }
                } header: {
                    Text("近期热门")
                }
                Section("主题") {
                    ForEach(suggested, id: \.self) { t in
                        NavigationLink {
                            TopicReposView(topic: t)
                        } label: {
                            Label(t, systemImage: "number")
                        }
                    }
                }
                Section("网站上的其他入口") {
                    Link("应用市场 Marketplace", destination: URL(string: "https://github.com/marketplace")!)
                    Link("MCP 注册表", destination: URL(string: "https://github.com/mcp")!)
                    Link("Copilot", destination: URL(string: "https://github.com/copilot")!)
                    Link("赞助 Sponsors", destination: URL(string: "https://github.com/sponsors")!)
                }
            } else {
                resultList
            }
        }
        .navigationTitle("探索")
        .searchable(text: $query, prompt: searchPrompt)
        .onSubmit(of: .search) { Task { await runSearch() } }
        .refreshable {
            if query.trimmingCharacters(in: .whitespaces).isEmpty { await loadTrending() }
            else { await runSearch() }
        }
        .task { await loadTrending() }
        .onChange(of: days) { _ in Task { await loadTrending() } }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("搜索") { Task { await runSearch() } }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var searchPrompt: String {
        switch scope {
        case .code: return "代码搜索，例如 repo:apple/swift language:swift"
        case .commits: return "提交搜索，例如 repo:golang/go fix"
        default: return "搜索 GitHub"
        }
    }

    @ViewBuilder private var resultList: some View {
        if loading { ProgressView() }
        switch scope {
        case .repos:
            if repos.isEmpty && searched { EmptyHint(title: "没有仓库") }
            ForEach(repos) { r in
                NavigationLink { RepoDetailView(repo: r) } label: { RepoRow(repo: r) }.repoContext(r)
            }
        case .users:
            if users.isEmpty && searched { EmptyHint(title: "没有用户") }
            ForEach(users) { u in
                NavigationLink { UserProfileView(login: u.login) } label: { UserRow(user: u) }
            }
        case .issues:
            if issues.isEmpty && searched { EmptyHint(title: "没有问题或拉取请求") }
            ForEach(issues) { i in
                NavigationLink { IssueDetailView(repoFullName: i.repoFullName ?? "", issue: i) } label: {
                    IssueRow(issue: i, showRepo: true)
                }
            }
        case .code:
            if code.isEmpty && searched { EmptyHint(title: "没有代码", message: "代码搜索通常需要限定词，例如 repo:owner/name 或 language:swift。") }
            ForEach(code) { c in
                NavigationLink {
                    FileView(
                        repo: c.repository,
                        item: ContentItem(name: c.name, path: c.path, type: "file", size: nil, sha: c.sha, htmlUrl: c.htmlUrl, downloadUrl: nil),
                        ref: c.repository.branch
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.path).font(.body).lineLimit(1)
                        Text(c.repository.fullName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case .commits:
            if commits.isEmpty && searched { EmptyHint(title: "没有提交") }
            ForEach(commits) { c in
                NavigationLink { CommitDetailView(repo: c.repository, sha: c.sha) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.commit.message.split(separator: "\n").first.map(String.init) ?? c.commit.message)
                            .font(.body).lineLimit(2)
                        Text("\(c.repository.fullName) · \(String(c.sha.prefix(7)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case .topics:
            if topics.isEmpty && searched { EmptyHint(title: "没有主题") }
            ForEach(topics) { t in
                NavigationLink { TopicReposView(topic: t.name) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.displayName ?? t.name).font(.headline)
                        if let d = t.shortDescription, !d.isEmpty {
                            Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func remember() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        recent.removeAll { $0 == q }
        recent.insert(q, at: 0)
        if recent.count > 8 { recent = Array(recent.prefix(8)) }
        UserDefaults.standard.set(recent, forKey: "recent_search")
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return }
        loading = true
        error = nil
        remember()
        do {
            switch scope {
            case .repos:
                let r: RepoSearch = try await API.shared.get("/search/repositories?q=\(enc(q))&per_page=30")
                repos = r.items
            case .users:
                let r: UserSearch = try await API.shared.get("/search/users?q=\(enc(q))&per_page=30")
                users = r.items
            case .issues:
                let r: IssueSearch = try await API.shared.get("/search/issues?q=\(enc(q))&sort=updated&per_page=30")
                issues = r.items
            case .code:
                let r: CodeSearch = try await API.shared.get("/search/code?q=\(enc(q))&per_page=20")
                code = r.items
            case .commits:
                let r: CommitSearch = try await API.shared.get("/search/commits?q=\(enc(q))&per_page=20")
                commits = r.items
            case .topics:
                let r: TopicSearch = try await API.shared.get("/search/topics?q=\(enc(q))&per_page=20")
                topics = r.items
            }
            searched = true
        } catch {
            self.error = errText(error)
        }
        loading = false
    }

    private func loadTrending() async {
        loading = trending.isEmpty
        let day = isoDay(daysAgo: days)
        let q = "created:>\(day)"
        do {
            let r: RepoSearch = try await API.shared.get("/search/repositories?q=\(enc(q))&sort=stars&order=desc&per_page=25")
            trending = r.items
            error = nil
        } catch {
            self.error = errText(error)
        }
        loading = false
    }
}

struct TopicReposView: View {
    let topic: String
    @State private var repos: [Repo] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && repos.isEmpty { ProgressView() }
            ForEach(repos) { r in
                NavigationLink { RepoDetailView(repo: r) } label: { RepoRow(repo: r) }.repoContext(r)
            }
        }
        .navigationTitle(topic)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = repos.isEmpty
        do {
            let r: RepoSearch = try await API.shared.get("/search/repositories?q=\(enc("topic:\(topic)"))&sort=stars&per_page=30")
            repos = r.items
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}

func isoDay(daysAgo: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
