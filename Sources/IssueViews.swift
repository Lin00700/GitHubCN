import SwiftUI

// MARK: - 全局议题 / PR（我参与的）

struct IssuesView: View {
    @EnvironmentObject var app: AppState
    @State private var kind = 0
    @State private var state = "open"
    @State private var items: [Issue] = []
    @State private var loading = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            List {
                Picker("类型", selection: $kind) {
                    Text("议题").tag(0)
                    Text("拉取请求").tag(1)
                }
                .pickerStyle(.segmented)
                Picker("状态", selection: $state) {
                    Text("打开").tag("open")
                    Text("已关闭").tag("closed")
                }
                .pickerStyle(.segmented)

                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
                ForEach(items) { i in
                    NavigationLink(destination: IssueDetailView(repoFullName: i.repoFullName ?? "", issue: i)) {
                        IssueRow(issue: i, showRepo: true)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && items.isEmpty {
                    ProgressView()
                } else if !loading && items.isEmpty && errorMsg == nil {
                    Text("没有内容").foregroundColor(.secondary)
                }
            }
            .navigationTitle("议题")
            .refreshable { await load() }
            .task(id: "\(kind)-\(state)-\(app.user?.login ?? "")") { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private func load() async {
        guard let login = app.user?.login else { return }
        loading = true
        errorMsg = nil
        let q = "involves:\(login) is:\(kind == 0 ? "issue" : "pr") is:\(state)"
        do {
            let r: IssueSearch = try await API.shared.get("/search/issues?q=\(enc(q))&sort=updated&per_page=50")
            items = r.items
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}

struct IssueRow: View {
    let issue: Issue
    let showRepo: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.headline).lineLimit(2)
                Text(meta).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if let c = issue.comments, c > 0 {
                Label("\(c)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var meta: String {
        let repoPart = showRepo ? "\(issue.repoFullName ?? "") " : ""
        return "\(repoPart)#\(issue.number) · \(issue.user.login) · \(relTime(issue.createdAt))"
    }

    private var merged: Bool { issue.pullRequest?.mergedAt != nil }

    private var icon: String {
        if issue.isPR { return "arrow.triangle.branch" }
        return issue.state == "open" ? "exclamationmark.circle" : "checkmark.circle"
    }

    private var color: Color {
        if issue.state == "open" { return .green }
        if issue.isPR && !merged { return .red }
        return .purple
    }
}

// MARK: - 仓库内的议题 / PR

struct IssueListView: View {
    let repoFullName: String
    let pulls: Bool
    @State private var state = "open"
    @State private var items: [Issue] = []
    @State private var loading = true
    @State private var errorMsg: String?

    var body: some View {
        List {
            if !pulls {
                NavigationLink(destination: NewIssueView(repoFullName: repoFullName, onCreated: { Task { await load() } })) {
                    Label("新建议题", systemImage: "plus.circle")
                }
            }
            Picker("状态", selection: $state) {
                Text("打开").tag("open")
                Text("已关闭").tag("closed")
            }
            .pickerStyle(.segmented)

            if let e = errorMsg {
                Text(e).font(.footnote).foregroundColor(.red)
            }
            ForEach(items) { i in
                NavigationLink(destination: IssueDetailView(repoFullName: repoFullName, issue: i)) {
                    IssueRow(issue: i, showRepo: false)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading {
                ProgressView()
            } else if items.isEmpty && errorMsg == nil {
                Text(pulls ? "没有拉取请求" : "没有议题").foregroundColor(.secondary)
            }
        }
        .task(id: state) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        errorMsg = nil
        do {
            let all: [Issue] = try await API.shared.get("/repos/\(repoFullName)/issues?state=\(state)&per_page=100")
            items = all.filter { $0.isPR == pulls }
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}

struct NewIssueView: View {
    let repoFullName: String
    var onCreated: () -> Void
    @Environment(\.presentationMode) private var mode
    @State private var title = ""
    @State private var bodyText = ""
    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        Form {
            Section(header: Text("标题")) {
                TextField("议题标题", text: $title)
            }
            Section(header: Text("描述")) {
                TextEditor(text: $bodyText).frame(minHeight: 140)
            }
            if let e = errorMsg {
                Section { Text(e).foregroundColor(.red) }
            }
            Section {
                Button("提交") { Task { await create() } }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .navigationTitle("新建议题")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() async {
        busy = true
        errorMsg = nil
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues", body: ["title": title, "body": bodyText])
            onCreated()
            mode.wrappedValue.dismiss()
        } catch {
            errorMsg = errText(error)
        }
        busy = false
    }
}

// MARK: - 议题 / PR 详情

struct IssueDetailView: View {
    let repoFullName: String
    let issue: Issue
    @State private var state: String
    @State private var comments: [Comment] = []
    @State private var zh = false
    @State private var titleZh: String?
    @State private var newComment = ""
    @State private var sending = false
    @State private var loading = true
    @State private var errorMsg: String?

    init(repoFullName: String, issue: Issue) {
        self.repoFullName = repoFullName
        self.issue = issue
        _state = State(initialValue: issue.state)
    }

    private var stateText: String {
        if issue.isPR && issue.pullRequest?.mergedAt != nil { return "已合并" }
        return state == "open" ? "打开" : "已关闭"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(zh ? (titleZh ?? issue.title) : issue.title)
                    .font(.title3.bold())

                HStack(spacing: 8) {
                    Text(stateText)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(state == "open" ? Color.green : Color.purple)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    Text("#\(issue.number) · \(issue.user.login) · \(relTime(issue.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                TranslateBar(on: $zh)

                if let b = issue.body, !b.isEmpty {
                    TranslatableMarkdown(text: b, translate: zh)
                } else {
                    Text("没有描述").foregroundColor(.secondary)
                }

                Divider()
                Text("评论 (\(comments.count))").font(.headline)
                if loading { ProgressView() }
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(c.user.login) · \(relTime(c.createdAt))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TranslatableMarkdown(text: c.body ?? "", translate: zh)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $newComment)
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    HStack {
                        Button(state == "open" ? "关闭" : "重新打开") {
                            Task { await toggleState() }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("评论") { Task { await send() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    }
                }
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
            }
            .padding()
        }
        .navigationTitle("#\(issue.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let u = URL(string: issue.htmlUrl) {
                    Link(destination: u) { Image(systemName: "safari") }
                }
            }
        }
        .task { await load() }
        .task(id: zh) {
            if zh && titleZh == nil {
                let r = await Translator.translate([issue.title])
                titleZh = r.first
            }
        }
    }

    private func load() async {
        do {
            let c: [Comment] = try await API.shared.get("/repos/\(repoFullName)/issues/\(issue.number)/comments?per_page=100")
            comments = c
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }

    private func send() async {
        sending = true
        errorMsg = nil
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues/\(issue.number)/comments", body: ["body": newComment])
            newComment = ""
            await load()
        } catch {
            errorMsg = errText(error)
        }
        sending = false
    }

    private func toggleState() async {
        errorMsg = nil
        let new = state == "open" ? "closed" : "open"
        do {
            try await API.shared.post("/repos/\(repoFullName)/issues/\(issue.number)", body: ["state": new], method: "PATCH")
            state = new
        } catch {
            errorMsg = errText(error)
        }
    }
}
