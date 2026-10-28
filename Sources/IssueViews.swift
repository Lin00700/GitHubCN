import SwiftUI

struct IssueListView: View {
    let repoFullName: String
    let pulls: Bool
    @State private var state = "open"
    @State private var query = ""
    @State private var items: [Issue] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showNew = false
    @State private var showPR = false

    private var shown: [Issue] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(q) || "\($0.number)".contains(q) }
    }

    var body: some View {
        List {
            Picker("状态", selection: $state) {
                Text("打开").tag("open")
                Text("已关闭").tag("closed")
                Text("全部").tag("all")
            }
            .pickerStyle(.segmented)
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && items.isEmpty { ProgressView() }
            if !loading && shown.isEmpty && error == nil {
                EmptyHint(title: pulls ? "没有拉取请求" : "没有问题")
            }
            ForEach(shown) { i in
                NavigationLink { IssueDetailView(repoFullName: repoFullName, issue: i) } label: {
                    IssueRow(issue: i, showRepo: false)
                }
            }
        }
        .navigationTitle(pulls ? "拉取请求" : "问题")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "筛选标题或编号")
        .refreshable { await load() }
        .task(id: state) { await load() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { if pulls { showPR = true } else { showNew = true } } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(pulls ? "新建拉取请求" : "新建问题")
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { NewIssueView(repoFullName: repoFullName) { Task { await load() } } }
        }
        .sheet(isPresented: $showPR) {
            NavigationStack { NewPullView(repoFullName: repoFullName) { Task { await load() } } }
        }
    }

    private func load() async {
        loading = items.isEmpty
        error = nil
        do {
            if pulls {
                let pulls: [Issue] = try await API.shared.get("/repos/\(repoFullName)/pulls?state=\(state)&per_page=50")
                items = pulls
            } else {
                let all: [Issue] = try await API.shared.get("/repos/\(repoFullName)/issues?state=\(state)&per_page=50")
                items = all.filter { !$0.isPR }
            }
        } catch { self.error = errText(error) }
        loading = false
    }
}

struct NewIssueView: View {
    let repoFullName: String
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var templates: [ContentItem] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("标题") { TextField("问题标题", text: $title) }
            if !templates.isEmpty {
                Section("模板") {
                    ForEach(templates) { t in
                        Button(t.name) { Task { await apply(t) } }
                    }
                }
            }
            Section("描述") {
                TextEditor(text: $bodyText).frame(minHeight: 160)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button { Task { await create() } } label: {
                    HStack { if busy { ProgressView() }; Text("提交") }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .navigationTitle("新建问题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .task {
            templates = (try? await API.shared.get("/repos/\(repoFullName)/contents/.github/ISSUE_TEMPLATE")) ?? []
            templates = templates.filter { $0.type == "file" }
        }
    }

    private func apply(_ t: ContentItem) async {
        if let text = try? await API.shared.raw("/repos/\(repoFullName)/contents/\(encPath(t.path))") {
            bodyText = text
        }
    }

    private func create() async {
        busy = true
        error = nil
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues", body: ["title": title, "body": bodyText])
            onCreated()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}

struct NewPullView: View {
    let repoFullName: String
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var head = ""
    @State private var base = ""
    @State private var draft = false
    @State private var branches: [GHBranch] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("标题", text: $title)
            TextField("说明", text: $bodyText, axis: .vertical).lineLimit(4...10)
            Picker("基线", selection: $base) {
                ForEach(branches) { b in Text(b.name).tag(b.name) }
            }
            Picker("比较", selection: $head) {
                ForEach(branches) { b in Text(b.name).tag(b.name) }
            }
            Text("跨仓库时，比较分支可以写成 用户名:分支。").font(.caption).foregroundStyle(.secondary)
            TextField("或手动填写比较分支", text: $head).textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("草稿", isOn: $draft)
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await create() } } label: {
                HStack { if busy { ProgressView() }; Text("创建拉取请求") }
            }
            .disabled(busy || title.isEmpty || head.isEmpty || base.isEmpty)
        }
        .navigationTitle("新建拉取请求")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .task {
            if let list: [GHBranch] = try? await API.shared.get("/repos/\(repoFullName)/branches?per_page=100") {
                branches = list
                if base.isEmpty { base = list.first(where: { $0.name == "main" || $0.name == "master" })?.name ?? list.first?.name ?? "" }
            }
        }
    }

    private func create() async {
        busy = true
        do {
            try await API.shared.post("/repos/\(repoFullName)/pulls", body: [
                "title": title, "body": bodyText, "head": head, "base": base, "draft": draft
            ])
            onCreated()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}

struct IssueDetailView: View {
    let repoFullName: String
    let issue: Issue
    @EnvironmentObject var app: AppState
    @State private var state: String
    @State private var title: String
    @State private var bodyText: String
    @State private var comments: [Comment] = []
    @State private var pull: PullDetail?
    @State private var reviews: [PRReview] = []
    @State private var reviewComments: [PRComment] = []
    @State private var files: [CommitFile] = []
    @State private var commits: [GHCommit] = []
    @State private var reviewers: ReviewerList?
    @State private var timeline: [TimelineRow] = []
    @State private var subs: [Issue] = []
    @State private var labels: [GHLabel] = []
    @State private var allLabels: [GHLabel] = []
    @State private var milestones: [Milestone] = []
    @State private var zh = false
    @State private var draft = ""
    @State private var error: String?
    @State private var info: String?
    @State private var showEdit = false
    @State private var showMerge = false
    @State private var showReview = false
    @State private var reviewerName = ""

    init(repoFullName: String, issue: Issue) {
        self.repoFullName = repoFullName
        self.issue = issue
        _state = State(initialValue: issue.state)
        _title = State(initialValue: issue.title)
        _bodyText = State(initialValue: issue.body ?? "")
        _labels = State(initialValue: issue.labels ?? [])
    }

    private var isPR: Bool { issue.isPR || pull != nil }

    var body: some View {
        List {
            Section {
                Text(title).font(.title3.bold())
                HStack {
                    let badge = issueBadge(currentIssue)
                    StateBadge(text: badge.0, color: badge.1)
                    Text("#\(issue.number) · \(issue.user.login) · \(relTime(issue.createdAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let pull {
                    Text("\(pull.base.ref) ← \(pull.head.label ?? pull.head.ref)")
                        .font(.subheadline.monospaced())
                    Text("+\(pull.additions ?? 0) −\(pull.deletions ?? 0) · \(pull.changedFiles ?? 0) 个文件 · \(pull.commits ?? 0) 个提交")
                        .font(.caption).foregroundStyle(.secondary)
                    if let m = pull.mergeableState { Text("合并状态：\(m)").font(.caption).foregroundStyle(.secondary) }
                }
                if let ms = issue.milestone { Text("里程碑：\(ms.title)").font(.caption) }
                if !(issue.assignees ?? []).isEmpty {
                    Text("指派：\((issue.assignees ?? []).map(\.login).joined(separator: "、"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !labels.isEmpty {
                Section("标签") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(labels) { l in
                                Text(l.name)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: l.color ?? "ddd").opacity(0.25), in: Capsule())
                            }
                        }
                    }
                }
            }
            Section {
                TranslateBar(on: $zh)
                if bodyText.isEmpty { Text("没有描述").foregroundStyle(.secondary) }
                else { TranslatableMarkdown(text: bodyText, translate: zh) }
                NavigationLink {
                    AIChatView(
                        contextTitle: "\(repoFullName)#\(issue.number)",
                        contextText: aiContext,
                        quickPrompts: ["用中文总结", "给出解决思路", "帮我起草一条回复"]
                    )
                } label: { Label("问 AI", systemImage: "sparkles") }
            }
            if isPR {
                Section("拉取请求") {
                    NavigationLink("提交 \(commits.count)") { prCommitList }
                    NavigationLink("文件 \(files.count)") { prFileList }
                    ForEach(reviews) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(r.user?.login ?? "") · \(reviewState(r.state))").font(.subheadline.weight(.semibold))
                            if let b = r.body, !b.isEmpty { Text(b).font(.subheadline) }
                        }
                    }
                    if let reviewers {
                        if !reviewers.users.isEmpty {
                            Text("等待审阅：\(reviewers.users.map(\.login).joined(separator: "、"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TextField("请求审阅的用户名", text: $reviewerName).textInputAutocapitalization(.never)
                    Button("请求审阅") { Task { await requestReviewer() } }.disabled(reviewerName.isEmpty)
                    Button("更新分支") { Task { await updateBranch() } }
                    if pull?.draft == true {
                        Button("标记为可审阅") { Task { await ready() } }
                    } else if state == "open" {
                        Button("转为草稿") { Task { await toDraft() } }
                    }
                    if state == "open" && pull?.draft != true {
                        Button("合并") { showMerge = true }
                    }
                }
            }
            if !subs.isEmpty {
                Section("子问题") {
                    ForEach(subs) { s in
                        NavigationLink { IssueDetailView(repoFullName: repoFullName, issue: s) } label: { IssueRow(issue: s) }
                    }
                }
            }
            Section("评论 \(comments.count)") {
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(c.user.login) · \(relTime(c.createdAt))")
                            .font(.caption).foregroundStyle(.secondary)
                        TranslatableMarkdown(text: c.body ?? "", translate: zh)
                    }
                    .contextMenu {
                        Button("复制") { UIPasteboard.general.string = c.body }
                        Menu("表态") {
                            ForEach(reactionChoices, id: \.0) { pair in
                                Button(pair.1) { Task { await reactComment(c, pair.0) } }
                            }
                        }
                        if c.user.login == app.user?.login {
                            Button("删除", role: .destructive) { Task { await deleteComment(c) } }
                        }
                    }
                }
            }
            if !timeline.isEmpty {
                Section("时间线") {
                    ForEach(timeline) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.subheadline)
                            if let d = row.detail, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                            Text(relTime(row.time)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            if let info { Section { Text(info).foregroundStyle(.secondary) } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("#\(issue.number)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(state == "open" ? "关闭" : "重新打开") { Task { await toggleState() } }
                    Button("编辑") { showEdit = true }
                    Button(issue.locked == true ? "解锁对话" : "锁定对话") { Task { await toggleLock() } }
                    Button("置顶") { Task { await pin(true) } }
                    Button("取消置顶") { Task { await pin(false) } }
                    Menu("表态") {
                        ForEach(reactionChoices, id: \.0) { pair in
                            Button(pair.1) { Task { await reactIssue(pair.0) } }
                        }
                    }
                    Menu("标签") {
                        ForEach(allLabels) { l in
                            Button(l.name) { Task { await addLabel(l.name) } }
                        }
                    }
                    Menu("里程碑") {
                        Button("无") { Task { await setMilestone(nil) } }
                        ForEach(milestones) { m in
                            Button(m.title) { Task { await setMilestone(m.number) } }
                        }
                    }
                    if let u = URL(string: issue.htmlUrl) {
                        Link(destination: u) { Label("在 Safari 中打开", systemImage: "safari") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack { EditIssueSheet(repo: repoFullName, number: issue.number, title: title, body: bodyText) { t, b in
                title = t; bodyText = b
            } }
        }
        .sheet(isPresented: $showMerge) {
            NavigationStack { MergeSheet(repo: repoFullName, number: issue.number) {
                state = "closed"
                info = "已合并"
            } }
        }
        .sheet(isPresented: $showReview) {
            NavigationStack { ReviewSheet(repo: repoFullName, number: issue.number) { Task { await load() } } }
        }
        .task { await load() }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("评论", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            Button("发送") { Task { await send() } }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var currentIssue: Issue { issue }

    private var aiContext: String {
        var s = "标题：\(title)\n状态：\(state)\n\n\(bodyText)"
        for c in comments.suffix(5) { s += "\n\n--- \(c.user.login) ---\n\(c.body ?? "")" }
        return String(s.prefix(6000))
    }

    @ViewBuilder private var prCommitList: some View {
        List(commits) { c in
            NavigationLink { CommitLoader(repo: repoFullName, sha: c.sha) } label: {
                VStack(alignment: .leading) {
                    Text(c.titleLine).lineLimit(2)
                    Text(c.shortSha).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("提交")
    }

    @ViewBuilder private var prFileList: some View {
        List(files) { f in
            VStack(alignment: .leading, spacing: 6) {
                Text(f.filename).font(.subheadline.monospaced())
                Text("\(f.status ?? "") +\(f.additions ?? 0) −\(f.deletions ?? 0)")
                    .font(.caption).foregroundStyle(.secondary)
                if let patch = f.patch {
                    Text(String(patch.prefix(5000)))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("审阅") { showReview = true }
            }
        }
        .navigationTitle("文件")
    }

    private func load() async {
        do {
            comments = try await API.shared.get("/repos/\(repoFullName)/issues/\(issue.number)/comments?per_page=100")
        } catch { self.error = errText(error) }
        if isPR {
            pull = try? await API.shared.get("/repos/\(repoFullName)/pulls/\(issue.number)")
            reviews = (try? await API.shared.get("/repos/\(repoFullName)/pulls/\(issue.number)/reviews")) ?? []
            reviewComments = (try? await API.shared.get("/repos/\(repoFullName)/pulls/\(issue.number)/comments?per_page=50")) ?? []
            files = (try? await API.shared.get("/repos/\(repoFullName)/pulls/\(issue.number)/files?per_page=100")) ?? []
            commits = (try? await API.shared.get("/repos/\(repoFullName)/pulls/\(issue.number)/commits?per_page=50")) ?? []
            reviewers = try? await API.shared.get("/repos/\(repoFullName)/pulls/\(issue.number)/requested_reviewers")
        }
        if let any = try? await API.shared.json("/repos/\(repoFullName)/issues/\(issue.number)/timeline") {
            timeline = parseTimeline(any)
        }
        subs = (try? await API.shared.get("/repos/\(repoFullName)/issues/\(issue.number)/sub_issues")) ?? []
        allLabels = (try? await API.shared.get("/repos/\(repoFullName)/labels?per_page=100")) ?? []
        milestones = (try? await API.shared.get("/repos/\(repoFullName)/milestones?state=open&per_page=50")) ?? []
        if reviewComments.isEmpty == false && reviews.isEmpty {
            // review comments shown via files; keep them loaded for future
        }
    }

    private func send() async {
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues/\(issue.number)/comments", body: ["body": draft])
            draft = ""
            await load()
            tapHaptic()
        } catch { self.error = errText(error) }
    }

    private func toggleState() async {
        let new = state == "open" ? "closed" : "open"
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues/\(issue.number)", body: ["state": new], method: "PATCH")
            state = new
        } catch { self.error = errText(error) }
    }

    private func toggleLock() async {
        do {
            if issue.locked == true {
                try await API.shared.delete("/repos/\(repoFullName)/issues/\(issue.number)/lock")
                info = "已解锁"
            } else {
                try await API.shared.put("/repos/\(repoFullName)/issues/\(issue.number)/lock", body: ["lock_reason": "resolved"])
                info = "已锁定"
            }
        } catch { self.error = errText(error) }
    }

    private func pin(_ on: Bool) async {
        do {
            if on { try await API.shared.action("/repos/\(repoFullName)/issues/\(issue.number)/pin", method: "PUT") }
            else { try await API.shared.delete("/repos/\(repoFullName)/issues/\(issue.number)/pin") }
            info = on ? "已置顶" : "已取消置顶"
        } catch { self.error = errText(error) }
    }

    private func reactIssue(_ content: String) async {
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues/\(issue.number)/reactions", body: ["content": content])
            info = "已表态"
        } catch { self.error = errText(error) }
    }

    private func reactComment(_ c: Comment, _ content: String) async {
        try? await API.shared.post("/repos/\(repoFullName)/issues/comments/\(c.id)/reactions", body: ["content": content])
    }

    private func deleteComment(_ c: Comment) async {
        try? await API.shared.delete("/repos/\(repoFullName)/issues/comments/\(c.id)")
        await load()
    }

    private func addLabel(_ name: String) async {
        do {
            let updated: [GHLabel] = try await API.shared.write("/repos/\(repoFullName)/issues/\(issue.number)/labels", method: "POST", body: ["labels": [name]])
            labels = updated
        } catch { self.error = errText(error) }
    }

    private func setMilestone(_ number: Int?) async {
        var body: [String: Any] = [:]
        if let number { body["milestone"] = number } else { body["milestone"] = NSNull() }
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues/\(issue.number)", body: body, method: "PATCH")
            info = "已更新里程碑"
        } catch { self.error = errText(error) }
    }

    private func requestReviewer() async {
        do {
            try await API.shared.post("/repos/\(repoFullName)/pulls/\(issue.number)/requested_reviewers", body: ["reviewers": [reviewerName]])
            reviewerName = ""
            await load()
        } catch { self.error = errText(error) }
    }

    private func updateBranch() async {
        do {
            try await API.shared.action("/repos/\(repoFullName)/pulls/\(issue.number)/update-branch", method: "PUT")
            info = "已请求更新分支"
        } catch { self.error = errText(error) }
    }

    private func ready() async {
        do {
            try await API.shared.action("/repos/\(repoFullName)/pulls/\(issue.number)/ready_for_review", method: "POST")
            await load()
        } catch { self.error = errText(error) }
    }

    private func toDraft() async {
        do {
            try await API.shared.action("/repos/\(repoFullName)/pulls/\(issue.number)/convert_to_draft", method: "POST")
            await load()
        } catch { self.error = errText(error) }
    }
}

private let reactionChoices: [(String, String)] = [
    ("+1", "👍"), ("-1", "👎"), ("laugh", "😄"), ("hooray", "🎉"),
    ("confused", "😕"), ("heart", "❤️"), ("rocket", "🚀"), ("eyes", "👀")
]

private func reviewState(_ s: String) -> String {
    switch s {
    case "APPROVED": return "已批准"
    case "CHANGES_REQUESTED": return "要求修改"
    case "COMMENTED": return "已评论"
    case "DISMISSED": return "已忽略"
    default: return s
    }
}

struct EditIssueSheet: View {
    let repo: String
    let number: Int
    @State var title: String
    @State var bodyText: String
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    init(repo: String, number: Int, title: String, body: String, onSave: @escaping (String, String) -> Void) {
        self.repo = repo
        self.number = number
        _title = State(initialValue: title)
        _bodyText = State(initialValue: body)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("标题", text: $title)
            TextField("正文", text: $bodyText, axis: .vertical).lineLimit(8...20)
            if let error { Text(error).foregroundStyle(.red) }
            Button("保存") { Task { await save() } }
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }

    private func save() async {
        do {
            try await API.shared.post("/repos/\(repo)/issues/\(number)", body: ["title": title, "body": bodyText], method: "PATCH")
            onSave(title, bodyText)
            dismiss()
        } catch { self.error = errText(error) }
    }
}

struct MergeSheet: View {
    let repo: String
    let number: Int
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var method = "merge"
    @State private var title = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("方式", selection: $method) {
                Text("合并提交").tag("merge")
                Text("压缩").tag("squash")
                Text("变基").tag("rebase")
            }
            TextField("提交标题（可选）", text: $title)
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await merge() } } label: {
                HStack { if busy { ProgressView() }; Text("合并") }
            }
            .disabled(busy)
        }
        .navigationTitle("合并")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }

    private func merge() async {
        busy = true
        var body: [String: Any] = ["merge_method": method]
        if !title.isEmpty { body["commit_title"] = title }
        do {
            try await API.shared.put("/repos/\(repo)/pulls/\(number)/merge", body: body)
            onDone()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}

struct ReviewSheet: View {
    let repo: String
    let number: Int
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var event = "COMMENT"
    @State private var bodyText = ""
    @State private var path = ""
    @State private var line = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("结论", selection: $event) {
                Text("评论").tag("COMMENT")
                Text("批准").tag("APPROVE")
                Text("要求修改").tag("REQUEST_CHANGES")
            }
            TextField("意见", text: $bodyText, axis: .vertical).lineLimit(4...10)
            Section("行内评论（可选）") {
                TextField("文件路径", text: $path).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("行号", text: $line).keyboardType(.numberPad)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await send() } } label: {
                HStack { if busy { ProgressView() }; Text("提交审阅") }
            }
            .disabled(busy)
        }
        .navigationTitle("审阅")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }

    private func send() async {
        busy = true
        do {
            if !path.isEmpty, let n = Int(line) {
                let pull: PullDetail = try await API.shared.get("/repos/\(repo)/pulls/\(number)")
                try await API.shared.post("/repos/\(repo)/pulls/\(number)/comments", body: [
                    "body": bodyText.isEmpty ? "评论" : bodyText,
                    "commit_id": pull.head.sha,
                    "path": path,
                    "line": n,
                    "side": "RIGHT"
                ])
            }
            var body: [String: Any] = ["event": event]
            if !bodyText.isEmpty { body["body"] = bodyText }
            try await API.shared.post("/repos/\(repo)/pulls/\(number)/reviews", body: body)
            onDone()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}
