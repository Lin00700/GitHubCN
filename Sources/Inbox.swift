import SwiftUI

struct InboxView: View {
    @EnvironmentObject var app: AppState
    @State private var mode = 0
    @State private var notes: [Note] = []
    @State private var loading = false
    @State private var error: String?

    private var grouped: [(String, [Note])] {
        var order: [String] = []
        var map: [String: [Note]] = [:]
        for n in notes {
            let key = n.repository.fullName
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(n)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        List {
            Picker("范围", selection: $mode) {
                Text("未读").tag(0)
                Text("参与").tag(1)
                Text("全部").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && notes.isEmpty { ProgressView() }
            if !loading && notes.isEmpty && error == nil {
                EmptyHint(title: mode == 0 ? "没有未读通知" : "没有通知", systemImage: "bell", message: "下拉可以刷新。")
            }
            ForEach(grouped, id: \.0) { repo, items in
                Section(repo) {
                    ForEach(items) { n in
                        NavigationLink { NoteRouter(note: n) } label: { NoteRow(note: n) }
                            .swipeActions {
                                Button { Task { await markRead(n) } } label: { Label("已读", systemImage: "envelope.open") }
                                    .tint(.blue)
                                Button(role: .destructive) { Task { await markDone(n) } } label: { Label("完成", systemImage: "checkmark") }
                            }
                    }
                }
            }
        }
        .navigationTitle("通知")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("全部已读") { Task { await markAll() } }
                    .disabled(notes.isEmpty)
            }
        }
        .refreshable { await load() }
        .task(id: mode) { await load() }
    }

    private func load() async {
        loading = notes.isEmpty
        error = nil
        var path = "/notifications?per_page=50"
        if mode == 1 { path += "&participating=true" }
        if mode == 2 { path += "&all=true" }
        do {
            notes = try await API.shared.get(path)
            if mode == 0 { app.unreadCount = notes.count }
        } catch {
            self.error = errText(error)
        }
        loading = false
    }

    private func markRead(_ n: Note) async {
        try? await API.shared.action("/notifications/threads/\(n.id)", method: "PATCH")
        notes.removeAll { $0.id == n.id }
        await app.refreshUnread()
    }

    private func markDone(_ n: Note) async {
        try? await API.shared.delete("/notifications/threads/\(n.id)")
        notes.removeAll { $0.id == n.id }
        await app.refreshUnread()
    }

    private func markAll() async {
        do {
            try await API.shared.post("/notifications", body: [:], method: "PUT")
            if mode == 0 { notes = [] }
            await app.refreshUnread()
            tapHaptic()
        } catch {
            self.error = errText(error)
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(note.unread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.subject.title).font(.body).lineLimit(2)
                Text("\(reasonText) · \(relTime(note.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.unread ? "未读 " : "")\(note.subject.title)，\(note.repository.fullName)")
    }

    private var icon: String {
        switch note.subject.type {
        case "Issue": return "exclamationmark.circle"
        case "PullRequest": return "arrow.triangle.branch"
        case "Release": return "tag"
        case "Discussion": return "bubble.left.and.bubble.right"
        case "Commit": return "number"
        case "CheckSuite": return "play.circle"
        default: return "bell"
        }
    }

    private var reasonText: String {
        switch note.reason {
        case "assign": return "指派给你"
        case "mention": return "提及了你"
        case "review_requested": return "请求你审阅"
        case "subscribed": return "你订阅的"
        case "author": return "你创建的"
        case "comment": return "有新评论"
        case "ci_activity": return "CI 动态"
        case "state_change": return "状态变更"
        case "team_mention": return "团队被提及"
        case "security_alert": return "安全警报"
        default: return note.reason
        }
    }
}

struct NoteRouter: View {
    let note: Note

    var body: some View {
        Group {
            switch note.subject.type {
            case "Issue", "PullRequest":
                if let url = note.subject.url {
                    RemoteIssue(url: url, repo: note.repository.fullName)
                } else {
                    RepoLoader(fullName: note.repository.fullName)
                }
            case "Discussion":
                if let n = discussionNumber(from: note.subject.url) {
                    DiscussionDetailView(fullName: note.repository.fullName, number: n)
                } else {
                    DiscussionsView(fullName: note.repository.fullName)
                }
            case "Commit":
                if let sha = note.subject.url?.split(separator: "/").last {
                    CommitLoader(repo: note.repository.fullName, sha: String(sha))
                } else {
                    RepoLoader(fullName: note.repository.fullName)
                }
            case "CheckSuite":
                ActionsLoader(fullName: note.repository.fullName)
            case "Release":
                ReleasesLoader(fullName: note.repository.fullName)
            default:
                RepoLoader(fullName: note.repository.fullName)
            }
        }
        .task {
            try? await API.shared.action("/notifications/threads/\(note.id)", method: "PATCH")
        }
    }
}

private struct RemoteIssue: View {
    let url: String
    let repo: String
    @State private var issue: Issue?
    @State private var error: String?

    var body: some View {
        Group {
            if let issue {
                IssueDetailView(repoFullName: repo, issue: issue)
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.secondary)
                    if let u = URL(string: "https://github.com/\(repo)") {
                        Link("在 Safari 打开", destination: u)
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            do { issue = try await API.shared.get(url) }
            catch { self.error = errText(error) ?? "这类通知暂时无法在应用内打开" }
        }
    }
}

func discussionNumber(from url: String?) -> Int? {
    guard let url, let last = url.split(separator: "/").last else { return nil }
    return Int(last)
}
