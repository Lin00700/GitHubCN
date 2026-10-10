import SwiftUI

// MARK: - Actions（构建）

struct ActionsView: View {
    let repo: Repo
    @State private var runs: [Run] = []
    @State private var workflows: [Workflow] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var info: String?

    var body: some View {
        List {
            if let e = errorMsg {
                Text(e).font(.footnote).foregroundColor(.red)
            }
            if let i = info {
                Text(i).font(.footnote).foregroundColor(.green)
            }
            if !workflows.isEmpty {
                Menu {
                    ForEach(workflows) { w in
                        Button(w.name) { Task { await dispatch(w) } }
                    }
                } label: {
                    Label("运行工作流", systemImage: "play.circle")
                }
            }
            ForEach(runs) { r in
                NavigationLink(destination: RunDetailView(repo: repo, run: r)) {
                    RunRow(run: r)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading {
                ProgressView()
            } else if runs.isEmpty && errorMsg == nil {
                Text("还没有构建记录").foregroundColor(.secondary)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        errorMsg = nil
        do {
            let r: RunList = try await API.shared.get("/repos/\(repo.fullName)/actions/runs?per_page=30")
            runs = r.workflowRuns
        } catch {
            errorMsg = errText(error)
        }
        if let w: WorkflowList = try? await API.shared.get("/repos/\(repo.fullName)/actions/workflows") {
            workflows = w.workflows.filter { $0.state == "active" }
        }
        loading = false
    }

    private func dispatch(_ w: Workflow) async {
        errorMsg = nil
        info = nil
        do {
            try await API.shared.post(
                "/repos/\(repo.fullName)/actions/workflows/\(w.id)/dispatches",
                body: ["ref": repo.defaultBranch ?? "main"]
            )
            info = "已触发「\(w.name)」，稍后下拉刷新查看"
        } catch {
            errorMsg = errText(error)
        }
    }
}

struct RunRow: View {
    let run: Run

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.displayTitle ?? run.name ?? "运行")
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text("#\(run.runNumber ?? 0) · \(run.headBranch ?? "") · \(run.event ?? "") · \(relTime(run.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var icon: String {
        if run.status != "completed" { return "clock.arrow.circlepath" }
        switch run.conclusion ?? "" {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "cancelled": return "slash.circle"
        default: return "questionmark.circle"
        }
    }

    private var color: Color {
        if run.status != "completed" { return .orange }
        switch run.conclusion ?? "" {
        case "success": return .green
        case "failure": return .red
        default: return .gray
        }
    }
}

struct RunDetailView: View {
    let repo: Repo
    let run: Run
    @State private var artifacts: [Artifact] = []
    @State private var loading = true
    @State private var busyId: Int?
    @State private var share: ShareItem?
    @State private var errorMsg: String?
    @State private var info: String?

    var body: some View {
        List {
            Section {
                RunRow(run: run)
                Button("重新运行") { Task { await rerun() } }
                if let u = URL(string: run.htmlUrl) {
                    Link("在 Safari 查看日志", destination: u)
                }
            }
            Section(header: Text("构建产物")) {
                if loading {
                    ProgressView()
                } else if artifacts.isEmpty {
                    Text("没有构建产物").foregroundColor(.secondary)
                }
                ForEach(artifacts) { a in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name)
                            Text(sizeText(a.sizeInBytes) + (a.expired ? " · 已过期" : ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if busyId == a.id {
                            ProgressView()
                        } else {
                            Button {
                                Task { await download(a) }
                            } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(a.expired)
                        }
                    }
                }
            }
            if let i = info {
                Section { Text(i).foregroundColor(.green) }
            }
            if let e = errorMsg {
                Section { Text(e).foregroundColor(.red) }
            }
        }
        .neonBackground()
        .navigationTitle("运行 #\(run.runNumber ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let r: ArtifactList = try await API.shared.get("/repos/\(repo.fullName)/actions/runs/\(run.id)/artifacts")
            artifacts = r.artifacts
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }

    private func download(_ a: Artifact) async {
        busyId = a.id
        errorMsg = nil
        do {
            let url = try await API.shared.downloadArtifact(repo: repo.fullName, id: a.id, name: a.name)
            share = ShareItem(url: url)
        } catch {
            errorMsg = errText(error)
        }
        busyId = nil
    }

    private func rerun() async {
        errorMsg = nil
        info = nil
        do {
            try await API.shared.action("/repos/\(repo.fullName)/actions/runs/\(run.id)/rerun", method: "POST")
            info = "已重新运行，返回上一页下拉刷新查看"
        } catch {
            errorMsg = errText(error)
        }
    }
}

// MARK: - 发行版

struct ReleasesView: View {
    let repo: Repo
    @State private var releases: [Release] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var zh = false
    @State private var busy: Int?
    @State private var share: ShareItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TranslateBar(on: $zh)
                if loading { ProgressView() }
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
                if !loading && releases.isEmpty && errorMsg == nil {
                    Text("没有发行版").foregroundColor(.secondary)
                }
                ForEach(releases) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(r.title).font(.headline)
                        Text("\(r.tagName) · \(relTime(r.publishedAt))\(r.prerelease ? " · 预发布" : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let b = r.body, !b.isEmpty {
                            TranslatableMarkdown(text: b, translate: zh)
                        }
                        ForEach(r.assets) { a in
                            HStack {
                                Image(systemName: "shippingbox")
                                Text(a.name).font(.footnote).lineLimit(1)
                                Spacer()
                                Text(sizeText(a.size)).font(.caption).foregroundColor(.secondary)
                                if busy == a.id {
                                    ProgressView()
                                } else {
                                    Button {
                                        Task { await download(a) }
                                    } label: {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let r: [Release] = try await API.shared.get("/repos/\(repo.fullName)/releases?per_page=20")
            releases = r
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }

    private func download(_ a: ReleaseAsset) async {
        busy = a.id
        errorMsg = nil
        do {
            let url = try await API.shared.downloadFile(a.browserDownloadUrl, name: a.name)
            share = ShareItem(url: url)
        } catch {
            errorMsg = errText(error)
        }
        busy = nil
    }
}
