import Foundation

struct GHUser: Codable, Identifiable, Hashable {
    let id: Int
    let login: String
    let avatarUrl: String?
    let name: String?
    let bio: String?
    let publicRepos: Int?
    let followers: Int?
    let following: Int?
}

struct Repo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let language: String?
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let updatedAt: String?
    let defaultBranch: String?
    let htmlUrl: String
    let owner: GHUser

    enum CodingKeys: String, CodingKey {
        case id, name, fullName, description
        case isPrivate = "private"
        case language, stargazersCount, forksCount, openIssuesCount
        case updatedAt, defaultBranch, htmlUrl, owner
    }
}

struct RepoSearch: Codable {
    let items: [Repo]
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

    var isPR: Bool { pullRequest != nil }
    var repoFullName: String? {
        repositoryUrl?.replacingOccurrences(of: "https://api.github.com/repos/", with: "")
    }
}

struct IssueSearch: Codable {
    let items: [Issue]
}

struct Comment: Codable, Identifiable, Hashable {
    let id: Int
    let body: String?
    let user: GHUser
    let createdAt: String?
}

struct ContentItem: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let type: String
    let size: Int?
    let sha: String?
    var id: String { path }
}

struct Run: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let status: String?
    let conclusion: String?
    let headBranch: String?
    let event: String?
    let createdAt: String?
    let htmlUrl: String
    let runNumber: Int?
}

struct RunList: Codable {
    let workflowRuns: [Run]
}

struct Artifact: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let sizeInBytes: Int
    let expired: Bool
}

struct ArtifactList: Codable {
    let artifacts: [Artifact]
}

struct Workflow: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let state: String
}

struct WorkflowList: Codable {
    let workflows: [Workflow]
}

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
    let prerelease: Bool
    let publishedAt: String?
    let assets: [ReleaseAsset]

    var title: String {
        if let n = name, !n.isEmpty { return n }
        return tagName
    }
}

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
