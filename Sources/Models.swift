import Foundation
import SwiftUI

// MARK: - 用户

struct GHUser: Codable, Identifiable, Hashable {
    let id: Int
    let login: String
    let avatarUrl: String?
    let name: String?
    let bio: String?
    let company: String?
    let location: String?
    let blog: String?
    let twitterUsername: String?
    let email: String?
    let publicRepos: Int?
    let publicGists: Int?
    let followers: Int?
    let following: Int?
    let htmlUrl: String?
    let type: String?
    let siteAdmin: Bool?

    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? login }
}

struct GHActor: Codable, Hashable {
    let login: String
    let avatarUrl: String?
}

// MARK: - 仓库

struct GHLicense: Codable, Hashable {
    let key: String?
    let name: String?
    let spdxId: String?
}

struct RepoPermissions: Codable, Hashable {
    let admin: Bool?
    let maintain: Bool?
    let push: Bool?
    let triage: Bool?
    let pull: Bool?
}

struct RepoParent: Codable, Hashable {
    let fullName: String
    let htmlUrl: String?
}

struct Repo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let language: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let subscribersCount: Int
    let size: Int
    let updatedAt: String?
    let pushedAt: String?
    let defaultBranch: String?
    let htmlUrl: String
    let homepage: String?
    let visibility: String?
    let topics: [String]
    let license: GHLicense?
    let permissions: RepoPermissions?
    let parent: RepoParent?
    let owner: GHUser

    var canAdmin: Bool { permissions?.admin == true }
    var canPush: Bool {
        permissions?.admin == true || permissions?.maintain == true || permissions?.push == true
    }
    var branch: String { defaultBranch ?? "main" }

    enum CodingKeys: String, CodingKey {
        case id, name, fullName, description, language, stargazersCount, forksCount
        case openIssuesCount, subscribersCount, size, updatedAt, pushedAt
        case defaultBranch, htmlUrl, homepage, visibility, topics, license, permissions, parent, owner
        case isPrivate = "private"
        case isFork = "fork"
        case isArchived = "archived"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fullName = try c.decode(String.self, forKey: .fullName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        isFork = try c.decodeIfPresent(Bool.self, forKey: .isFork) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        language = try c.decodeIfPresent(String.self, forKey: .language)
        stargazersCount = try c.decodeIfPresent(Int.self, forKey: .stargazersCount) ?? 0
        forksCount = try c.decodeIfPresent(Int.self, forKey: .forksCount) ?? 0
        openIssuesCount = try c.decodeIfPresent(Int.self, forKey: .openIssuesCount) ?? 0
        subscribersCount = try c.decodeIfPresent(Int.self, forKey: .subscribersCount) ?? 0
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        pushedAt = try c.decodeIfPresent(String.self, forKey: .pushedAt)
        defaultBranch = try c.decodeIfPresent(String.self, forKey: .defaultBranch)
        htmlUrl = try c.decodeIfPresent(String.self, forKey: .htmlUrl) ?? "https://github.com/\(fullName)"
        homepage = try c.decodeIfPresent(String.self, forKey: .homepage)
        visibility = try c.decodeIfPresent(String.self, forKey: .visibility)
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        license = try c.decodeIfPresent(GHLicense.self, forKey: .license)
        permissions = try c.decodeIfPresent(RepoPermissions.self, forKey: .permissions)
        parent = try c.decodeIfPresent(RepoParent.self, forKey: .parent)
        owner = try c.decode(GHUser.self, forKey: .owner)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fullName, forKey: .fullName)
        try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(htmlUrl, forKey: .htmlUrl)
        try c.encode(owner, forKey: .owner)
    }
}

struct RepoSearch: Codable { let items: [Repo] }

struct LicenseTemplate: Codable, Identifiable, Hashable {
    let key: String
    let name: String
    let spdxId: String?
    var id: String { key }
}

// MARK: - 议题 / PR

struct GHLabel: Codable, Hashable, Identifiable {
    let name: String
    let color: String?
    let description: String?
    var id: String { name }
}

struct Milestone: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let description: String?
    let state: String?
    let openIssues: Int?
    let closedIssues: Int?
    let dueOn: String?
}

struct Reactions: Codable, Hashable {
    let totalCount: Int
    let plusOne: Int
    let minusOne: Int
    let laugh: Int
    let hooray: Int
    let confused: Int
    let heart: Int
    let rocket: Int
    let eyes: Int

    private struct Key: CodingKey {
        var stringValue: String
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func n(_ keys: String...) -> Int {
            for k in keys {
                if let v = try? c.decode(Int.self, forKey: Key(k)) { return v }
            }
            return 0
        }
        totalCount = n("totalCount", "total_count")
        plusOne = n("+1", "plusOne")
        minusOne = n("-1", "minusOne")
        laugh = n("laugh")
        hooray = n("hooray")
        confused = n("confused")
        heart = n("heart")
        rocket = n("rocket")
        eyes = n("eyes")
    }

    func encode(to encoder: Encoder) throws {}
}

struct PRRef: Codable, Hashable {
    let mergedAt: String?
}

struct Issue: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: GHUser
    let comments: Int?
    let createdAt: String?
    let updatedAt: String?
    let htmlUrl: String
    let pullRequest: PRRef?
    let repositoryUrl: String?
    let labels: [GHLabel]?
    let assignees: [GHUser]?
    let milestone: Milestone?
    let locked: Bool?
    let draft: Bool?
    let mergedAt: String?
    let reactions: Reactions?
    let authorAssociation: String?

    var isPR: Bool { pullRequest != nil || draft != nil || mergedAt != nil }
    var merged: Bool { pullRequest?.mergedAt != nil || mergedAt != nil }
    var repoFullName: String? {
        repositoryUrl?.replacingOccurrences(of: "https://api.github.com/repos/", with: "")
    }
}

struct IssueSearch: Codable { let items: [Issue] }

struct Comment: Codable, Identifiable, Hashable {
    let id: Int
    let body: String?
    let user: GHUser
    let createdAt: String?
    let updatedAt: String?
    let authorAssociation: String?
}

struct PRBranch: Codable, Hashable {
    let ref: String
    let sha: String
    let label: String?
}

struct PullDetail: Codable {
    let number: Int
    let state: String
    let title: String
    let body: String?
    let merged: Bool?
    let mergeable: Bool?
    let mergeableState: String?
    let draft: Bool?
    let htmlUrl: String
    let user: GHUser
    let head: PRBranch
    let base: PRBranch
    let commits: Int?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
}

struct PRReview: Codable, Identifiable, Hashable {
    let id: Int
    let user: GHUser?
    let body: String?
    let state: String
    let submittedAt: String?
}

struct PRComment: Codable, Identifiable, Hashable {
    let id: Int
    let user: GHUser?
    let body: String?
    let path: String?
    let line: Int?
    let diffHunk: String?
    let createdAt: String?
    let commitId: String?
}

struct GHTeam: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String?
}

struct ReviewerList: Codable {
    let users: [GHUser]
    let teams: [GHTeam]
}

// MARK: - 文件 / 提交 / 分支

struct ContentItem: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let type: String
    let size: Int?
    let sha: String?
    let htmlUrl: String?
    let downloadUrl: String?
    var id: String { path }
}

struct RemoteFile: Codable {
    let type: String?
    let encoding: String?
    let content: String?
    let sha: String?
    let size: Int?
    let htmlUrl: String?
    let downloadUrl: String?
    let path: String?

    var decoded: Data? {
        guard let content else { return nil }
        return Data(base64Encoded: content, options: .ignoreUnknownCharacters)
    }

    var text: String? {
        guard let decoded else { return nil }
        return String(data: decoded, encoding: .utf8)
    }
}

struct GHBranch: Codable, Identifiable, Hashable {
    let name: String
    let protected: Bool
    var id: String { name }
}

struct GHTag: Codable, Identifiable, Hashable {
    let name: String
    let commit: GitObj
    var id: String { name }
}

struct GitActor: Codable, Hashable {
    let name: String?
    let email: String?
    let date: String?
}

struct CommitMeta: Codable, Hashable {
    let message: String
    let author: GitActor?
    let committer: GitActor?
}

struct GHCommit: Codable, Identifiable, Hashable {
    let sha: String
    let htmlUrl: String?
    let commit: CommitMeta
    let author: GHUser?
    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
    var titleLine: String { commit.message.split(separator: "\n").first.map(String.init) ?? commit.message }
}

struct CommitFile: Codable, Identifiable, Hashable {
    let filename: String
    let status: String?
    let additions: Int?
    let deletions: Int?
    let patch: String?
    var id: String { filename }
}

struct CommitStats: Codable, Hashable {
    let additions: Int?
    let deletions: Int?
    let total: Int?
}

struct CommitDetail: Codable, Identifiable {
    let sha: String
    let htmlUrl: String?
    let commit: CommitMeta
    let author: GHUser?
    let stats: CommitStats?
    let files: [CommitFile]?
    var id: String { sha }
}

struct CompareResult: Codable {
    let status: String?
    let aheadBy: Int?
    let behindBy: Int?
    let totalCommits: Int?
    let htmlUrl: String?
    let files: [CommitFile]?
    let commits: [GHCommit]?
}

struct CommitStatusItem: Codable, Hashable, Identifiable {
    let id: Int?
    let context: String?
    let state: String?
    let description: String?
    let targetUrl: String?
    var stable: String { "\(id ?? 0)-\(context ?? "")-\(state ?? "")" }
    var ident: String { stable }
}

struct CombinedStatus: Codable {
    let state: String?
    let statuses: [CommitStatusItem]
}

struct CheckRun: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let status: String?
    let conclusion: String?
    let htmlUrl: String?
    let startedAt: String?
}

struct CheckRunList: Codable { let checkRuns: [CheckRun] }

// MARK: - Actions / 发行

struct Run: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let status: String?
    let conclusion: String?
    let headBranch: String?
    let headSha: String?
    let event: String?
    let createdAt: String?
    let htmlUrl: String
    let runNumber: Int?
}

struct RunList: Codable { let workflowRuns: [Run] }

struct Artifact: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let sizeInBytes: Int
    let expired: Bool
}

struct ArtifactList: Codable { let artifacts: [Artifact] }

struct Workflow: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let state: String
    let path: String?
    let htmlUrl: String?
}

struct WorkflowList: Codable { let workflows: [Workflow] }

struct ReleaseAsset: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let size: Int
    let browserDownloadUrl: String
}

struct Release: Codable, Identifiable, Hashable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool
    let publishedAt: String?
    let htmlUrl: String?
    let targetCommitish: String?
    let assets: [ReleaseAsset]

    var title: String {
        if let n = name, !n.isEmpty { return n }
        return tagName
    }
}

// MARK: - 通知 / 动态

struct NoteSubject: Codable, Hashable {
    let title: String
    let type: String
    let url: String?
}

struct NoteRepo: Codable, Hashable {
    let fullName: String
}

struct Note: Codable, Identifiable, Hashable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: String?
    let subject: NoteSubject
    let repository: NoteRepo
}

struct EventCommit: Codable, Hashable {
    let sha: String?
    let message: String?
}

struct EventSnippet: Codable, Hashable {
    let number: Int?
    let title: String?
}

struct EventRelease: Codable, Hashable {
    let tagName: String?
    let name: String?
}

struct EventPayload: Codable, Hashable {
    let action: String?
    let ref: String?
    let refType: String?
    let size: Int?
    let commits: [EventCommit]?
    let issue: EventSnippet?
    let pullRequest: EventSnippet?
    let release: EventRelease?
}

struct GHEvent: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let actor: GHActor
    let repo: EventRepo
    let createdAt: String?
    let payload: EventPayload?
}

struct EventRepo: Codable, Hashable {
    let name: String
}

// MARK: - 搜索

struct UserSearch: Codable { let items: [GHUser] }

struct CodeHit: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let sha: String?
    let htmlUrl: String
    let repository: Repo
    var id: String { htmlUrl }
}

struct CodeSearch: Codable { let items: [CodeHit] }

struct CommitHit: Codable, Identifiable, Hashable {
    let sha: String
    let htmlUrl: String?
    let commit: CommitMeta
    let author: GHUser?
    let repository: Repo
    var id: String { sha + repository.fullName }
}

struct CommitSearch: Codable { let items: [CommitHit] }

struct GHTopic: Codable, Identifiable, Hashable {
    let name: String
    let displayName: String?
    let shortDescription: String?
    var id: String { name }
}

struct TopicSearch: Codable { let items: [GHTopic] }

// MARK: - 社交 / 账号

struct Org: Codable, Identifiable, Hashable {
    let id: Int
    let login: String
    let avatarUrl: String?
    let description: String?
    let name: String?
    let blog: String?
    let location: String?
    let email: String?
    let publicRepos: Int?
    let followers: Int?
    let htmlUrl: String?
}

struct RepoInvite: Codable, Identifiable, Hashable {
    let id: Int
    let permissions: String?
    let createdAt: String?
    let repository: Repo
}

struct GHEmail: Codable, Identifiable, Hashable {
    let email: String
    let verified: Bool
    let primary: Bool
    let visibility: String?
    var id: String { email }
}

struct SSHKey: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let key: String
    let createdAt: String?
}

struct RateResource: Codable, Hashable {
    let limit: Int
    let remaining: Int
    let reset: Int
    let used: Int?
}

struct RateResources: Codable {
    let core: RateResource
    let search: RateResource?
    let graphql: RateResource?
}

struct RateLimit: Codable { let resources: RateResources }

struct Collaborator: Codable, Identifiable, Hashable {
    let id: Int
    let login: String
    let avatarUrl: String?
    let roleName: String?
    let permissions: RepoPermissions?
}

// MARK: - Gist / 代码空间 / 包

struct GistFile: Codable, Hashable {
    let filename: String?
    let language: String?
    let size: Int?
    let content: String?
    let rawUrl: String?
}

struct Gist: Codable, Identifiable, Hashable {
    let id: String
    let description: String?
    let isPublic: Bool
    let htmlUrl: String
    let files: [String: GistFile]
    let createdAt: String?
    let updatedAt: String?
    let owner: GHUser?
    let comments: Int?

    enum CodingKeys: String, CodingKey {
        case id, description, files, owner, comments, htmlUrl, createdAt, updatedAt
        case isPublic = "public"
    }
}

struct GistComment: Codable, Identifiable, Hashable {
    let id: Int
    let body: String?
    let user: GHUser?
    let createdAt: String?
}

struct CodespaceMachine: Codable, Hashable {
    let name: String?
    let displayName: String?
    let operatingSystem: String?
}

struct CodespaceGit: Codable, Hashable {
    let ahead: Int?
    let behind: Int?
    let ref: String?
    let hasUncommittedChanges: Bool?
    let hasUnpushedChanges: Bool?
}

struct Codespace: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let displayName: String?
    let state: String?
    let webUrl: String?
    let createdAt: String?
    let updatedAt: String?
    let lastUsedAt: String?
    let repository: Repo?
    let machine: CodespaceMachine?
    let gitStatus: CodespaceGit?
}

struct CodespaceList: Codable { let codespaces: [Codespace] }

struct GHPackage: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let packageType: String
    let visibility: String?
    let htmlUrl: String?
    let createdAt: String?
}

// MARK: - 洞察 / 管理

struct Contributor: Codable, Hashable, Identifiable {
    let id: Int?
    let login: String?
    let avatarUrl: String?
    let contributions: Int?
    let htmlUrl: String?
    var ident: String { login ?? "anon-\(id ?? contributions ?? 0)" }
}

struct TrafficPoint: Codable, Identifiable, Hashable {
    let timestamp: String
    let count: Int
    let uniques: Int
    var id: String { timestamp }
}

struct TrafficViews: Codable {
    let count: Int
    let uniques: Int
    let views: [TrafficPoint]?
}

struct TrafficClones: Codable {
    let count: Int
    let uniques: Int
    let clones: [TrafficPoint]?
}

struct WeekActivity: Codable, Identifiable, Hashable {
    let total: Int
    let week: Int
    let days: [Int]?
    var id: Int { week }
}

struct Participation: Codable {
    let all: [Int]
    let owner: [Int]
}

struct CommunityProfile: Codable {
    let healthPercentage: Int?
    let description: String?
}

struct GHPages: Decodable {
    let status: String?
    let htmlUrl: String?
    let cname: String?
}

struct GHEnvironment: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let htmlUrl: String?
}

struct EnvList: Codable { let environments: [GHEnvironment] }

struct ActionsSecret: Codable, Identifiable, Hashable {
    let name: String
    let updatedAt: String?
    var id: String { name }
}

struct SecretList: Codable { let secrets: [ActionsSecret] }

struct ActionsVariable: Codable, Identifiable, Hashable {
    let name: String
    let value: String?
    let updatedAt: String?
    var id: String { name }
}

struct VariableList: Codable { let variables: [ActionsVariable] }

struct Webhook: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let active: Bool
    let events: [String]
}

struct DeployKey: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let readOnly: Bool
    let createdAt: String?
}

struct Ruleset: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let target: String?
    let enforcement: String?
}

struct GHRunner: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let os: String?
    let status: String?
    let busy: Bool?
}

struct RunnerList: Codable { let runners: [GHRunner] }

struct ActionsCache: Codable, Identifiable, Hashable {
    let id: Int
    let ref: String?
    let key: String?
    let sizeInBytes: Int?
}

struct CacheList: Codable {
    let totalCount: Int?
    let actionsCaches: [ActionsCache]
}

struct Advisory: Codable, Hashable {
    let ghsaId: String?
    let summary: String?
    let severity: String?
    let description: String?
}

struct DepPackage: Codable, Hashable {
    let name: String?
    let ecosystem: String?
}

struct DepInfo: Codable, Hashable {
    let package: DepPackage?
    let manifestPath: String?
}

struct DependabotAlert: Codable, Identifiable, Hashable {
    let number: Int
    let state: String
    let htmlUrl: String?
    let createdAt: String?
    let dependency: DepInfo?
    let securityAdvisory: Advisory?
    var id: Int { number }
}

struct SecretAlert: Codable, Identifiable, Hashable {
    let number: Int
    let state: String
    let secretType: String?
    let htmlUrl: String?
    let createdAt: String?
    var id: Int { number }
}

struct ScanRule: Codable, Hashable {
    let id: String?
    let description: String?
    let severity: String?
}

struct CodeScanAlert: Codable, Identifiable, Hashable {
    let number: Int
    let state: String
    let htmlUrl: String?
    let createdAt: String?
    let rule: ScanRule?
    var id: Int { number }
}

struct GlobalAdvisory: Codable, Identifiable, Hashable {
    let ghsaId: String
    let summary: String?
    let severity: String?
    let description: String?
    let publishedAt: String?
    let htmlUrl: String?
    var id: String { ghsaId }
}

struct Subscription: Codable {
    let subscribed: Bool?
    let ignored: Bool?
    let reason: String?
}

// MARK: - 时间线（手动解析，事件结构不统一）

struct TimelineRow: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
    let time: String?
}

func parseTimeline(_ any: Any) -> [TimelineRow] {
    guard let items = any as? [Any] else { return [] }
    var rows: [TimelineRow] = []
    for (idx, item) in items.enumerated() {
        guard let o = item as? [String: Any] else { continue }
        let event = o["event"] as? String ?? ""
        let actor = (o["actor"] as? [String: Any])?["login"] as? String
            ?? (o["user"] as? [String: Any])?["login"] as? String
            ?? ""
        let created = (o["created_at"] as? String) ?? (o["submitted_at"] as? String)
        let body = o["body"] as? String
        let label = (o["label"] as? [String: Any])?["name"] as? String
        let assignee = (o["assignee"] as? [String: Any])?["login"] as? String
        let sha = (o["sha"] as? String) ?? (o["commit_id"] as? String)
        let who = actor.isEmpty ? "有人" : actor
        let title: String
        switch event {
        case "commented": title = "\(who) 发表了评论"
        case "closed": title = "\(who) 关闭了"
        case "reopened": title = "\(who) 重新打开"
        case "labeled": title = "\(who) 添加了标签 \(label ?? "")"
        case "unlabeled": title = "\(who) 移除了标签 \(label ?? "")"
        case "assigned": title = "\(who) 指派给 \(assignee ?? "")"
        case "unassigned": title = "\(who) 取消指派 \(assignee ?? "")"
        case "milestoned": title = "\(who) 设置了里程碑"
        case "demilestoned": title = "\(who) 移除了里程碑"
        case "renamed": title = "\(who) 修改了标题"
        case "locked": title = "\(who) 锁定了对话"
        case "unlocked": title = "\(who) 解锁了对话"
        case "pinned": title = "\(who) 置顶"
        case "unpinned": title = "\(who) 取消置顶"
        case "reviewed": title = "\(who) 提交了审阅"
        case "merged": title = "\(who) 合并了"
        case "committed": title = "提交 \((sha ?? "").prefix(7))"
        case "cross-referenced", "referenced": title = "\(who) 关联了其他内容"
        case "mentioned": title = "\(who) 被提及"
        case "subscribed": title = "\(who) 订阅了"
        case "head_ref_force_pushed": title = "\(who) 强推了分支"
        case "head_ref_deleted": title = "头部分支已删除"
        case "ready_for_review": title = "\(who) 标记为可审阅"
        case "convert_to_draft": title = "\(who) 转为草稿"
        case "review_requested": title = "\(who) 请求了审阅"
        default:
            if event.isEmpty { continue }
            title = "\(who) · \(event)"
        }
        let detail = (body?.isEmpty == false) ? body : nil
        rows.append(TimelineRow(id: "\(idx)-\(event)-\(created ?? "")", title: title, detail: detail, time: created))
    }
    return rows
}

func splitRepo(_ full: String) -> (owner: String, name: String) {
    let parts = full.split(separator: "/", maxSplits: 1).map(String.init)
    return (parts.first ?? full, parts.count > 1 ? parts[1] : "")
}

func languageColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "swift": return Color(red: 0.94, green: 0.31, blue: 0.18)
    case "javascript": return Color(red: 0.94, green: 0.86, blue: 0.25)
    case "typescript": return Color(red: 0.18, green: 0.45, blue: 0.78)
    case "python": return Color(red: 0.22, green: 0.45, blue: 0.65)
    case "go": return Color(red: 0.00, green: 0.68, blue: 0.84)
    case "rust": return Color(red: 0.87, green: 0.33, blue: 0.18)
    case "java": return Color(red: 0.69, green: 0.38, blue: 0.09)
    case "kotlin": return Color(red: 0.66, green: 0.40, blue: 0.94)
    case "ruby": return Color(red: 0.70, green: 0.13, blue: 0.18)
    case "c++", "c": return Color(red: 0.20, green: 0.40, blue: 0.67)
    case "html": return Color(red: 0.89, green: 0.29, blue: 0.16)
    case "css", "scss": return Color(red: 0.33, green: 0.22, blue: 0.60)
    case "shell", "bash": return Color(red: 0.34, green: 0.78, blue: 0.27)
    case "php": return Color(red: 0.31, green: 0.33, blue: 0.58)
    case "dart": return Color(red: 0.00, green: 0.71, blue: 0.85)
    default: return .secondary
    }
}
