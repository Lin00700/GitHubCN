import SwiftUI

struct UserProfileView: View {
    let login: String
    @EnvironmentObject var app: AppState
    @State private var user: GHUser?
    @State private var following = false
    @State private var blocked = false
    @State private var error: String?
    @State private var readme: String?
    @State private var zh = false

    private var isMe: Bool { app.user?.login == login }

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if let u = user {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(url: u.avatarUrl, side: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.displayName).font(.title3.bold())
                            Text("@\(u.login)").foregroundStyle(.secondary)
                            if let c = u.company, !c.isEmpty { Label(c, systemImage: "building.2").font(.subheadline) }
                            if let loc = u.location, !loc.isEmpty { Label(loc, systemImage: "mappin.and.ellipse").font(.subheadline) }
                            if let b = u.blog, !b.isEmpty, let url = URL(string: b.contains("://") ? b : "https://\(b)") {
                                Link(b, destination: url).font(.subheadline)
                            }
                        }
                    }
                    if let bio = u.bio, !bio.isEmpty { Text(bio).font(.subheadline) }
                    HStack {
                        NavigationLink { FollowListView(login: login, followers: true) } label: { stat("关注者", u.followers ?? 0) }
                        NavigationLink { FollowListView(login: login, followers: false) } label: { stat("正在关注", u.following ?? 0) }
                        NavigationLink { MyReposView(user: login) } label: { stat("仓库", u.publicRepos ?? 0) }
                    }
                    .buttonStyle(.plain)
                    if !isMe {
                        Button(following ? "取消关注" : "关注") { Task { await toggleFollow() } }
                            .buttonStyle(.borderedProminent)
                        Button(blocked ? "取消屏蔽" : "屏蔽", role: blocked ? nil : .destructive) { Task { await toggleBlock() } }
                    }
                }
                Section {
                    NavigationLink { MyReposView(user: login) } label: { Label("仓库", systemImage: "book.closed") }
                    NavigationLink { StarredReposView(login: login) } label: { Label("星标", systemImage: "star") }
                    NavigationLink { GistListView(login: login) } label: { Label("Gist", systemImage: "note.text") }
                    NavigationLink { OrgListView(user: login) } label: { Label("组织", systemImage: "building.2") }
                    if let url = URL(string: u.htmlUrl ?? "https://github.com/\(login)") {
                        Link(destination: url) { Label("在 Safari 中打开", systemImage: "safari") }
                    }
                    if let url = URL(string: "https://github.com/sponsors/\(login)") {
                        Link(destination: url) { Label("赞助", systemImage: "heart") }
                    }
                }
                if let readme {
                    Section("简介仓库") {
                        TranslateBar(on: $zh)
                        TranslatableMarkdown(text: readme, translate: zh)
                    }
                }
            } else if error == nil {
                ProgressView()
            }
        }
        .navigationTitle(login)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func stat(_ t: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.headline)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        do {
            user = try await API.shared.get("/users/\(enc(login))")
            error = nil
        } catch { self.error = errText(error) }
        if !isMe {
            following = await API.shared.exists("/user/following/\(enc(login))")
            blocked = await API.shared.exists("/user/blocks/\(enc(login))")
        }
        readme = try? await API.shared.raw("/repos/\(enc(login))/\(enc(login))/readme")
        if readme?.isEmpty == true { readme = nil }
    }

    private func toggleFollow() async {
        do {
            try await API.shared.action("/user/following/\(enc(login))", method: following ? "DELETE" : "PUT")
            following.toggle()
            tapHaptic()
        } catch { self.error = errText(error) }
    }

    private func toggleBlock() async {
        do {
            try await API.shared.action("/user/blocks/\(enc(login))", method: blocked ? "DELETE" : "PUT")
            blocked.toggle()
            tapHaptic()
        } catch { self.error = errText(error) }
    }
}

struct FollowListView: View {
    let login: String
    let followers: Bool
    @State private var users: [GHUser] = []
    @State private var error: String?
    @State private var loading = true
    @State private var page = 1

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await reload() } } }
            if loading && users.isEmpty { ProgressView() }
            if !loading && users.isEmpty && error == nil { EmptyHint(title: followers ? "没有关注者" : "没有正在关注的人") }
            ForEach(users) { u in
                NavigationLink { UserProfileView(login: u.login) } label: { UserRow(user: u) }
            }
            if users.count >= page * 50 { Button("加载更多") { Task { await load(more: true) } } }
        }
        .navigationTitle(followers ? "关注者" : "正在关注")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async { page = 1; await load(more: false) }
    private func load(more: Bool) async {
        if !more { loading = users.isEmpty }
        let next = more ? page + 1 : 1
        let kind = followers ? "followers" : "following"
        do {
            let part: [GHUser] = try await API.shared.get("/users/\(enc(login))/\(kind)?per_page=50&page=\(next)")
            if more { users += part } else { users = part }
            page = next
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}

struct OrgListView: View {
    var user: String? = nil
    @State private var orgs: [Org] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && orgs.isEmpty { ProgressView() }
            if !loading && orgs.isEmpty && error == nil { EmptyHint(title: "没有组织", systemImage: "building.2") }
            ForEach(orgs) { o in
                NavigationLink { OrgDetailView(login: o.login) } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: o.avatarUrl, side: 36)
                        VStack(alignment: .leading) {
                            Text(o.login).font(.body)
                            if let d = o.description, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("组织")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = orgs.isEmpty
        let path = user == nil ? "/user/orgs?per_page=100" : "/users/\(enc(user!))/orgs?per_page=100"
        do { orgs = try await API.shared.get(path); error = nil }
        catch { self.error = errText(error) }
        loading = false
    }
}

struct OrgDetailView: View {
    let login: String
    @State private var org: Org?
    @State private var error: String?

    var body: some View {
        List {
            if let o = org {
                Section {
                    HStack(spacing: 12) {
                        AvatarView(url: o.avatarUrl, side: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(o.name ?? o.login).font(.title3.bold())
                            if let d = o.description { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                            if let loc = o.location { Text(loc).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section {
                    NavigationLink { OrgReposView(org: login) } label: { Label("仓库", systemImage: "book.closed") }
                    NavigationLink { OrgMembersView(org: login) } label: { Label("成员", systemImage: "person.3") }
                    NavigationLink { ProjectListView(scope: .org(login)) } label: { Label("项目", systemImage: "square.grid.2x2") }
                    if let u = URL(string: o.htmlUrl ?? "https://github.com/\(login)") {
                        Link(destination: u) { Label("在 Safari 中打开", systemImage: "safari") }
                    }
                }
            } else if let error {
                InlineError(message: error) { Task { await load() } }
            } else { ProgressView() }
        }
        .navigationTitle(login)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { org = try await API.shared.get("/orgs/\(enc(login))") }
        catch { self.error = errText(error) }
    }
}

struct OrgReposView: View {
    let org: String
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
        .navigationTitle("\(org) 的仓库")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }
    private func load() async {
        loading = repos.isEmpty
        do { repos = try await API.shared.get("/orgs/\(enc(org))/repos?sort=updated&per_page=50"); error = nil }
        catch { self.error = errText(error) }
        loading = false
    }
}

struct OrgMembersView: View {
    let org: String
    @State private var users: [GHUser] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(users) { u in
                NavigationLink { UserProfileView(login: u.login) } label: { UserRow(user: u) }
            }
        }
        .navigationTitle("成员")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { users = try await API.shared.get("/orgs/\(enc(org))/members?per_page=100") }
            catch { self.error = errText(error) }
        }
    }
}

struct GistListView: View {
    var login: String?
    @State private var mode = 0
    @State private var gists: [Gist] = []
    @State private var error: String?
    @State private var loading = true
    @State private var showNew = false

    var body: some View {
        List {
            if login == nil {
                Picker("范围", selection: $mode) {
                    Text("我的").tag(0)
                    Text("已加星").tag(1)
                    Text("公开").tag(2)
                }
                .pickerStyle(.segmented)
            }
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && gists.isEmpty { ProgressView() }
            if !loading && gists.isEmpty && error == nil { EmptyHint(title: "没有 Gist", systemImage: "note.text") }
            ForEach(gists) { g in
                NavigationLink { GistDetailView(id: g.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(g.description?.isEmpty == false ? g.description! : (g.files.keys.sorted().first ?? g.id))
                            .font(.body).lineLimit(2)
                        Text("\(g.files.count) 个文件 · \(g.isPublic ? "公开" : "私密") · \(relTime(g.updatedAt))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Gist")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: mode) { await load() }
        .toolbar {
            if login == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新建 Gist")
                }
            }
        }
        .sheet(isPresented: $showNew) { NavigationStack { NewGistView { Task { await load() } } } }
    }

    private func load() async {
        loading = gists.isEmpty
        let path: String
        if let login { path = "/users/\(enc(login))/gists?per_page=50" }
        else if mode == 1 { path = "/gists/starred?per_page=50" }
        else if mode == 2 { path = "/gists/public?per_page=30" }
        else { path = "/gists?per_page=50" }
        do { gists = try await API.shared.get(path); error = nil }
        catch { self.error = errText(error) }
        loading = false
    }
}

struct GistDetailView: View {
    let id: String
    @State private var gist: Gist?
    @State private var comments: [GistComment] = []
    @State private var starred = false
    @State private var text = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let g = gist {
                Section {
                    Text(g.description?.isEmpty == false ? g.description! : "Gist").font(.headline)
                    Text(g.isPublic ? "公开" : "私密").font(.caption).foregroundStyle(.secondary)
                    if let u = URL(string: g.htmlUrl) { Link("在 Safari 中打开", destination: u) }
                    Button(starred ? "取消星标" : "加星标") { Task { await toggleStar() } }
                    Button("删除", role: .destructive) { Task { await remove() } }
                }
                ForEach(g.files.keys.sorted(), id: \.self) { name in
                    if let f = g.files[name] {
                        Section(name) {
                            if let c = f.content, !c.isEmpty {
                                Text(String(c.prefix(20_000)))
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                            } else if let raw = f.rawUrl {
                                Text(raw).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("评论") {
                    ForEach(comments) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(c.user?.login ?? "") · \(relTime(c.createdAt))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(c.body ?? "").font(.body)
                        }
                    }
                    TextField("评论", text: $text, axis: .vertical)
                    Button("发送") { Task { await send() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if let error {
                InlineError(message: error) { Task { await load() } }
            } else { ProgressView() }
        }
        .navigationTitle("Gist")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            gist = try await API.shared.get("/gists/\(id)")
            comments = (try? await API.shared.get("/gists/\(id)/comments")) ?? []
            starred = await API.shared.exists("/gists/\(id)/star")
            error = nil
        } catch { self.error = errText(error) }
    }

    private func toggleStar() async {
        try? await API.shared.action("/gists/\(id)/star", method: starred ? "DELETE" : "PUT")
        starred.toggle()
    }

    private func send() async {
        do {
            try await API.shared.post("/gists/\(id)/comments", body: ["body": text])
            text = ""
            await load()
        } catch { self.error = errText(error) }
    }

    private func remove() async {
        do {
            try await API.shared.delete("/gists/\(id)")
            dismiss()
        } catch { self.error = errText(error) }
    }
}

struct NewGistView: View {
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "note.md"
    @State private var desc = ""
    @State private var content = ""
    @State private var isPublic = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("文件名", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("描述", text: $desc)
            Toggle("公开", isOn: $isPublic)
            TextField("内容", text: $content, axis: .vertical).lineLimit(8...20)
                .font(.system(.footnote, design: .monospaced))
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await create() } } label: {
                HStack { if busy { ProgressView() }; Text("创建") }
            }
            .disabled(busy || name.isEmpty || content.isEmpty)
        }
        .navigationTitle("新建 Gist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }

    private func create() async {
        busy = true
        error = nil
        do {
            let _: Gist = try await API.shared.write("/gists", method: "POST", body: [
                "description": desc,
                "public": isPublic,
                "files": [name: ["content": content]]
            ])
            onCreated()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}

struct CodespaceListView: View {
    @State private var items: [Codespace] = []
    @State private var error: String?
    @State private var loading = true
    @State private var busy: String?

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && items.isEmpty { ProgressView() }
            if !loading && items.isEmpty && error == nil {
                EmptyHint(title: "没有代码空间", systemImage: "laptopcomputer", message: "可以在仓库页创建。编辑器本身在浏览器里打开。")
            }
            ForEach(items) { c in
                VStack(alignment: .leading, spacing: 6) {
                    Text(c.displayName ?? c.name).font(.headline)
                    Text("\(c.repository?.fullName ?? "") · \(c.state ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    if let m = c.machine?.displayName { Text(m).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if busy == c.name { ProgressView() }
                        Button("启动") { Task { await act(c, "start") } }
                        Button("停止") { Task { await act(c, "stop") } }
                        if let s = c.webUrl, let u = URL(string: s) { Link("打开", destination: u) }
                        Button("删除", role: .destructive) { Task { await remove(c) } }
                    }
                    .font(.subheadline)
                    NavigationLink("端口") { CodespacePortsView(name: c.name) }
                }
            }
        }
        .navigationTitle("代码空间")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = items.isEmpty
        do {
            let r: CodespaceList = try await API.shared.get("/user/codespaces")
            items = r.codespaces
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }

    private func act(_ c: Codespace, _ op: String) async {
        busy = c.name
        do {
            try await API.shared.action("/user/codespaces/\(c.name)/\(op)", method: "POST")
            await load()
        } catch { self.error = errText(error) }
        busy = nil
    }

    private func remove(_ c: Codespace) async {
        do {
            try await API.shared.delete("/user/codespaces/\(c.name)")
            await load()
        } catch { self.error = errText(error) }
    }
}

struct CodespacePortsView: View {
    let name: String
    @State private var rows: [(String, String)] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.secondary) }
            if rows.isEmpty && error == nil { Text("没有转发端口").foregroundStyle(.secondary) }
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading) {
                    Text(row.0).font(.headline)
                    Text(row.1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("端口")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let any = try await API.shared.json("/user/codespaces/\(name)/ports")
                let list = (any as? [String: Any])?["ports"] as? [Any] ?? (any as? [Any] ?? [])
                rows = list.compactMap { item in
                    guard let o = item as? [String: Any] else { return nil }
                    let port = "\(o["port"] ?? "")"
                    let vis = o["visibility"] as? String ?? ""
                    let url = o["browse_url"] as? String ?? ""
                    return (port, "\(vis) \(url)")
                }
            } catch { self.error = errText(error) }
        }
    }
}

struct PackageListView: View {
    @State private var items: [GHPackage] = []
    @State private var error: String?
    @State private var loading = true
    private let types = ["container", "npm", "maven", "nuget", "rubygems"]

    var body: some View {
        List {
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if loading && items.isEmpty { ProgressView() }
            if !loading && items.isEmpty { EmptyHint(title: "没有软件包", systemImage: "shippingbox") }
            ForEach(items) { p in
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(.headline)
                    Text("\(p.packageType) · \(p.visibility ?? "") · \(relTime(p.createdAt))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = p.htmlUrl, let u = URL(string: s) { Link("打开", destination: u).font(.subheadline) }
                }
            }
        }
        .navigationTitle("软件包")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = items.isEmpty
        var all: [GHPackage] = []
        var last: String?
        for t in types {
            if let part: [GHPackage] = try? await API.shared.get("/user/packages?package_type=\(t)&per_page=30") {
                all += part
            } else {
                last = "部分类型需要 read:packages 权限"
            }
        }
        items = all
        error = all.isEmpty ? last : nil
        loading = false
    }
}

struct EmailListView: View {
    @State private var emails: [GHEmail] = []
    @State private var error: String?
    @State private var add = ""

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(emails) { e in
                VStack(alignment: .leading) {
                    Text(e.email).font(.body)
                    Text("\(e.primary ? "主要 · " : "")\(e.verified ? "已验证" : "未验证")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("删除", role: .destructive) { Task { await remove(e) } }
                }
            }
            Section("添加") {
                TextField("name@example.com", text: $add)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Button("添加") { Task { await addEmail() } }.disabled(add.isEmpty)
            }
        }
        .navigationTitle("邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { emails = try await API.shared.get("/user/emails") ; error = nil }
        catch { self.error = errText(error) }
    }
    private func addEmail() async {
        do {
            try await API.shared.post("/user/emails", body: ["emails": [add]])
            add = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ e: GHEmail) async {
        do {
            try await API.shared.delete("/user/emails", body: ["emails": [e.email]])
            await load()
        } catch { self.error = errText(error) }
    }
}

struct SSHKeyListView: View {
    @State private var keys: [SSHKey] = []
    @State private var title = ""
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            Section("已有密钥") {
                ForEach(keys) { k in
                    VStack(alignment: .leading) {
                        Text(k.title).font(.headline)
                        Text(k.key).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button("删除", role: .destructive) { Task { await remove(k) } } }
                }
            }
            Section("添加") {
                TextField("标题", text: $title)
                TextField("ssh-ed25519 …", text: $key, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") { Task { await add() } }.disabled(title.isEmpty || key.isEmpty)
            }
        }
        .navigationTitle("SSH 密钥")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { keys = try await API.shared.get("/user/keys"); error = nil }
        catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.post("/user/keys", body: ["title": title, "key": key])
            title = ""; key = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ k: SSHKey) async {
        do { try await API.shared.delete("/user/keys/\(k.id)"); await load() }
        catch { self.error = errText(error) }
    }
}

struct BlockListView: View {
    @State private var users: [GHUser] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if users.isEmpty && error == nil { EmptyHint(title: "没有屏蔽任何人") }
            ForEach(users) { u in
                HStack {
                    UserRow(user: u)
                    Spacer()
                    Button("解除") { Task { await unblock(u) } }
                }
            }
        }
        .navigationTitle("已屏蔽")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { users = try await API.shared.get("/user/blocks"); error = nil }
        catch { self.error = errText(error) }
    }
    private func unblock(_ u: GHUser) async {
        try? await API.shared.delete("/user/blocks/\(u.login)")
        await load()
    }
}

struct RateLimitView: View {
    @State private var rate: RateLimit?
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let r = rate {
                row("核心", r.resources.core)
                if let s = r.resources.search { row("搜索", s) }
                if let g = r.resources.graphql { row("GraphQL", g) }
            } else if error == nil { ProgressView() }
        }
        .navigationTitle("API 速率")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }
    private func row(_ title: String, _ r: RateResource) -> some View {
        let reset = Date(timeIntervalSince1970: TimeInterval(r.reset))
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text("剩余 \(r.remaining) / \(r.limit)")
            Text("重置 \(reset.formatted(date: .omitted, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func load() async {
        do { rate = try await API.shared.get("/rate_limit"); error = nil }
        catch { self.error = errText(error) }
    }
}

struct AdvisoryListView: View {
    @State private var items: [GlobalAdvisory] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && items.isEmpty { ProgressView() }
            ForEach(items) { a in
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.summary ?? a.ghsaId).font(.body).lineLimit(3)
                    Text("\(a.ghsaId) · \(a.severity ?? "") · \(relTime(a.publishedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = a.htmlUrl, let u = URL(string: s) { Link("详情", destination: u).font(.subheadline) }
                }
            }
        }
        .navigationTitle("安全公告")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }
    private func load() async {
        loading = items.isEmpty
        do { items = try await API.shared.get("/advisories?per_page=30"); error = nil }
        catch { self.error = errText(error) }
        loading = false
    }
}
