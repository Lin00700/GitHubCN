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
                .swipeActions {
                    Button("重跑") { Task { await rerun(r) } }.tint(.blue)
                    if r.status != "completed" {
                        Button("取消", role: .destructive) { Task { await cancel(r) } }
                    }
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
        .navigationTitle("行动")
        .navigationBarTitleDisplayMode(.inline)
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

    private func rerun(_ r: Run) async {
        do {
            try await API.shared.action("/repos/\(repo.fullName)/actions/runs/\(r.id)/rerun", method: "POST")
            info = "已重新运行 #\(r.runNumber ?? 0)"
        } catch { errorMsg = errText(error) }
    }

    private func cancel(_ r: Run) async {
        do {
            try await API.shared.action("/repos/\(repo.fullName)/actions/runs/\(r.id)/cancel", method: "POST")
            info = "已取消"
            await load()
        } catch { errorMsg = errText(error) }
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
    @State private var buildErrors: [BuildError] = []
    @State private var analyzing = false
    @State private var analyzed = false
    @State private var aiContext = ""

    var body: some View {
        List {
            Section {
                RunRow(run: run)
                NavigationLink("任务和日志") { RunJobsView(repo: repo, run: run) }
                Button("重新运行") { Task { await rerun() } }
                Button("只重跑失败的任务") { Task { await rerunFailed() } }
                if run.status != "completed" {
                    Button("取消", role: .destructive) { Task { await cancel() } }
                }
                Button("下载日志包") { Task { await downloadLogs() } }
                if let u = URL(string: run.htmlUrl) {
                    Link("在 Safari 中打开", destination: u)
                }
            }
            if run.conclusion == "failure" {
                Section(header: Text("构建错误")) {
                    Button {
                        Task { await analyze() }
                    } label: {
                        HStack {
                            if analyzing { ProgressView() }
                            Text(analyzed ? "重新分析报错" : "分析报错（读取构建日志）")
                        }
                    }
                    .disabled(analyzing)
                    ForEach(buildErrors) { e in
                        if let p = e.path {
                            NavigationLink(
                                destination: FileView(
                                    repo: repo,
                                    item: ContentItem(name: (p as NSString).lastPathComponent, path: p, type: "file", size: nil, sha: nil, htmlUrl: nil, downloadUrl: nil),
                                    highlightLine: e.line,
                                    ref: run.headBranch ?? repo.defaultBranch ?? "main"
                                )
                            ) {
                                BuildErrorRow(e: e)
                            }
                        } else {
                            BuildErrorRow(e: e)
                        }
                    }
                    if analyzed && buildErrors.isEmpty {
                        Text("日志里没有找到 error: 行").foregroundColor(.secondary)
                    }
                    if !buildErrors.isEmpty {
                        NavigationLink(
                            destination: AIChatView(
                                contextTitle: "构建报错",
                                contextText: aiContext,
                                quickPrompts: ["根据报错给出修复后的完整代码", "解释这些报错的原因", "最小改动怎么修？"]
                            )
                        ) {
                            Label("让 AI 分析并给出修复", systemImage: "sparkles")
                        }
                    }
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
        .navigationTitle("运行 #\(run.runNumber ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
        }
        .task { await load() }
    }

    private func analyze() async {
        analyzing = true
        errorMsg = nil
        do {
            let jl: JobList = try await API.shared.get("/repos/\(repo.fullName)/actions/runs/\(run.id)/jobs")
            let failed = jl.jobs.filter { $0.conclusion == "failure" }
            let targets = Array((failed.isEmpty ? jl.jobs : failed).prefix(2))
            var found: [BuildError] = []
            for j in targets {
                let log = try await API.shared.jobLog(repo: repo.fullName, jobId: j.id)
                found += BuildErrorParser.parse(log)
            }
            var seen = Set<String>()
            var unique: [BuildError] = []
            for e in found {
                let key = "\(e.path ?? "")|\(e.line ?? 0)|\(e.message)"
                if seen.insert(key).inserted { unique.append(e) }
            }
            buildErrors = Array(unique.prefix(30))
            analyzed = true
            aiContext = await buildAIContext(buildErrors)
        } catch {
            errorMsg = errText(error)
        }
        analyzing = false
    }

    private func buildAIContext(_ errs: [BuildError]) async -> String {
        var t = "GitHub Actions 构建失败，仓库 \(repo.fullName)。编译错误：\n"
        for e in errs.prefix(15) {
            let loc = e.line.map { ":\($0)" } ?? ""
            t += "- \(e.path ?? "")\(loc) \(e.message)\n"
        }
        var cache: [String: [String]] = [:]
        t += "\n相关代码（行号: 内容）：\n"
        for e in errs.prefix(8) {
            guard let p = e.path, let l = e.line else { continue }
            if cache[p] == nil {
                let src = (try? await API.shared.raw("/repos/\(repo.fullName)/contents/\(encPath(p))")) ?? ""
                cache[p] = src.components(separatedBy: "\n")
            }
            guard let lines = cache[p], !lines.isEmpty else { continue }
            let lo = max(l - 6, 1)
            let hi = min(l + 6, lines.count)
            if lo > hi { continue }
            t += "\n[\(p)]\n"
            for n in lo...hi { t += "\(n): \(lines[n - 1])\n" }
        }
        return String(t.prefix(12000))
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

    private func rerunFailed() async {
        errorMsg = nil
        do {
            try await API.shared.action("/repos/\(repo.fullName)/actions/runs/\(run.id)/rerun-failed-jobs", method: "POST")
            info = "已重跑失败的任务"
        } catch { errorMsg = errText(error) }
    }

    private func cancel() async {
        errorMsg = nil
        do {
            try await API.shared.action("/repos/\(repo.fullName)/actions/runs/\(run.id)/cancel", method: "POST")
            info = "已取消"
        } catch { errorMsg = errText(error) }
    }

    private func downloadLogs() async {
        errorMsg = nil
        do {
            let url = try await API.shared.downloadFollowingRedirect(
                "/repos/\(repo.fullName)/actions/runs/\(run.id)/logs",
                name: "run-\(run.id)-logs.zip"
            )
            share = ShareItem(url: url)
        } catch { errorMsg = errText(error) }
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
        .navigationTitle("发行版")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { NewReleaseView(repo: repo) { Task { await load() } } } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建发行版")
            }
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

struct RunJobsView: View {
    let repo: Repo
    let run: Run
    @State private var jobs: [Job] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(jobs) { j in
                NavigationLink { JobLogView(repo: repo, job: j) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(j.name).font(.body)
                        Text("\(j.status ?? "") \(j.conclusion ?? "")").font(.caption).foregroundStyle(.secondary)
                        if let steps = j.steps {
                            ForEach(steps) { s in
                                Text("\(s.number). \(s.name) · \(s.conclusion ?? s.status ?? "")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("任务")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let list: JobList = try await API.shared.get("/repos/\(repo.fullName)/actions/runs/\(run.id)/jobs")
                jobs = list.jobs
            } catch { self.error = errText(error) }
        }
    }
}

struct JobLogView: View {
    let repo: Repo
    let job: Job
    @State private var text = ""
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if loading { ProgressView().padding() }
            if let error { Text(error).foregroundStyle(.red).padding() }
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(job.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                text = try await API.shared.jobLog(repo: repo.fullName, jobId: job.id)
                error = nil
            } catch { self.error = errText(error) }
            loading = false
        }
    }
}

struct NewReleaseView: View {
    let repo: Repo
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tag = ""
    @State private var name = ""
    @State private var bodyText = ""
    @State private var pre = false
    @State private var draft = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("标签，例如 v1.0.0", text: $tag).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("标题", text: $name)
            TextField("说明", text: $bodyText, axis: .vertical).lineLimit(5...12)
            Toggle("预发布", isOn: $pre)
            Toggle("草稿", isOn: $draft)
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await create() } } label: {
                HStack { if busy { ProgressView() }; Text("发布") }
            }
            .disabled(busy || tag.isEmpty)
        }
        .navigationTitle("新建发行版")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() async {
        busy = true
        do {
            let _: Release = try await API.shared.write("/repos/\(repo.fullName)/releases", method: "POST", body: [
                "tag_name": tag,
                "name": name.isEmpty ? tag : name,
                "body": bodyText,
                "draft": draft,
                "prerelease": pre,
                "target_commitish": repo.branch
            ])
            onCreated()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}
