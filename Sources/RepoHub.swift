import SwiftUI

struct RepoDetailView: View {
    let repo: Repo
    @State private var starred = false
    @State private var watching = "none"
    @State private var readme: String?
    @State private var zh = false
    @State private var loadingReadme = true
    @State private var error: String?
    @State private var info: String?
    @State private var showClone = false
    @State private var forking = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        AvatarView(url: repo.owner.avatarUrl, side: 28)
                        Text(repo.owner.login).font(.subheadline)
                        if repo.isPrivate { Label("私有", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                        if repo.isArchived { Text("已归档").font(.caption).foregroundStyle(.orange) }
                    }
                    if let d = repo.description, !d.isEmpty { Text(d).font(.body) }
                    if repo.isFork, let p = repo.parent {
                        Text("复刻自 \(p.fullName)").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        Label("\(repo.stargazersCount)", systemImage: "star")
                        Label("\(repo.forksCount)", systemImage: "arrow.triangle.branch")
                        Label("\(repo.subscribersCount)", systemImage: "eye")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let lang = repo.language {
                        HStack(spacing: 6) {
                            Circle().fill(languageColor(lang)).frame(width: 8, height: 8)
                            Text(lang).font(.subheadline)
                        }
                    }
                    if !repo.topics.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(repo.topics, id: \.self) { t in
                                    NavigationLink { TopicReposView(topic: t) } label: {
                                        Text(t)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    if let home = repo.homepage, let u = URL(string: home.contains("://") ? home : "https://\(home)") {
                        Link(home, destination: u).font(.subheadline)
                    }
                    if let lic = repo.license?.name { Text(lic).font(.caption).foregroundStyle(.secondary) }
                }
                Button { Task { await toggleStar() } } label: {
                    Label(starred ? "取消星标" : "加星标", systemImage: starred ? "star.fill" : "star")
                }
                Menu {
                    Button("全部动态") { Task { await setWatch(sub: true, ignore: false) } }
                    Button("仅参与和提及") { Task { await setWatch(sub: false, ignore: false) } }
                    Button("忽略") { Task { await setWatch(sub: false, ignore: true) } }
                } label: {
                    Label(watchLabel, systemImage: "eye")
                }
                Button { Task { await fork() } } label: {
                    HStack { if forking { ProgressView() }; Label("复刻", systemImage: "arrow.triangle.branch") }
                }
                .disabled(forking)
                Button { showClone = true } label: { Label("克隆 / 下载", systemImage: "square.and.arrow.down") }
            }

            if let info { Section { Text(info).foregroundStyle(.secondary) } }
            if let error { Section { Text(error).foregroundStyle(.red) } }

            Section("代码") {
                NavigationLink { FilesView(repo: repo, path: "", ref: repo.branch) } label: { Label("文件", systemImage: "folder") }
                NavigationLink { CommitsView(repo: repo, ref: repo.branch) } label: { Label("提交", systemImage: "clock.arrow.circlepath") }
                NavigationLink { BranchesView(repo: repo) } label: { Label("分支", systemImage: "arrow.triangle.branch") }
                NavigationLink { TagsView(repo: repo) } label: { Label("标签", systemImage: "tag") }
                NavigationLink { CompareView(repo: repo) } label: { Label("对比", systemImage: "arrow.left.arrow.right") }
                NavigationLink { ReleasesView(repo: repo) } label: { Label("发行版", systemImage: "shippingbox") }
            }

            Section("协作") {
                NavigationLink { IssueListView(repoFullName: repo.fullName, pulls: false) } label: {
                    Label("问题", systemImage: "exclamationmark.circle")
                }
                NavigationLink { IssueListView(repoFullName: repo.fullName, pulls: true) } label: {
                    Label("拉取请求", systemImage: "arrow.triangle.branch")
                }
                NavigationLink { DiscussionsView(fullName: repo.fullName) } label: {
                    Label("讨论", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink { ProjectListView(scope: .repo(repo.fullName)) } label: {
                    Label("项目", systemImage: "square.grid.2x2")
                }
                NavigationLink { WikiView(fullName: repo.fullName) } label: { Label("维基", systemImage: "book") }
                NavigationLink { LabelListView(repo: repo.fullName) } label: { Label("标签", systemImage: "tag") }
                NavigationLink { MilestoneListView(repo: repo.fullName) } label: { Label("里程碑", systemImage: "flag") }
            }

            Section("自动化") {
                NavigationLink { ActionsView(repo: repo) } label: { Label("行动 Actions", systemImage: "play.circle") }
                NavigationLink { CreateCodespaceView(repo: repo) } label: { Label("代码空间", systemImage: "laptopcomputer") }
                NavigationLink { PagesView(repo: repo) } label: { Label("Pages", systemImage: "globe") }
            }

            Section("洞察") {
                NavigationLink { InsightsView(repo: repo) } label: { Label("语言、贡献与流量", systemImage: "chart.bar") }
                NavigationLink { PeopleListView(repo: repo, kind: .contributors) } label: { Label("贡献者", systemImage: "person.2") }
                NavigationLink { PeopleListView(repo: repo, kind: .stargazers) } label: { Label("标星的人", systemImage: "star") }
                NavigationLink { PeopleListView(repo: repo, kind: .watchers) } label: { Label("关注的人", systemImage: "eye") }
                NavigationLink { ForkListView(repo: repo) } label: { Label("复刻", systemImage: "arrow.triangle.branch") }
                NavigationLink { RepoEventsView(repo: repo) } label: { Label("仓库动态", systemImage: "bolt") }
            }

            Section("安全") {
                NavigationLink { SecurityView(repo: repo) } label: { Label("警报", systemImage: "shield") }
                NavigationLink { MergeQueueView(repo: repo) } label: { Label("合并队列", systemImage: "list.number") }
            }

            if repo.canPush || repo.canAdmin {
                Section("管理") {
                    NavigationLink { RepoSettingsView(repo: repo) } label: { Label("仓库设置", systemImage: "gearshape") }
                    NavigationLink { CollaboratorsView(repo: repo) } label: { Label("协作者", systemImage: "person.2") }
                    NavigationLink { HooksView(repo: repo) } label: { Label("Webhooks", systemImage: "link") }
                    NavigationLink { DeployKeysView(repo: repo) } label: { Label("部署密钥", systemImage: "key") }
                    NavigationLink { EnvironmentsView(repo: repo) } label: { Label("环境", systemImage: "server.rack") }
                    NavigationLink { VariablesView(repo: repo) } label: { Label("变量", systemImage: "curlybraces") }
                    NavigationLink { SecretsView(repo: repo) } label: { Label("密钥名称", systemImage: "lock") }
                    NavigationLink { RunnersView(repo: repo) } label: { Label("运行器", systemImage: "desktopcomputer") }
                    NavigationLink { CachesView(repo: repo) } label: { Label("缓存", systemImage: "internaldrive") }
                    NavigationLink { RulesetsView(repo: repo) } label: { Label("规则集", systemImage: "checklist") }
                }
            }

            Section {
                if loadingReadme { ProgressView() }
                else if let readme {
                    TranslateBar(on: $zh)
                    TranslatableMarkdown(text: readme, translate: zh)
                    NavigationLink {
                        AIChatView(
                            contextTitle: repo.fullName,
                            contextText: String(readme.prefix(6000)),
                            quickPrompts: ["用中文总结这个仓库", "怎么安装和使用？", "有哪些注意事项？"]
                        )
                    } label: { Label("问 AI", systemImage: "sparkles") }
                } else {
                    Text("没有 README").foregroundStyle(.secondary)
                }
            } header: {
                Text("README")
            }

            Section {
                if let u = URL(string: repo.htmlUrl) {
                    Link(destination: u) { Label("在 Safari 中打开", systemImage: "safari") }
                }
                Link(destination: URL(string: "https://github.com/\(repo.fullName)/agents")!) {
                    Label("代理 Agents（网页）", systemImage: "safari")
                }
            }
        }
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showClone) { CloneSheet(repo: repo) }
        .task { await loadMeta() }
    }

    private var watchLabel: String {
        switch watching {
        case "all": return "关注：全部动态"
        case "ignore": return "关注：忽略"
        default: return "关注：仅参与"
        }
    }

    private func loadMeta() async {
        starred = await API.shared.exists("/user/starred/\(repo.fullName)")
        if let sub: Subscription = try? await API.shared.get("/repos/\(repo.fullName)/subscription") {
            if sub.ignored == true { watching = "ignore" }
            else if sub.subscribed == true { watching = "all" }
            else { watching = "participating" }
        } else {
            watching = "none"
        }
        do {
            let r = try await API.shared.raw("/repos/\(repo.fullName)/readme")
            readme = r.isEmpty ? nil : r
        } catch { readme = nil }
        loadingReadme = false
    }

    private func toggleStar() async {
        error = nil
        do {
            try await API.shared.action("/user/starred/\(repo.fullName)", method: starred ? "DELETE" : "PUT")
            starred.toggle()
            tapHaptic()
        } catch { self.error = errText(error) }
    }

    private func setWatch(sub: Bool, ignore: Bool) async {
        error = nil
        do {
            if !sub && !ignore {
                try await API.shared.delete("/repos/\(repo.fullName)/subscription")
                watching = "none"
            } else {
                try await API.shared.put("/repos/\(repo.fullName)/subscription", body: ["subscribed": sub, "ignored": ignore])
                watching = ignore ? "ignore" : "all"
            }
            tapHaptic()
        } catch { self.error = errText(error) }
    }

    private func fork() async {
        forking = true
        error = nil
        do {
            let created: Repo = try await API.shared.write("/repos/\(repo.fullName)/forks", method: "POST", body: [:])
            info = "已请求复刻到 \(created.fullName)。GitHub 可能还要一点时间准备。"
            tapHaptic()
        } catch { self.error = errText(error) }
        forking = false
    }
}

struct CloneSheet: View {
    let repo: Repo
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var share: ShareItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("HTTPS") {
                    Text("https://github.com/\(repo.fullName).git")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("复制") { UIPasteboard.general.string = "https://github.com/\(repo.fullName).git"; tapHaptic() }
                }
                Section("SSH") {
                    Text("git@github.com:\(repo.fullName).git")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("复制") { UIPasteboard.general.string = "git@github.com:\(repo.fullName).git"; tapHaptic() }
                }
                Section {
                    Button {
                        Task { await zip() }
                    } label: {
                        HStack { if busy { ProgressView() }; Text("下载 \(repo.branch).zip") }
                    }
                    .disabled(busy)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("克隆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $share) { ActivityView(items: [$0.url]) }
        }
    }

    private func zip() async {
        busy = true
        error = nil
        do {
            let url = try await API.shared.downloadFollowingRedirect(
                "/repos/\(repo.fullName)/zipball/\(enc(repo.branch))",
                name: "\(repo.name).zip"
            )
            share = ShareItem(url: url)
        } catch { self.error = errText(error) }
        busy = false
    }
}

struct CreateCodespaceView: View {
    let repo: Repo
    @State private var ref: String = ""
    @State private var busy = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        Form {
            TextField("分支或提交", text: $ref).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("会在这个仓库创建一个代码空间。编辑器通过浏览器打开。需要令牌包含 codespace 范围。")
                .font(.footnote).foregroundStyle(.secondary)
            Button { Task { await create() } } label: {
                HStack { if busy { ProgressView() }; Text("创建代码空间") }
            }
            .disabled(busy)
            if let message { Text(message).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
            NavigationLink { CodespaceListView() } label: { Text("我的代码空间") }
        }
        .navigationTitle("代码空间")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if ref.isEmpty { ref = repo.branch } }
    }

    private func create() async {
        busy = true
        error = nil
        do {
            let _: Codespace = try await API.shared.write("/repos/\(repo.fullName)/codespaces", method: "POST", body: ["ref": ref])
            message = "已创建。可以在「我的代码空间」里启动并打开。"
            tapHaptic()
        } catch { self.error = errText(error) }
        busy = false
    }
}
