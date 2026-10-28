import SwiftUI

struct MyReposView: View {
    var user: String? = nil
    @EnvironmentObject var app: AppState
    @State private var repos: [Repo] = []
    @State private var kind = "all"
    @State private var query = ""
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?
    @State private var showNew = false

    private var filtered: [Repo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return repos }
        return repos.filter {
            $0.fullName.localizedCaseInsensitiveContains(q)
                || ($0.description ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            if user == nil {
                Picker("范围", selection: $kind) {
                    Text("全部").tag("all")
                    Text("我拥有").tag("owner")
                    Text("我参与").tag("member")
                    Text("公开").tag("public")
                    Text("私有").tag("private")
                }
                .pickerStyle(.menu)
            }
            if let error { InlineError(message: error) { Task { await reload() } } }
            if loading && repos.isEmpty { ProgressView() }
            if !loading && filtered.isEmpty && error == nil {
                EmptyHint(title: "没有仓库", systemImage: "book.closed")
            }
            ForEach(filtered) { r in
                NavigationLink { RepoDetailView(repo: r) } label: { RepoRow(repo: r) }
                    .repoContext(r)
                    .swipeActions {
                        Button { Task { await toggleStar(r) } } label: { Label("星标", systemImage: "star") }
                            .tint(.yellow)
                    }
            }
            if repos.count >= page * 50 {
                Button("加载更多") { Task { await load(more: true) } }
            }
        }
        .navigationTitle(user == nil ? "仓库" : "\(user!) 的仓库")
        .navigationBarTitleDisplayMode(user == nil ? .large : .inline)
        .searchable(text: $query, prompt: "筛选仓库")
        .refreshable { await reload() }
        .task(id: kind) { await reload() }
        .toolbar {
            if user == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新建仓库")
                }
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { NewRepoView(onCreated: { Task { await reload() } }) }
        }
    }

    private func reload() async {
        page = 1
        await load(more: false)
    }

    private func load(more: Bool) async {
        if !more { loading = repos.isEmpty }
        error = nil
        let next = more ? page + 1 : 1
        let path: String
        if let user {
            path = "/users/\(enc(user))/repos?sort=updated&per_page=50&page=\(next)"
        } else {
            path = "/user/repos?sort=updated&per_page=50&page=\(next)&type=\(kind)"
        }
        do {
            let part: [Repo] = try await API.shared.get(path)
            if more { repos += part } else { repos = part }
            page = next
        } catch { self.error = errText(error) }
        loading = false
    }
}

enum WorkKind: String, Identifiable {
    case issue, pull
    var id: String { rawValue }
    var title: String { self == .issue ? "问题" : "拉取请求" }
    var isPR: Bool { self == .pull }
}

struct MyWorkView: View {
    let kind: WorkKind
    @EnvironmentObject var app: AppState
    @State private var filter = "involves"
    @State private var state = "open"
    @State private var items: [Issue] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Picker("关系", selection: $filter) {
                Text("涉及我").tag("involves")
                Text("我创建").tag("author")
                Text("指派给我").tag("assignee")
                Text("提及我").tag("mentions")
                if kind == .pull { Text("待我审阅").tag("review-requested") }
            }
            Picker("状态", selection: $state) {
                Text("打开").tag("open")
                Text("已关闭").tag("closed")
                Text("全部").tag("all")
            }
            .pickerStyle(.segmented)
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && items.isEmpty { ProgressView() }
            if !loading && items.isEmpty && error == nil {
                EmptyHint(title: "没有\(kind.title)", systemImage: kind == .issue ? "exclamationmark.circle" : "arrow.triangle.branch")
            }
            ForEach(items) { i in
                NavigationLink { IssueDetailView(repoFullName: i.repoFullName ?? "", issue: i) } label: {
                    IssueRow(issue: i, showRepo: true)
                }
            }
        }
        .navigationTitle(kind.title)
        .refreshable { await load() }
        .task(id: "\(filter)-\(state)-\(app.user?.login ?? "")") { await load() }
    }

    private func load() async {
        guard let login = app.user?.login else { return }
        loading = items.isEmpty
        error = nil
        let qual = kind == .issue ? "is:issue" : "is:pr"
        let who = filter == "review-requested" ? "review-requested:\(login)" : "\(filter):\(login)"
        let q = "\(who) \(qual) is:\(state)"
        do {
            let r: IssueSearch = try await API.shared.get("/search/issues?q=\(enc(q))&sort=updated&per_page=40")
            items = r.items
        } catch { self.error = errText(error) }
        loading = false
    }
}

struct StarredReposView: View {
    var login: String? = nil
    @State private var repos: [Repo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var page = 1

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await reload() } } }
            if loading && repos.isEmpty { ProgressView() }
            if !loading && repos.isEmpty && error == nil { EmptyHint(title: "没有星标", systemImage: "star") }
            ForEach(repos) { r in
                NavigationLink { RepoDetailView(repo: r) } label: { RepoRow(repo: r) }.repoContext(r)
            }
            if repos.count >= page * 50 {
                Button("加载更多") { Task { await load(more: true) } }
            }
        }
        .navigationTitle("星标")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async { page = 1; await load(more: false) }

    private func load(more: Bool) async {
        if !more { loading = repos.isEmpty }
        let next = more ? page + 1 : 1
        let path = login == nil
            ? "/user/starred?per_page=50&page=\(next)"
            : "/users/\(enc(login!))/starred?per_page=50&page=\(next)"
        do {
            let part: [Repo] = try await API.shared.get(path)
            if more { repos += part } else { repos = part }
            page = next
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}
