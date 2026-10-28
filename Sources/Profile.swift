import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var confirm = false
    @State private var pinned: [PinnedRepo] = []
    @State private var contribTotal: Int?
    @State private var weeks: [[ContribDay]] = []
    @State private var sponsors: [String] = []

    var body: some View {
        List {
            if let u = app.user {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(url: u.avatarUrl, side: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.displayName).font(.title3.bold())
                            Text("@\(u.login)").foregroundStyle(.secondary)
                            if let b = u.bio, !b.isEmpty {
                                Text(b).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        NavigationLink { FollowListView(login: u.login, followers: false) } label: {
                            stat("正在关注", u.following ?? 0)
                        }
                        NavigationLink { FollowListView(login: u.login, followers: true) } label: {
                            stat("关注者", u.followers ?? 0)
                        }
                        NavigationLink { MyReposView() } label: {
                            stat("仓库", u.publicRepos ?? 0)
                        }
                    }
                    .buttonStyle(.plain)
                    if let n = contribTotal {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("近一年贡献 \(n)")
                                .font(.subheadline)
                            ContributionGrid(weeks: weeks)
                        }
                    }
                }
                if !pinned.isEmpty {
                    Section("置顶") {
                        ForEach(pinned) { p in
                            NavigationLink { RepoLoader(fullName: p.fullName) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.fullName).font(.headline)
                                    if let d = p.description, !d.isEmpty {
                                        Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Label("\(p.stars)", systemImage: "star").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink { MyReposView() } label: { Label("仓库", systemImage: "book.closed") }
                NavigationLink { StarredReposView() } label: { Label("星标", systemImage: "star") }
                NavigationLink { GistListView(login: nil) } label: { Label("Gist", systemImage: "note.text") }
                NavigationLink { OrgListView() } label: { Label("组织", systemImage: "building.2") }
                NavigationLink { ProjectListView(scope: .me) } label: { Label("项目", systemImage: "square.grid.2x2") }
                NavigationLink { CodespaceListView() } label: { Label("代码空间", systemImage: "laptopcomputer") }
                NavigationLink { PackageListView() } label: { Label("软件包", systemImage: "shippingbox") }
                NavigationLink { AdvisoryListView() } label: { Label("安全公告", systemImage: "shield") }
            }

            Section("AI") {
                NavigationLink { AIChatView() } label: { Label("AI 助手", systemImage: "sparkles") }
                NavigationLink { AISettingsView() } label: { Label("AI 服务商", systemImage: "slider.horizontal.3") }
            }

            Section("账号") {
                NavigationLink { EditProfileView() } label: { Label("编辑资料", systemImage: "pencil") }
                NavigationLink { EmailListView() } label: { Label("邮箱", systemImage: "envelope") }
                NavigationLink { SSHKeyListView() } label: { Label("SSH 密钥", systemImage: "key") }
                NavigationLink { BlockListView() } label: { Label("已屏蔽", systemImage: "hand.raised") }
                NavigationLink { RateLimitView() } label: { Label("API 速率", systemImage: "speedometer") }
                if let u = app.user, let url = URL(string: "https://github.com/\(u.login)") {
                    Link(destination: url) { Label("在 Safari 中打开主页", systemImage: "safari") }
                }
                Link(destination: URL(string: "https://github.com/settings/security")!) {
                    Label("账号安全设置", systemImage: "lock")
                }
            }

            if !sponsors.isEmpty {
                Section("我赞助的人") {
                    ForEach(sponsors, id: \.self) { login in
                        NavigationLink { UserProfileView(login: login) } label: { Text(login) }
                    }
                }
            }

            Section {
                Button(role: .destructive) { confirm = true } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("推送通知需要 Apple 推送证书和后端，GitHub API 本身不向第三方应用投递系统通知。收件箱请下拉刷新。")
                    .font(.footnote)
            }
        }
        .navigationTitle("我的")
        .refreshable { await refresh() }
        .task { await refresh() }
        .alert("退出登录？", isPresented: $confirm) {
            Button("退出", role: .destructive) { app.logout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清除本机保存的令牌。")
        }
    }

    private func stat(_ title: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func refresh() async {
        await app.refreshUser()
        await app.refreshUnread()
        guard let login = app.user?.login else { return }
        await loadGraph(login)
    }

    private func loadGraph(_ login: String) async {
        let q = """
        query($login: String!) {
          user(login: $login) {
            pinnedItems(first: 6) {
              nodes {
                ... on Repository {
                  nameWithOwner
                  description
                  stargazerCount
                }
              }
            }
            contributionsCollection {
              contributionCalendar {
                totalContributions
                weeks { contributionDays { contributionCount date } }
              }
            }
            sponsorshipsAsSponsor(first: 20) {
              nodes { sponsorable { ... on User { login } ... on Organization { login } } }
            }
          }
        }
        """
        guard let data = try? await API.shared.gql(q, ["login": login]),
              let user = data["user"] as? [String: Any] else { return }
        if let pin = user["pinnedItems"] as? [String: Any] {
            pinned = (pin["nodes"] as? [Any] ?? []).compactMap { node -> PinnedRepo? in
                guard let o = node as? [String: Any], let name = o["nameWithOwner"] as? String else { return nil }
                return PinnedRepo(fullName: name, description: o["description"] as? String, stars: o["stargazerCount"] as? Int ?? 0)
            }
        }
        if let col = user["contributionsCollection"] as? [String: Any],
           let cal = col["contributionCalendar"] as? [String: Any] {
            contribTotal = cal["totalContributions"] as? Int
            let ws = cal["weeks"] as? [Any] ?? []
            weeks = ws.compactMap { w -> [ContribDay]? in
                guard let o = w as? [String: Any] else { return nil }
                let days = o["contributionDays"] as? [Any] ?? []
                return days.compactMap { d in
                    guard let day = d as? [String: Any] else { return nil }
                    return ContribDay(date: day["date"] as? String ?? "", count: day["contributionCount"] as? Int ?? 0)
                }
            }
        }
        if let sp = user["sponsorshipsAsSponsor"] as? [String: Any] {
            sponsors = (sp["nodes"] as? [Any] ?? []).compactMap { n in
                ((n as? [String: Any])?["sponsorable"] as? [String: Any])?["login"] as? String
            }
        }
    }
}

struct PinnedRepo: Identifiable, Hashable {
    var id: String { fullName }
    let fullName: String
    let description: String?
    let stars: Int
}

struct ContribDay: Hashable {
    let date: String
    let count: Int
}

struct ContributionGrid: View {
    let weeks: [[ContribDay]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(day.count))
                                .frame(width: 11, height: 11)
                                .accessibilityLabel("\(day.date) \(day.count) 次贡献")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(_ n: Int) -> Color {
        if n <= 0 { return Color.primary.opacity(0.08) }
        if n < 3 { return Color.green.opacity(0.35) }
        if n < 6 { return Color.green.opacity(0.6) }
        return Color.green.opacity(0.9)
    }
}

struct EditProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var company = ""
    @State private var location = ""
    @State private var blog = ""
    @State private var twitter = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("公开资料") {
                TextField("名字", text: $name)
                TextField("简介", text: $bio, axis: .vertical).lineLimit(3...6)
                TextField("公司", text: $company)
                TextField("位置", text: $location)
                TextField("网站", text: $blog)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Twitter 用户名", text: $twitter)
                    .textInputAutocapitalization(.never)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if busy { ProgressView() }; Text("保存") }
                }
                .disabled(busy)
            }
        }
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let u = app.user
            name = u?.name ?? ""
            bio = u?.bio ?? ""
            company = u?.company ?? ""
            location = u?.location ?? ""
            blog = u?.blog ?? ""
            twitter = u?.twitterUsername ?? ""
        }
    }

    private func save() async {
        busy = true
        error = nil
        do {
            let _: GHUser = try await API.shared.write("/user", method: "PATCH", body: [
                "name": name,
                "bio": bio,
                "company": company,
                "location": location,
                "blog": blog,
                "twitter_username": twitter
            ])
            await app.refreshUser()
            tapHaptic()
            dismiss()
        } catch {
            self.error = errText(error)
        }
        busy = false
    }
}
