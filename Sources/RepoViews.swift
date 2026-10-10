import SwiftUI

// MARK: - 仓库列表

struct RepoRow: View {
    let repo: Repo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock" : "book.closed")
                    .foregroundColor(.secondary)
                Text(repo.fullName).font(.headline).lineLimit(1)
            }
            if let d = repo.description, !d.isEmpty {
                Text(d).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
            }
            HStack(spacing: 12) {
                if let l = repo.language {
                    Text(l).font(.caption)
                }
                Label("\(repo.stargazersCount)", systemImage: "star").font(.caption)
                Label("\(repo.forksCount)", systemImage: "arrow.triangle.branch").font(.caption)
                Spacer()
                Text(relTime(repo.updatedAt)).font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct NewRepoView: View {
    var onCreated: () -> Void
    @Environment(\.presentationMode) private var mode
    @State private var name = ""
    @State private var desc = ""
    @State private var isPrivate = false
    @State private var addReadme = true
    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        Form {
            Section {
                TextField("仓库名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                TextField("描述（可选）", text: $desc)
                Toggle("私有仓库", isOn: $isPrivate)
                Toggle("添加 README", isOn: $addReadme)
            }
            if let e = errorMsg {
                Section { Text(e).foregroundColor(.red) }
            }
            Section {
                Button("创建仓库") { Task { await create() } }
                    .disabled(name.isEmpty || busy)
            }
        }
        .neonBackground()
        .navigationTitle("新建仓库")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() async {
        busy = true
        errorMsg = nil
        do {
            try await API.shared.post("/user/repos", body: [
                "name": name,
                "description": desc,
                "private": isPrivate,
                "auto_init": addReadme
            ])
            onCreated()
            mode.wrappedValue.dismiss()
        } catch {
            errorMsg = errText(error)
        }
        busy = false
    }
}

// MARK: - 仓库详情

struct RepoDetailView: View {
    let repo: Repo
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("简介").tag(0)
                Text("文件").tag(1)
                Text("议题").tag(2)
                Text("PR").tag(3)
                Text("构建").tag(4)
                Text("发行").tag(5)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                switch tab {
                case 0: RepoInfoView(repo: repo)
                case 1: FilesView(repo: repo, path: "", embedded: true)
                case 2: IssueListView(repoFullName: repo.fullName, pulls: false)
                case 3: IssueListView(repoFullName: repo.fullName, pulls: true)
                case 4: ActionsView(repo: repo)
                default: ReleasesView(repo: repo)
                }
            }
        }
        .neonBackground()
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let u = URL(string: repo.htmlUrl) {
                    Link(destination: u) { Image(systemName: "safari") }
                }
            }
        }
    }
}

struct RepoInfoView: View {
    let repo: Repo
    @State private var readme: String?
    @State private var loading = true
    @State private var starred = false
    @State private var zh = false
    @State private var errorMsg: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let d = repo.description, !d.isEmpty {
                    Text(d)
                }
                HStack(spacing: 16) {
                    Label("\(repo.stargazersCount)", systemImage: "star")
                    Label("\(repo.forksCount)", systemImage: "arrow.triangle.branch")
                    Label("\(repo.openIssuesCount)", systemImage: "exclamationmark.circle")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                HStack {
                    Button {
                        Task { await toggleStar() }
                    } label: {
                        Label(starred ? "取消星标" : "加星标", systemImage: starred ? "star.fill" : "star")
                    }
                    .buttonStyle(.bordered)
                    if let u = URL(string: "\(repo.htmlUrl)/archive/refs/heads/\(repo.defaultBranch ?? "main").zip") {
                        Link(destination: u) {
                            Label("下载 ZIP", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }

                NavigationLink(
                    destination: AIChatView(
                        contextTitle: repo.fullName,
                        contextText: String((readme ?? repo.description ?? "").prefix(6000)),
                        quickPrompts: ["用中文总结这个仓库", "怎么安装和使用？", "有哪些注意事项或风险？"]
                    )
                ) {
                    Label("问 AI", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                TranslateBar(on: $zh)
                Divider()
                if loading {
                    ProgressView()
                } else if let r = readme {
                    TranslatableMarkdown(text: r, translate: zh)
                } else {
                    Text("没有 README").foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .task { await load() }
    }

    private func load() async {
        starred = await API.shared.exists("/user/starred/\(repo.fullName)")
        do {
            let r = try await API.shared.raw("/repos/\(repo.fullName)/readme")
            readme = r.isEmpty ? nil : r
        } catch {
            readme = nil
        }
        loading = false
    }

    private func toggleStar() async {
        errorMsg = nil
        do {
            try await API.shared.action("/user/starred/\(repo.fullName)", method: starred ? "DELETE" : "PUT")
            starred.toggle()
        } catch {
            errorMsg = errText(error)
        }
    }
}

// MARK: - 文件浏览

struct FilesView: View {
    let repo: Repo
    let path: String
    let embedded: Bool
    @State private var items: [ContentItem] = []
    @State private var loading = true
    @State private var errorMsg: String?

    var body: some View {
        List {
            if let e = errorMsg {
                Text(e).font(.footnote).foregroundColor(.red)
            }
            ForEach(items) { it in
                if it.type == "dir" {
                    NavigationLink(destination: FilesView(repo: repo, path: it.path, embedded: false)) {
                        Label(it.name, systemImage: "folder")
                    }
                } else {
                    NavigationLink(destination: FileView(repo: repo, item: it)) {
                        Label(it.name, systemImage: "doc.text")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if loading { ProgressView() } }
        .neonBackground()
        .navigationTitle(embedded ? repo.name : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let url = path.isEmpty
                ? "/repos/\(repo.fullName)/contents"
                : "/repos/\(repo.fullName)/contents/\(encPath(path))"
            let list: [ContentItem] = try await API.shared.get(url)
            items = list.sorted { a, b in
                if (a.type == "dir") != (b.type == "dir") { return a.type == "dir" }
                return a.name.lowercased() < b.name.lowercased()
            }
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}

struct FileView: View {
    let repo: Repo
    let item: ContentItem
    @State private var text: String?
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var zh = false

    private var isMD: Bool {
        let n = item.name.lowercased()
        return n.hasSuffix(".md") || n.hasSuffix(".markdown")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if isMD { TranslateBar(on: $zh) }
                if loading {
                    ProgressView()
                } else if let t = text, !t.isEmpty {
                    if isMD {
                        TranslatableMarkdown(text: t, translate: zh)
                    } else {
                        ScrollView(.horizontal) {
                            Text(t)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Text(errorMsg ?? "无法预览此文件（二进制或为空）").foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .neonBackground()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let t = try await API.shared.raw("/repos/\(repo.fullName)/contents/\(encPath(item.path))")
            text = String(t.prefix(60_000))
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}
