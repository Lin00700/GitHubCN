import SwiftUI

// MARK: - 工作台

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var repos: [Repo] = []
    @State private var unread = 0
    @State private var errorMsg: String?

    private var stars: Int { repos.reduce(0) { $0 + $1.stargazersCount } }
    private var openIssues: Int { repos.reduce(0) { $0 + $1.openIssuesCount } }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 6 { return "夜深了" }
        if h < 12 { return "早上好" }
        if h < 18 { return "下午好" }
        return "晚上好"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    HStack(spacing: 10) {
                        statCell("仓库", repos.count, "books.vertical", Theme.cyan)
                        statCell("星标", stars, "star", Theme.purple)
                        statCell("议题", openIssues, "exclamationmark.circle", Theme.pink)
                        statCell("通知", unread, "bell", Theme.cyan)
                    }

                    sectionTitle("快捷入口")
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        NavigationLink(destination: NotificationsContent()) {
                            NeonTile(icon: "bell", title: "通知",
                                     subtitle: unread > 0 ? "\(unread) 条未读" : "全部已读", tint: Theme.cyan)
                        }
                        NavigationLink(destination: SearchContent()) {
                            NeonTile(icon: "magnifyingglass", title: "搜索", subtitle: "查找仓库", tint: Theme.purple)
                        }
                        NavigationLink(destination: NewRepoView(onCreated: { Task { await load() } })) {
                            NeonTile(icon: "plus.rectangle.on.folder", title: "新建仓库", subtitle: "一键创建", tint: Theme.pink)
                        }
                        NavigationLink(destination: StarredView()) {
                            NeonTile(icon: "star", title: "我的星标", subtitle: "收藏的项目", tint: Theme.cyan)
                        }
                        NavigationLink(destination: AIChatView()) {
                            NeonTile(icon: "sparkles", title: "AI 助手",
                                     subtitle: AIStore.shared.current?.name ?? "未配置", tint: Theme.purple)
                        }
                        NavigationLink(destination: AISettingsView()) {
                            NeonTile(icon: "slider.horizontal.3", title: "AI 设置", subtitle: "服务商 / 模型 / Key", tint: Theme.pink)
                        }
                    }
                    .buttonStyle(.plain)

                    sectionTitle("最近更新")
                    if let e = errorMsg {
                        Text(e).font(.footnote).foregroundColor(.red)
                    }
                    ForEach(Array(repos.prefix(6))) { r in
                        NavigationLink(destination: RepoDetailView(repo: r)) {
                            RepoCard(repo: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .neonBackground()
            .navigationTitle("工作台")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: app.user?.avatarUrl ?? "")) { img in
                img.resizable()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.gradient, lineWidth: 2))
            .shadow(color: Theme.cyan.opacity(0.5), radius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
                Text(app.user?.name ?? app.user?.login ?? "GitHub")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.gradient)
                if let l = app.user?.login {
                    Text("@\(l)").font(.caption).foregroundColor(Theme.textDim)
                }
            }
            Spacer()
        }
        .neonCard()
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.footnote.bold())
            .foregroundColor(Theme.cyan)
            .padding(.top, 4)
    }

    private func statCell(_ title: String, _ n: Int, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(tint)
            Text("\(n)").font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundColor(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.5), lineWidth: 1))
    }

    private func load() async {
        errorMsg = nil
        do {
            let r: [Repo] = try await API.shared.get("/user/repos?sort=updated&per_page=100")
            repos = r
        } catch {
            errorMsg = errText(error)
        }
        if let n: [Note] = try? await API.shared.get("/notifications?per_page=50") {
            unread = n.count
        }
    }
}

struct NeonTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(tint)
                .shadow(color: tint.opacity(0.8), radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .neonCard()
    }
}

struct RepoCard: View {
    let repo: Repo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: repo.isPrivate ? "lock.fill" : "shippingbox.fill")
                    .foregroundStyle(Theme.gradient)
                Text(repo.name).font(.headline).lineLimit(1)
                Spacer()
                Text(relTime(repo.updatedAt))
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
            }
            if let d = repo.description, !d.isEmpty {
                Text(d)
                    .font(.subheadline)
                    .foregroundColor(Theme.textDim)
                    .lineLimit(2)
            }
            HStack(spacing: 14) {
                if let l = repo.language {
                    Label(l, systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Label("\(repo.stargazersCount)", systemImage: "star")
                Label("\(repo.forksCount)", systemImage: "arrow.triangle.branch")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(Theme.cyan.opacity(0.9))
        }
        .neonCard()
    }
}

// MARK: - 仓库列表（卡片）

struct ReposView: View {
    @State private var repos: [Repo] = []
    @State private var query = ""
    @State private var loading = false
    @State private var errorMsg: String?

    private var filtered: [Repo] {
        if query.isEmpty { return repos }
        return repos.filter {
            $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let e = errorMsg {
                        Text(e).font(.footnote).foregroundColor(.red)
                    }
                    ForEach(filtered) { r in
                        NavigationLink(destination: RepoDetailView(repo: r)) {
                            RepoCard(repo: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay { if loading && repos.isEmpty { ProgressView() } }
            .neonBackground()
            .searchable(text: $query, prompt: "筛选仓库")
            .navigationTitle("仓库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: NewRepoView(onCreated: { Task { await load() } })) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await load() }
            .task { if repos.isEmpty { await load() } }
        }
        .navigationViewStyle(.stack)
    }

    private func load() async {
        loading = true
        errorMsg = nil
        do {
            var all: [Repo] = []
            var page = 1
            while page <= 5 {
                let part: [Repo] = try await API.shared.get("/user/repos?sort=updated&per_page=100&page=\(page)")
                all += part
                if part.count < 100 { break }
                page += 1
            }
            repos = all
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}
