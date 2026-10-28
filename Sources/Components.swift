import SwiftUI
import UIKit
import QuickLook

struct AvatarView: View {
    let url: String?
    var side: CGFloat = 40

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct EmptyHint: View {
    let title: String
    var systemImage: String = "tray"
    var message: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
    }
}

struct InlineError: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
            if let retry {
                Button("重试", action: retry).font(.footnote)
            }
        }
    }
}

struct RepoRow: View {
    let repo: Repo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(repo.fullName)
                    .font(.headline)
                    .lineLimit(1)
                if repo.isArchived {
                    Text("已归档")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            if let d = repo.description, !d.isEmpty {
                Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                if let l = repo.language {
                    HStack(spacing: 4) {
                        Circle().fill(languageColor(l)).frame(width: 8, height: 8)
                        Text(l)
                    }
                }
                if repo.isFork {
                    Label("复刻", systemImage: "arrow.triangle.branch")
                }
                Label("\(repo.stargazersCount)", systemImage: "star")
                Label("\(repo.forksCount)", systemImage: "arrow.branch")
                Spacer(minLength: 0)
                Text(relTime(repo.updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct UserRow: View {
    let user: GHUser
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: user.avatarUrl, side: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.body)
                Text(subtitle ?? "@\(user.login)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

func issueBadge(_ issue: Issue) -> (String, Color) {
    if issue.isPR && issue.merged { return ("已合并", Theme.merged) }
    if issue.draft == true { return ("草稿", .secondary) }
    if issue.state == "open" { return (issue.isPR ? "打开" : "打开", Theme.open) }
    if issue.isPR { return ("已关闭", Theme.danger) }
    return ("已关闭", Theme.closed)
}

func issueIcon(_ issue: Issue) -> String {
    if issue.isPR { return "arrow.triangle.branch" }
    return issue.state == "open" ? "smallcircle.filled.circle" : "checkmark.circle"
}

struct IssueRow: View {
    let issue: Issue
    var showRepo: Bool = false

    var body: some View {
        let badge = issueBadge(issue)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issueIcon(issue))
                .foregroundStyle(badge.1)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.body).lineLimit(2)
                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let c = issue.comments, c > 0 {
                Label("\(c)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let repo = showRepo ? "\(issue.repoFullName ?? "") " : ""
        return "\(repo)#\(issue.number) · \(issue.user.login) · \(relTime(issue.updatedAt ?? issue.createdAt))"
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct RepoLoader: View {
    let fullName: String
    @State private var repo: Repo?
    @State private var error: String?

    var body: some View {
        Group {
            if let repo {
                RepoDetailView(repo: repo)
            } else if let error {
                InlineError(message: error) { Task { await load() } }.padding()
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            repo = try await API.shared.get("/repos/\(fullName)")
            error = nil
        } catch {
            self.error = errText(error) ?? "无法打开仓库"
        }
    }
}

struct IssueLoader: View {
    let repo: String
    let number: Int
    @State private var issue: Issue?
    @State private var error: String?

    var body: some View {
        Group {
            if let issue {
                IssueDetailView(repoFullName: repo, issue: issue)
            } else if let error {
                InlineError(message: error) { Task { await load() } }.padding()
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            issue = try await API.shared.get("/repos/\(repo)/issues/\(number)")
        } catch {
            self.error = errText(error) ?? "无法打开"
        }
    }
}

struct CommitLoader: View {
    let repo: String
    let sha: String
    @State private var repoObj: Repo?
    @State private var error: String?

    var body: some View {
        Group {
            if let repoObj {
                CommitDetailView(repo: repoObj, sha: sha)
            } else if let error {
                Text(error).foregroundStyle(.secondary).padding()
            } else {
                ProgressView()
            }
        }
        .task {
            do { repoObj = try await API.shared.get("/repos/\(repo)") }
            catch { self.error = errText(error) ?? "无法打开提交" }
        }
    }
}

struct ActionsLoader: View {
    let fullName: String
    @State private var repo: Repo?
    @State private var error: String?

    var body: some View {
        Group {
            if let repo {
                ActionsView(repo: repo)
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("行动")
        .task {
            do { repo = try await API.shared.get("/repos/\(fullName)") }
            catch { self.error = errText(error) ?? "无法打开" }
        }
    }
}

extension View {
    func repoContext(_ repo: Repo) -> some View {
        self.contextMenu {
            Button {
                UIPasteboard.general.string = repo.htmlUrl
                tapHaptic()
            } label: {
                Label("复制链接", systemImage: "doc.on.doc")
            }
            Button {
                Task { await toggleStar(repo) }
            } label: {
                Label("切换星标", systemImage: "star")
            }
            Button {
                if let u = URL(string: repo.htmlUrl) {
                    UIApplication.shared.open(u)
                }
            } label: {
                Label("在 Safari 中打开", systemImage: "safari")
            }
        }
    }
}

func toggleStar(_ repo: Repo) async {
    let on = await API.shared.exists("/user/starred/\(repo.fullName)")
    try? await API.shared.action("/user/starred/\(repo.fullName)", method: on ? "DELETE" : "PUT")
    tapHaptic()
}

func eventSummary(_ e: GHEvent) -> String {
    let p = e.payload
    switch e.type {
    case "PushEvent":
        let n = p?.size ?? p?.commits?.count ?? 0
        let ref = (p?.ref ?? "").replacingOccurrences(of: "refs/heads/", with: "")
        return "推送了 \(n) 个提交到 \(ref)"
    case "WatchEvent":
        return "标星了仓库"
    case "ForkEvent":
        return "复刻了仓库"
    case "IssuesEvent":
        return "\(zhAction(p?.action))问题 \(p?.issue?.title ?? "")"
    case "IssueCommentEvent":
        return "评论了问题 \(p?.issue?.title ?? "")"
    case "PullRequestEvent":
        return "\(zhAction(p?.action))拉取请求 \(p?.pullRequest?.title ?? "")"
    case "PullRequestReviewEvent":
        return "审阅了拉取请求 \(p?.pullRequest?.title ?? "")"
    case "PullRequestReviewCommentEvent":
        return "评论了拉取请求代码"
    case "CreateEvent":
        return "创建了\(p?.refType == "tag" ? "标签" : "分支") \(p?.ref ?? "")"
    case "DeleteEvent":
        return "删除了\(p?.refType == "tag" ? "标签" : "分支") \(p?.ref ?? "")"
    case "ReleaseEvent":
        return "\(zhAction(p?.action))发行版 \(p?.release?.name ?? p?.release?.tagName ?? "")"
    case "CommitCommentEvent":
        return "评论了提交"
    case "MemberEvent":
        return "\(zhAction(p?.action))了成员"
    case "PublicEvent":
        return "将仓库设为公开"
    case "DiscussionEvent":
        return "\(zhAction(p?.action))讨论"
    case "GollumEvent":
        return "更新了维基"
    default:
        return e.type.replacingOccurrences(of: "Event", with: "")
    }
}

func eventSymbol(_ type: String) -> String {
    switch type {
    case "PushEvent": return "arrow.up.circle"
    case "WatchEvent": return "star"
    case "ForkEvent": return "arrow.triangle.branch"
    case "IssuesEvent", "IssueCommentEvent": return "smallcircle.filled.circle"
    case "PullRequestEvent", "PullRequestReviewEvent", "PullRequestReviewCommentEvent": return "arrow.triangle.branch"
    case "ReleaseEvent": return "tag"
    case "CreateEvent": return "plus.circle"
    case "DeleteEvent": return "minus.circle"
    case "DiscussionEvent": return "bubble.left.and.bubble.right"
    case "GollumEvent": return "book"
    default: return "circle"
    }
}

private func zhAction(_ action: String?) -> String {
    switch action ?? "" {
    case "opened": return "打开了"
    case "closed": return "关闭了"
    case "reopened": return "重新打开了"
    case "created": return "创建了"
    case "published": return "发布了"
    case "started": return ""
    case "reviewed": return "审阅了"
    default: return action.map { $0.isEmpty ? "" : "\($0) " } ?? ""
    }
}

struct EventLink: View {
    let event: GHEvent

    var body: some View {
        let repo = event.repo.name
        switch event.type {
        case "IssuesEvent", "IssueCommentEvent":
            if let n = event.payload?.issue?.number {
                NavigationLink { IssueLoader(repo: repo, number: n) } label: { row }
            } else {
                NavigationLink { RepoLoader(fullName: repo) } label: { row }
            }
        case "PullRequestEvent", "PullRequestReviewEvent", "PullRequestReviewCommentEvent":
            if let n = event.payload?.pullRequest?.number {
                NavigationLink { IssueLoader(repo: repo, number: n) } label: { row }
            } else {
                NavigationLink { RepoLoader(fullName: repo) } label: { row }
            }
        case "ReleaseEvent":
            NavigationLink { ReleasesLoader(fullName: repo) } label: { row }
        case "PushEvent":
            NavigationLink { CommitsLoader(fullName: repo) } label: { row }
        default:
            NavigationLink { RepoLoader(fullName: repo) } label: { row }
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: event.actor.avatarUrl, side: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.actor.login).font(.subheadline.weight(.semibold)) +
                Text(" \(eventSummary(event))").font(.subheadline)
                Text("\(event.repo.name) · \(relTime(event.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReleasesLoader: View {
    let fullName: String
    @State private var repo: Repo?
    @State private var error: String?
    var body: some View {
        Group {
            if let repo { ReleasesView(repo: repo) }
            else if let error { Text(error).foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .navigationTitle("发行版")
        .task {
            do { repo = try await API.shared.get("/repos/\(fullName)") }
            catch { self.error = errText(error) }
        }
    }
}

struct CommitsLoader: View {
    let fullName: String
    @State private var repo: Repo?
    @State private var error: String?
    var body: some View {
        Group {
            if let repo { CommitsView(repo: repo, ref: repo.branch) }
            else if let error { Text(error).foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task {
            do { repo = try await API.shared.get("/repos/\(fullName)") }
            catch { self.error = errText(error) }
        }
    }
}
