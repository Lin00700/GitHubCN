import SwiftUI

enum PeopleKind { case contributors, stargazers, watchers }

struct PeopleListView: View {
    let repo: Repo
    let kind: PeopleKind
    @State private var users: [GHUser] = []
    @State private var contribs: [Contributor] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if kind == .contributors {
                ForEach(contribs, id: \.ident) { c in
                    if let login = c.login {
                        NavigationLink { UserProfileView(login: login) } label: {
                            HStack {
                                AvatarView(url: c.avatarUrl, side: 32)
                                Text(login)
                                Spacer()
                                Text("\(c.contributions ?? 0)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ForEach(users) { u in
                    NavigationLink { UserProfileView(login: u.login) } label: { UserRow(user: u) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var title: String {
        switch kind {
        case .contributors: return "贡献者"
        case .stargazers: return "标星的人"
        case .watchers: return "关注的人"
        }
    }

    private func load() async {
        do {
            switch kind {
            case .contributors:
                contribs = try await API.shared.get("/repos/\(repo.fullName)/contributors?per_page=100")
            case .stargazers:
                users = try await API.shared.get("/repos/\(repo.fullName)/stargazers?per_page=100")
            case .watchers:
                users = try await API.shared.get("/repos/\(repo.fullName)/subscribers?per_page=100")
            }
        } catch { self.error = errText(error) }
    }
}

struct ForkListView: View {
    let repo: Repo
    @State private var repos: [Repo] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(repos) { r in
                NavigationLink { RepoDetailView(repo: r) } label: { RepoRow(repo: r) }
            }
        }
        .navigationTitle("复刻")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { repos = try await API.shared.get("/repos/\(repo.fullName)/forks?sort=newest&per_page=50") }
            catch { self.error = errText(error) }
        }
    }
}

struct RepoEventsView: View {
    let repo: Repo
    @State private var events: [GHEvent] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(events) { e in EventLink(event: e) }
        }
        .navigationTitle("仓库动态")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }
    private func load() async {
        do { events = try await API.shared.get("/repos/\(repo.fullName)/events?per_page=40"); error = nil }
        catch { self.error = errText(error) }
    }
}

struct InsightsView: View {
    let repo: Repo
    @State private var languages: [(String, Int)] = []
    @State private var weeks: [WeekActivity] = []
    @State private var part: Participation?
    @State private var views: TrafficViews?
    @State private var clones: TrafficClones?
    @State private var health: Int?
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if !languages.isEmpty {
                Section("语言") {
                    let total = max(languages.map(\.1).reduce(0, +), 1)
                    ForEach(languages, id: \.0) { name, bytes in
                        HStack {
                            Circle().fill(languageColor(name)).frame(width: 8, height: 8)
                            Text(name)
                            Spacer()
                            Text("\(bytes * 100 / total)%").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !weeks.isEmpty {
                Section("每周提交") {
                    BarRow(values: weeks.suffix(20).map(\.total))
                }
            }
            if let part {
                Section("参与度（52 周）") {
                    Text("全部提交合计 \(part.all.reduce(0, +))，所有者 \(part.owner.reduce(0, +))")
                        .font(.subheadline)
                    BarRow(values: Array(part.all.suffix(26)))
                }
            }
            if let views {
                Section("访问（14 天）") {
                    Text("\(views.count) 次 · \(views.uniques) 个独立访客")
                    BarRow(values: (views.views ?? []).map(\.count))
                }
            }
            if let clones {
                Section("克隆（14 天）") {
                    Text("\(clones.count) 次 · \(clones.uniques) 个独立来源")
                }
            }
            if let health {
                Section("社区健康") { Text("\(health)%") }
            }
            Section {
                Text("访问和克隆统计需要推送权限。社区健康度来自 GitHub 的 community profile。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("洞察")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if let map: [String: Int] = try? await API.shared.get("/repos/\(repo.fullName)/languages") {
            languages = map.sorted { $0.value > $1.value }
        }
        if let w: [WeekActivity] = try? await API.shared.get("/repos/\(repo.fullName)/stats/commit_activity") {
            weeks = w
        }
        part = try? await API.shared.get("/repos/\(repo.fullName)/stats/participation")
        views = try? await API.shared.get("/repos/\(repo.fullName)/traffic/views")
        clones = try? await API.shared.get("/repos/\(repo.fullName)/traffic/clones")
        if let c: CommunityProfile = try? await API.shared.get("/repos/\(repo.fullName)/community/profile") {
            health = c.healthPercentage
        }
        if languages.isEmpty && weeks.isEmpty && views == nil {
            error = "部分统计需要权限，或 GitHub 仍在计算（stats 有时返回 202）。"
        }
    }
}

struct BarRow: View {
    let values: [Int]
    var body: some View {
        let maxV = max(values.max() ?? 1, 1)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 8, height: max(2, CGFloat(v) / CGFloat(maxV) * 64))
                        .accessibilityLabel("\(v)")
                }
            }
            .frame(height: 68)
        }
    }
}

struct SecurityView: View {
    let repo: Repo
    @State private var dep: [DependabotAlert] = []
    @State private var secrets: [SecretAlert] = []
    @State private var code: [CodeScanAlert] = []
    @State private var notes: [String] = []

    var body: some View {
        List {
            Section {
                Text("私有仓库的警报需要 security_events 权限。没有权限时对应列表为空。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("开启漏洞警报") { Task { await toggleVuln(on: true) } }
                Button("关闭漏洞警报", role: .destructive) { Task { await toggleVuln(on: false) } }
            }
            if !notes.isEmpty {
                Section { ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) } }
            }
            Section("Dependabot") {
                if dep.isEmpty { Text("没有警报").foregroundStyle(.secondary) }
                ForEach(dep) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.securityAdvisory?.summary ?? a.dependency?.package?.name ?? "#\(a.number)")
                            .font(.body)
                        Text("\(a.state) · \(a.securityAdvisory?.severity ?? "") · \(a.dependency?.manifestPath ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        if a.state == "open" {
                            Button("忽略（可接受的风险）") { Task { await dismissDep(a) } }
                        }
                    }
                }
            }
            Section("密钥扫描") {
                if secrets.isEmpty { Text("没有警报").foregroundStyle(.secondary) }
                ForEach(secrets) { a in
                    VStack(alignment: .leading) {
                        Text(a.secretType ?? "密钥").font(.body)
                        Text("\(a.state) · \(relTime(a.createdAt))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("代码扫描") {
                if code.isEmpty { Text("没有警报").foregroundStyle(.secondary) }
                ForEach(code) { a in
                    VStack(alignment: .leading) {
                        Text(a.rule?.description ?? a.rule?.id ?? "#\(a.number)").font(.body).lineLimit(2)
                        Text("\(a.state) · \(a.rule?.severity ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("安全")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        notes = []
        if let list: [DependabotAlert] = try? await API.shared.get("/repos/\(repo.fullName)/dependabot/alerts?per_page=30&state=open") {
            dep = list
        } else { notes.append("Dependabot 警报不可用") }
        if let list: [SecretAlert] = try? await API.shared.get("/repos/\(repo.fullName)/secret-scanning/alerts?per_page=30&state=open") {
            secrets = list
        } else { notes.append("密钥扫描不可用") }
        if let list: [CodeScanAlert] = try? await API.shared.get("/repos/\(repo.fullName)/code-scanning/alerts?per_page=30&state=open") {
            code = list
        } else { notes.append("代码扫描不可用") }
    }

    private func dismissDep(_ a: DependabotAlert) async {
        try? await API.shared.post("/repos/\(repo.fullName)/dependabot/alerts/\(a.number)", body: [
            "state": "dismissed",
            "dismissed_reason": "tolerable_risk",
            "dismissed_comment": "在 GitHub 中文里忽略"
        ], method: "PATCH")
        await load()
    }

    private func toggleVuln(on: Bool) async {
        do {
            if on { try await API.shared.action("/repos/\(repo.fullName)/vulnerability-alerts", method: "PUT") }
            else { try await API.shared.delete("/repos/\(repo.fullName)/vulnerability-alerts") }
            notes.append(on ? "已请求开启漏洞警报" : "已请求关闭漏洞警报")
        } catch { notes.append(errText(error) ?? "失败") }
    }
}

struct PagesView: View {
    let repo: Repo
    @State private var pages: GHPages?
    @State private var error: String?
    @State private var info: String?
    var body: some View {
        Form {
            if let pages {
                LabeledContent("状态", value: pages.status ?? "未知")
                if let c = pages.cname, !c.isEmpty { LabeledContent("域名", value: c) }
                if let u = pages.htmlUrl.flatMap(URL.init(string:)) { Link("打开站点", destination: u) }
            } else {
                Text(error ?? "这个仓库没有 GitHub Pages，或仍在加载。").foregroundStyle(.secondary)
            }
            Button("请求重新构建") { Task { await build() } }
            if let info { Text(info).foregroundStyle(.secondary) }
        }
        .navigationTitle("Pages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { pages = try await API.shared.get("/repos/\(repo.fullName)/pages") }
            catch { self.error = errText(error) }
        }
    }
    private func build() async {
        do {
            try await API.shared.action("/repos/\(repo.fullName)/pages/builds", method: "POST")
            info = "已请求构建"
        } catch { info = errText(error) }
    }
}

struct RepoSettingsView: View {
    let repo: Repo
    @State private var desc: String = ""
    @State private var home: String = ""
    @State private var visibility = "public"
    @State private var branch = ""
    @State private var topics = ""
    @State private var hasIssues = true
    @State private var hasWiki = true
    @State private var hasProjects = true
    @State private var hasDiscussions = true
    @State private var archived = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var deleteName = ""

    var body: some View {
        Form {
            Section("资料") {
                TextField("描述", text: $desc)
                TextField("主页", text: $home).textInputAutocapitalization(.never)
                TextField("默认分支", text: $branch).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("主题，用空格分隔", text: $topics).textInputAutocapitalization(.never)
            }
            Section("功能") {
                Picker("可见性", selection: $visibility) {
                    Text("公开").tag("public")
                    Text("私有").tag("private")
                }
                Toggle("问题", isOn: $hasIssues)
                Toggle("维基", isOn: $hasWiki)
                Toggle("项目", isOn: $hasProjects)
                Toggle("讨论", isOn: $hasDiscussions)
                Toggle("归档", isOn: $archived)
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
            Section { Button("保存") { Task { await save() } } }
            if repo.canAdmin {
                Section {
                    TextField("输入 \(repo.fullName) 以确认删除", text: $deleteName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("删除仓库", role: .destructive) { confirmDelete = true }
                        .disabled(deleteName != repo.fullName)
                }
            }
        }
        .navigationTitle("仓库设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            desc = repo.description ?? ""
            home = repo.homepage ?? ""
            visibility = repo.isPrivate ? "private" : "public"
            branch = repo.branch
            topics = repo.topics.joined(separator: " ")
            archived = repo.isArchived
        }
        .confirmationDialog("删除 \(repo.name)？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await remove() } }
            Button("取消", role: .cancel) {}
        } message: { Text("此操作不能在应用内撤销。") }
    }

    private func save() async {
        do {
            try await API.shared.post("/repos/\(repo.fullName)", body: [
                "description": desc,
                "homepage": home,
                "visibility": visibility,
                "default_branch": branch,
                "has_issues": hasIssues,
                "has_wiki": hasWiki,
                "has_projects": hasProjects,
                "has_discussions": hasDiscussions,
                "archived": archived
            ], method: "PATCH")
            let names = topics.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            try? await API.shared.put("/repos/\(repo.fullName)/topics", body: ["names": names])
            message = "已保存"
            tapHaptic()
        } catch { message = errText(error) }
    }

    private func remove() async {
        do {
            try await API.shared.delete("/repos/\(repo.fullName)")
            message = "已删除。返回上一页即可。"
        } catch { message = errText(error) }
    }
}

struct CollaboratorsView: View {
    let repo: Repo
    @State private var people: [Collaborator] = []
    @State private var login = ""
    @State private var perm = "push"
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(people) { p in
                VStack(alignment: .leading) {
                    Text(p.login).font(.headline)
                    Text(p.roleName ?? "").font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("移除", role: .destructive) { Task { await remove(p) } }
                }
            }
            Section("邀请") {
                TextField("用户名", text: $login).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("权限", selection: $perm) {
                    Text("读取").tag("pull")
                    Text("分类").tag("triage")
                    Text("写入").tag("push")
                    Text("维护").tag("maintain")
                    Text("管理").tag("admin")
                }
                Button("邀请") { Task { await add() } }.disabled(login.isEmpty)
            }
        }
        .navigationTitle("协作者")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { people = try await API.shared.get("/repos/\(repo.fullName)/collaborators?per_page=100"); error = nil }
        catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.put("/repos/\(repo.fullName)/collaborators/\(enc(login))", body: ["permission": perm])
            login = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ p: Collaborator) async {
        try? await API.shared.delete("/repos/\(repo.fullName)/collaborators/\(p.login)")
        await load()
    }
}

struct HooksView: View {
    let repo: Repo
    @State private var hooks: [Webhook] = []
    @State private var url = ""
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(hooks) { h in
                VStack(alignment: .leading) {
                    Text(h.name).font(.headline)
                    Text(h.events.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions { Button("删除", role: .destructive) { Task { await remove(h) } } }
            }
            Section("新建 web hook") {
                TextField("https://example.com/hook", text: $url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("创建（监听 push）") { Task { await add() } }.disabled(url.isEmpty)
            }
        }
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { hooks = try await API.shared.get("/repos/\(repo.fullName)/hooks"); error = nil }
        catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.post("/repos/\(repo.fullName)/hooks", body: [
                "name": "web",
                "active": true,
                "events": ["push"],
                "config": ["url": url, "content_type": "json"]
            ])
            url = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ h: Webhook) async {
        try? await API.shared.delete("/repos/\(repo.fullName)/hooks/\(h.id)")
        await load()
    }
}

struct DeployKeysView: View {
    let repo: Repo
    @State private var keys: [DeployKey] = []
    @State private var title = ""
    @State private var key = ""
    @State private var readOnly = true
    @State private var error: String?
    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                ForEach(keys) { k in
                    VStack(alignment: .leading) {
                        Text(k.title).font(.headline)
                        Text(k.readOnly ? "只读" : "可写").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button("删除", role: .destructive) { Task { await remove(k) } } }
                }
            }
            Section("添加") {
                TextField("标题", text: $title)
                TextField("公钥", text: $key, axis: .vertical).font(.system(.footnote, design: .monospaced))
                Toggle("只读", isOn: $readOnly)
                Button("添加") { Task { await add() } }.disabled(title.isEmpty || key.isEmpty)
            }
        }
        .navigationTitle("部署密钥")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { keys = try await API.shared.get("/repos/\(repo.fullName)/keys"); error = nil }
        catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.post("/repos/\(repo.fullName)/keys", body: ["title": title, "key": key, "read_only": readOnly])
            title = ""; key = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ k: DeployKey) async {
        try? await API.shared.delete("/repos/\(repo.fullName)/keys/\(k.id)")
        await load()
    }
}

struct EnvironmentsView: View {
    let repo: Repo
    @State private var items: [GHEnvironment] = []
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { e in
                Text(e.name)
                    .swipeActions { Button("删除", role: .destructive) { Task { await remove(e) } } }
            }
            Section {
                TextField("环境名", text: $name).textInputAutocapitalization(.never)
                Button("创建") { Task { await add() } }.disabled(name.isEmpty)
            }
        }
        .navigationTitle("环境")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do {
            let list: EnvList = try await API.shared.get("/repos/\(repo.fullName)/environments")
            items = list.environments
            error = nil
        } catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.put("/repos/\(repo.fullName)/environments/\(enc(name))", body: [:])
            name = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ e: GHEnvironment) async {
        try? await API.shared.delete("/repos/\(repo.fullName)/environments/\(enc(e.name))")
        await load()
    }
}

struct VariablesView: View {
    let repo: Repo
    @State private var items: [ActionsVariable] = []
    @State private var name = ""
    @State private var value = ""
    @State private var error: String?
    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                ForEach(items) { v in
                    VStack(alignment: .leading) {
                        Text(v.name).font(.headline)
                        Text(v.value ?? "").font(.caption.monospaced()).textSelection(.enabled)
                    }
                    .swipeActions { Button("删除", role: .destructive) { Task { await remove(v) } } }
                }
            }
            Section("新建变量") {
                TextField("名称", text: $name).textInputAutocapitalization(.never)
                TextField("值", text: $value)
                Button("保存") { Task { await add() } }.disabled(name.isEmpty)
            } footer: {
                Text("Actions 密钥的值不能通过 API 读出，只能在下面的「密钥名称」里看到名字。变量的值可以读写。")
            }
        }
        .navigationTitle("变量")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do {
            let list: VariableList = try await API.shared.get("/repos/\(repo.fullName)/actions/variables")
            items = list.variables
            error = nil
        } catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.post("/repos/\(repo.fullName)/actions/variables", body: ["name": name, "value": value])
            name = ""; value = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ v: ActionsVariable) async {
        try? await API.shared.delete("/repos/\(repo.fullName)/actions/variables/\(enc(v.name))")
        await load()
    }
}

struct SecretsView: View {
    let repo: Repo
    @State private var items: [ActionsSecret] = []
    @State private var error: String?
    var body: some View {
        List {
            Text("密钥值使用仓库公钥加密后才能写入，API 不会返回明文。这里只列出名称。")
                .font(.footnote).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { s in
                VStack(alignment: .leading) {
                    Text(s.name).font(.headline)
                    Text(relTime(s.updatedAt)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("密钥")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let list: SecretList = try await API.shared.get("/repos/\(repo.fullName)/actions/secrets")
                items = list.secrets
            } catch { self.error = errText(error) }
        }
    }
}

struct RunnersView: View {
    let repo: Repo
    @State private var items: [GHRunner] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if items.isEmpty && error == nil { Text("没有自托管运行器").foregroundStyle(.secondary) }
            ForEach(items) { r in
                VStack(alignment: .leading) {
                    Text(r.name).font(.headline)
                    Text("\(r.os ?? "") · \(r.status ?? "")\(r.busy == true ? " · 忙碌" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("运行器")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let list: RunnerList = try await API.shared.get("/repos/\(repo.fullName)/actions/runners")
                items = list.runners
            } catch { self.error = errText(error) }
        }
    }
}

struct CachesView: View {
    let repo: Repo
    @State private var items: [ActionsCache] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { c in
                VStack(alignment: .leading) {
                    Text(c.key ?? "缓存").font(.subheadline).lineLimit(2)
                    Text("\(c.ref ?? "") · \(sizeText(c.sizeInBytes ?? 0))").font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions { Button("删除", role: .destructive) { Task { await remove(c) } } }
            }
        }
        .navigationTitle("缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do {
            let list: CacheList = try await API.shared.get("/repos/\(repo.fullName)/actions/caches?per_page=50")
            items = list.actionsCaches
            error = nil
        } catch { self.error = errText(error) }
    }
    private func remove(_ c: ActionsCache) async {
        try? await API.shared.delete("/repos/\(repo.fullName)/actions/caches/\(c.id)")
        await load()
    }
}

struct RulesetsView: View {
    let repo: Repo
    @State private var items: [Ruleset] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.secondary) }
            if items.isEmpty && error == nil { Text("没有规则集").foregroundStyle(.secondary) }
            ForEach(items) { r in
                VStack(alignment: .leading) {
                    Text(r.name).font(.headline)
                    Text("\(r.target ?? "") · \(r.enforcement ?? "")").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let u = URL(string: "https://github.com/\(repo.fullName)/rules") {
                Link("在网页编辑规则集", destination: u)
            }
        }
        .navigationTitle("规则集")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { items = try await API.shared.get("/repos/\(repo.fullName)/rulesets") }
            catch { self.error = errText(error) }
        }
    }
}

struct LabelListView: View {
    let repo: String
    @State private var labels: [GHLabel] = []
    @State private var name = ""
    @State private var color = "ededed"
    @State private var desc = ""
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(labels) { l in
                HStack {
                    Circle().fill(Color(hex: l.color ?? "ccc")).frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(l.name)
                        if let d = l.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions { Button("删除", role: .destructive) { Task { await remove(l) } } }
            }
            Section("新建") {
                TextField("名称", text: $name)
                TextField("颜色，例如 d73a4a", text: $color).textInputAutocapitalization(.never)
                TextField("描述", text: $desc)
                Button("创建") { Task { await add() } }.disabled(name.isEmpty)
            }
        }
        .navigationTitle("标签")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { labels = try await API.shared.get("/repos/\(repo)/labels?per_page=100"); error = nil }
        catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.post("/repos/\(repo)/labels", body: ["name": name, "color": color, "description": desc])
            name = ""; desc = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func remove(_ l: GHLabel) async {
        try? await API.shared.delete("/repos/\(repo)/labels/\(enc(l.name))")
        await load()
    }
}

struct MilestoneListView: View {
    let repo: String
    @State private var items: [Milestone] = []
    @State private var title = ""
    @State private var desc = ""
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { m in
                VStack(alignment: .leading) {
                    Text(m.title).font(.headline)
                    Text("打开 \(m.openIssues ?? 0) · 关闭 \(m.closedIssues ?? 0) · \(m.state ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    if let d = m.description, !d.isEmpty { Text(d).font(.subheadline) }
                }
                .swipeActions {
                    Button("关闭") { Task { await close(m) } }.tint(.purple)
                }
            }
            Section("新建") {
                TextField("标题", text: $title)
                TextField("描述", text: $desc)
                Button("创建") { Task { await add() } }.disabled(title.isEmpty)
            }
        }
        .navigationTitle("里程碑")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { items = try await API.shared.get("/repos/\(repo)/milestones?state=all&per_page=50"); error = nil }
        catch { self.error = errText(error) }
    }
    private func add() async {
        do {
            try await API.shared.post("/repos/\(repo)/milestones", body: ["title": title, "description": desc])
            title = ""; desc = ""
            await load()
        } catch { self.error = errText(error) }
    }
    private func close(_ m: Milestone) async {
        try? await API.shared.post("/repos/\(repo)/milestones/\(m.number)", body: ["state": "closed"], method: "PATCH")
        await load()
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
