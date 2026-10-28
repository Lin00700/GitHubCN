import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var events: [GHEvent] = []
    @State private var mine = false
    @State private var loading = false
    @State private var error: String?
    @State private var page = 1
    @State private var showNewRepo = false
    @State private var showNewGist = false
    @State private var invites: [RepoInvite] = []

    var body: some View {
        List {
            if !invites.isEmpty {
                Section("仓库邀请") {
                    ForEach(invites) { inv in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(inv.repository.fullName).font(.headline)
                            Text(inv.permissions ?? "权限未知").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("接受") { Task { await answer(inv, accept: true) } }
                                Button("拒绝", role: .destructive) { Task { await answer(inv, accept: false) } }
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink { MyReposView() } label: { Label("我的仓库", systemImage: "book.closed") }
                NavigationLink { MyWorkView(kind: .issue) } label: { Label("所有问题", systemImage: "exclamationmark.circle") }
                NavigationLink { MyWorkView(kind: .pull) } label: { Label("所有拉取请求", systemImage: "arrow.triangle.branch") }
                NavigationLink { StarredReposView() } label: { Label("星标", systemImage: "star") }
                NavigationLink { GistListView(login: nil) } label: { Label("Gist", systemImage: "note.text") }
                NavigationLink { OrgListView() } label: { Label("组织", systemImage: "building.2") }
                NavigationLink { ProjectListView(scope: .me) } label: { Label("项目", systemImage: "square.grid.2x2") }
                NavigationLink { CodespaceListView() } label: { Label("代码空间", systemImage: "laptopcomputer") }
                NavigationLink { PackageListView() } label: { Label("软件包", systemImage: "shippingbox") }
                NavigationLink { AIChatView() } label: { Label("AI 助手", systemImage: "sparkles") }
            }

            Section {
                Picker("动态", selection: $mine) {
                    Text("关注").tag(false)
                    Text("我的").tag(true)
                }
                .pickerStyle(.segmented)
                if let error { InlineError(message: error) { Task { await reload() } } }
                if loading && events.isEmpty { ProgressView() }
                if !loading && events.isEmpty && error == nil {
                    EmptyHint(title: "没有动态", systemImage: "dot.radiowaves.left.and.right", message: "关注别人或推送代码后会出现在这里。")
                }
                ForEach(events) { e in
                    EventLink(event: e)
                }
                if events.count >= page * 30 {
                    Button("加载更多") { Task { await load(more: true) } }
                }
            } header: {
                Text("动态")
            }
        }
        .navigationTitle(greeting)
        .refreshable { await reload() }
        .task { await reload() }
        .onChange(of: mine) { _ in Task { await reload() } }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showNewRepo = true } label: { Label("新建仓库", systemImage: "plus.rectangle.on.folder") }
                    Button { showNewGist = true } label: { Label("新建 Gist", systemImage: "note.text") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建")
            }
        }
        .sheet(isPresented: $showNewRepo) {
            NavigationStack { NewRepoView(onCreated: { Task { await reload() } }) }
        }
        .sheet(isPresented: $showNewGist) {
            NavigationStack { NewGistView(onCreated: {}) }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let name = app.user?.name ?? app.user?.login ?? ""
        let hello: String
        if h < 6 { hello = "夜深了" }
        else if h < 12 { hello = "早上好" }
        else if h < 18 { hello = "下午好" }
        else { hello = "晚上好" }
        return name.isEmpty ? hello : "\(hello)，\(name)"
    }

    private func reload() async {
        page = 1
        await load(more: false)
        await app.refreshUnread()
        invites = (try? await API.shared.get("/user/repository_invitations")) ?? []
    }

    private func load(more: Bool) async {
        if !more { loading = events.isEmpty }
        error = nil
        let next = more ? page + 1 : 1
        guard let login = app.user?.login else { loading = false; return }
        let path = mine
            ? "/users/\(login)/events?per_page=30&page=\(next)"
            : "/users/\(login)/received_events?per_page=30&page=\(next)"
        do {
            let part: [GHEvent] = try await API.shared.get(path)
            if more { events += part } else { events = part }
            page = next
        } catch {
            if !more { self.error = errText(error) }
        }
        loading = false
    }

    private func answer(_ inv: RepoInvite, accept: Bool) async {
        do {
            if accept {
                try await API.shared.post("/user/repository_invitations/\(inv.id)", body: [:], method: "PATCH")
            } else {
                try await API.shared.delete("/user/repository_invitations/\(inv.id)")
            }
            invites.removeAll { $0.id == inv.id }
            tapHaptic()
        } catch {
            self.error = errText(error)
        }
    }
}
