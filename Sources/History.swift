import SwiftUI

struct BranchesView: View {
    let repo: Repo
    @State private var items: [GHBranch] = []
    @State private var error: String?
    @State private var loading = true
    @State private var newName = ""
    @State private var info: String?

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if let info { Text(info).foregroundStyle(.secondary) }
            if repo.canPush {
                Section("从 \(repo.branch) 新建") {
                    TextField("新分支名", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("创建") { Task { await create() } }.disabled(newName.isEmpty)
                }
            }
            if loading && items.isEmpty { ProgressView() }
            ForEach(items) { b in
                HStack {
                    VStack(alignment: .leading) {
                        Text(b.name).font(.body)
                        if b.name == repo.defaultBranch { Text("默认分支").font(.caption).foregroundStyle(.secondary) }
                        if b.protected { Text("受保护").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    NavigationLink { FilesView(repo: repo, path: "", ref: b.name) } label: { Image(systemName: "folder") }
                        .accessibilityLabel("浏览文件")
                    NavigationLink { CommitsView(repo: repo, ref: b.name) } label: { Image(systemName: "clock") }
                        .accessibilityLabel("提交")
                }
                .swipeActions {
                    if repo.canPush && b.name != repo.defaultBranch {
                        Button("删除", role: .destructive) { Task { await remove(b) } }
                    }
                }
            }
        }
        .navigationTitle("分支")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = items.isEmpty
        do {
            items = try await API.shared.get("/repos/\(repo.fullName)/branches?per_page=100")
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }

    private func create() async {
        do {
            let ref: GitRef = try await API.shared.get("/repos/\(repo.fullName)/git/ref/heads/\(enc(repo.branch))")
            try await API.shared.post("/repos/\(repo.fullName)/git/refs", body: [
                "ref": "refs/heads/\(newName)",
                "sha": ref.object.sha
            ])
            newName = ""
            info = "已创建"
            await load()
        } catch { self.error = errText(error) }
    }

    private func remove(_ b: GHBranch) async {
        do {
            try await API.shared.delete("/repos/\(repo.fullName)/git/refs/heads/\(enc(b.name))")
            await load()
        } catch { self.error = errText(error) }
    }
}

struct TagsView: View {
    let repo: Repo
    @State private var tags: [GHTag] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if tags.isEmpty && error == nil { EmptyHint(title: "没有标签", systemImage: "tag") }
            ForEach(tags) { t in
                NavigationLink { CommitDetailView(repo: repo, sha: t.commit.sha) } label: {
                    VStack(alignment: .leading) {
                        Text(t.name).font(.body)
                        Text(String(t.commit.sha.prefix(7))).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("标签")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { tags = try await API.shared.get("/repos/\(repo.fullName)/tags?per_page=100") }
            catch { self.error = errText(error) }
        }
    }
}

struct CommitsView: View {
    let repo: Repo
    var ref: String
    var path: String? = nil
    @State private var items: [GHCommit] = []
    @State private var branch: String = ""
    @State private var page = 1
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await reload() } } }
            if loading && items.isEmpty { ProgressView() }
            ForEach(items) { c in
                NavigationLink { CommitDetailView(repo: repo, sha: c.sha) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.titleLine).font(.body).lineLimit(2)
                        Text("\(c.author?.login ?? c.commit.author?.name ?? "") · \(c.shortSha) · \(relTime(c.commit.author?.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if items.count >= page * 40 { Button("加载更多") { Task { await load(more: true) } } }
        }
        .navigationTitle(path == nil ? "提交" : "历史")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task {
            if branch.isEmpty { branch = ref }
            await reload()
        }
    }

    private func reload() async { page = 1; await load(more: false) }
    private func load(more: Bool) async {
        if !more { loading = items.isEmpty }
        let next = more ? page + 1 : 1
        var pathQ = "/repos/\(repo.fullName)/commits?sha=\(enc(branch.isEmpty ? ref : branch))&per_page=40&page=\(next)"
        if let path, !path.isEmpty { pathQ += "&path=\(enc(path))" }
        do {
            let part: [GHCommit] = try await API.shared.get(pathQ)
            if more { items += part } else { items = part }
            page = next
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}

struct CommitDetailView: View {
    let repo: Repo
    let sha: String
    @State private var detail: CommitDetail?
    @State private var status: CombinedStatus?
    @State private var checks: [CheckRun] = []
    @State private var error: String?
    @State private var comment = ""

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let d = detail {
                Section {
                    Text(d.commit.message).font(.body).textSelection(.enabled)
                    Text("\(d.author?.login ?? d.commit.author?.name ?? "") · \(String(d.sha.prefix(7))) · \(relTime(d.commit.author?.date))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = d.stats {
                        Text("+\(s.additions ?? 0)  −\(s.deletions ?? 0)")
                            .font(.caption.monospaced())
                    }
                    if let u = d.htmlUrl.flatMap(URL.init(string:)) { Link("在 Safari 中打开", destination: u) }
                }
                if status != nil || !checks.isEmpty {
                    Section("检查") {
                        if let status {
                            Text("综合状态：\(status.state ?? "")").font(.subheadline)
                            ForEach(status.statuses, id: \.stable) { s in
                                VStack(alignment: .leading) {
                                    Text(s.context ?? "状态").font(.subheadline)
                                    Text(s.state ?? "").font(.caption).foregroundStyle(.secondary)
                                    if let t = s.targetUrl, let u = URL(string: t) { Link("详情", destination: u).font(.caption) }
                                }
                            }
                        }
                        ForEach(checks) { c in
                            VStack(alignment: .leading) {
                                Text(c.name).font(.subheadline)
                                Text("\(c.status ?? "") \(c.conclusion ?? "")").font(.caption).foregroundStyle(.secondary)
                                if let h = c.htmlUrl, let u = URL(string: h) { Link("打开", destination: u).font(.caption) }
                            }
                        }
                    }
                }
                Section("文件") {
                    ForEach(d.files ?? []) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.filename).font(.subheadline.monospaced())
                            Text("\(f.status ?? "")  +\(f.additions ?? 0) −\(f.deletions ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let patch = f.patch {
                                Text(String(patch.prefix(4000)))
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            NavigationLink("打开文件") {
                                FileView(
                                    repo: repo,
                                    item: ContentItem(name: (f.filename as NSString).lastPathComponent, path: f.filename, type: "file", size: nil, sha: nil, htmlUrl: nil, downloadUrl: nil),
                                    ref: sha
                                )
                            }
                        }
                    }
                }
                Section("评论") {
                    TextField("对这次提交说点什么", text: $comment, axis: .vertical)
                    Button("发送") { Task { await send(d.sha) } }.disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if error == nil { ProgressView() }
        }
        .navigationTitle(String(sha.prefix(7)))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            detail = try await API.shared.get("/repos/\(repo.fullName)/commits/\(sha)")
            status = try? await API.shared.get("/repos/\(repo.fullName)/commits/\(sha)/status")
            if let list: CheckRunList = try? await API.shared.get("/repos/\(repo.fullName)/commits/\(sha)/check-runs") {
                checks = list.checkRuns
            }
            error = nil
        } catch { self.error = errText(error) }
    }

    private func send(_ sha: String) async {
        do {
            try await API.shared.post("/repos/\(repo.fullName)/commits/\(sha)/comments", body: ["body": comment])
            comment = ""
            tapHaptic()
        } catch { self.error = errText(error) }
    }
}

struct CompareView: View {
    let repo: Repo
    @State private var base = ""
    @State private var head = ""
    @State private var result: CompareResult?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                TextField("基线，例如 main", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("比较，例如 feature", text: $head).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("对比") { Task { await run() } }.disabled(base.isEmpty || head.isEmpty || loading)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let r = result {
                Section {
                    Text("\(r.status ?? "") · 超前 \(r.aheadBy ?? 0) · 落后 \(r.behindBy ?? 0) · \(r.totalCommits ?? 0) 个提交")
                    if let u = r.htmlUrl.flatMap(URL.init(string:)) { Link("在网页查看", destination: u) }
                }
                Section("提交") {
                    ForEach(r.commits ?? []) { c in
                        NavigationLink { CommitDetailView(repo: repo, sha: c.sha) } label: {
                            Text(c.titleLine).lineLimit(2)
                        }
                    }
                }
                Section("文件") {
                    ForEach(r.files ?? []) { f in
                        VStack(alignment: .leading) {
                            Text(f.filename).font(.subheadline.monospaced())
                            Text("\(f.status ?? "") +\(f.additions ?? 0) −\(f.deletions ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("对比")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if base.isEmpty { base = repo.branch } }
    }

    private func run() async {
        loading = true
        error = nil
        do {
            result = try await API.shared.get("/repos/\(repo.fullName)/compare/\(enc(base))...\(enc(head))")
        } catch { self.error = errText(error) }
        loading = false
    }
}

struct BlameView: View {
    let repo: Repo
    let path: String
    var ref: String
    @State private var lines: [(Int, Int, String, String)] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if loading { ProgressView() }
            ForEach(lines.indices, id: \.self) { i in
                let row = lines[i]
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.0)–\(row.1)  \(row.2)")
                        .font(.caption.weight(.semibold))
                    Text(row.3).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .navigationTitle("追溯")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let parts = splitRepo(repo.fullName)
        let q = """
        query($owner: String!, $name: String!, $ref: String!, $path: String!) {
          repository(owner: $owner, name: $name) {
            object(expression: $ref) {
              ... on Commit {
                blame(path: $path) {
                  ranges {
                    startingLine
                    endingLine
                    commit { oid messageHeadline author { name user { login } } }
                  }
                }
              }
            }
        }
        }
        """
        do {
            let data = try await API.shared.gql(q, ["owner": parts.owner, "name": parts.name, "ref": ref, "path": path])
            let obj = ((data["repository"] as? [String: Any])?["object"] as? [String: Any])
            let blame = obj?["blame"] as? [String: Any]
            let ranges = blame?["ranges"] as? [Any] ?? []
            lines = ranges.compactMap { item in
                guard let o = item as? [String: Any] else { return nil }
                let start = o["startingLine"] as? Int ?? 0
                let end = o["endingLine"] as? Int ?? start
                let commit = o["commit"] as? [String: Any]
                let author = commit?["author"] as? [String: Any]
                let who = (author?["user"] as? [String: Any])?["login"] as? String ?? author?["name"] as? String ?? ""
                let msg = commit?["messageHeadline"] as? String ?? ""
                let oid = String((commit?["oid"] as? String ?? "").prefix(7))
                return (start, end, "\(who) \(oid)", msg)
            }
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}
