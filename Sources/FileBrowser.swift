import SwiftUI
import UniformTypeIdentifiers

enum FilesSheet: Identifiable {
    case newFile
    case upload(UploadBatch)
    case rename(ContentItem)

    var id: String {
        switch self {
        case .newFile: return "new"
        case .upload(let b): return "up-" + b.id.uuidString
        case .rename(let i): return "rn-" + i.path
        }
    }
}

// MARK: - 文件列表（可新建、上传、重命名、删除）

struct FilesView: View {
    let repo: Repo
    let path: String
    let embedded: Bool
    @State private var items: [ContentItem] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var info: String?
    @State private var progressText = ""
    @State private var busy = false
    @State private var sheet: FilesSheet?
    @State private var showFiles = false
    @State private var showFolder = false
    @State private var deleting: ContentItem?

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    actionButton("新建文件", "doc.badge.plus") { sheet = .newFile }
                    actionButton("上传文件", "square.and.arrow.up") { showFiles = true }
                    actionButton("上传文件夹", "folder.badge.plus") { showFolder = true }
                }
            }
            .listRowBackground(Color.clear)

            if busy {
                HStack {
                    ProgressView()
                    Text(progressText).font(.footnote).foregroundColor(Theme.textDim)
                }
            }
            if let e = errorMsg {
                Text(e).font(.footnote).foregroundColor(.red)
            }
            if let i = info {
                Text(i).font(.footnote).foregroundColor(.green)
            }

            ForEach(items) { it in
                NavigationLink(destination: destination(it)) {
                    Label(it.name, systemImage: it.type == "dir" ? "folder" : "doc.text")
                }
                .contextMenu {
                    Button {
                        sheet = .rename(it)
                    } label: {
                        Label("重命名 / 移动", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleting = it
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleting = it
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if loading { ProgressView() } }
        .refreshable { await load() }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleImport(result, folder: false)
        }
        .background(
            Color.clear.fileImporter(isPresented: $showFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleImport(result, folder: true)
            }
        )
        .sheet(item: $sheet) { s in
            NavigationView {
                switch s {
                case .newFile:
                    NewFileSheet(repo: repo, dir: path) { Task { await load() } }
                case .upload(let b):
                    UploadSheet(repo: repo, batch: b) { Task { await load() } }
                case .rename(let it):
                    RenameSheet(repo: repo, item: it) { Task { await load() } }
                }
            }
            .preferredColorScheme(.dark)
        }
        .alert(
            "删除「\(deleting?.name ?? "")」？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("删除", role: .destructive) {
                if let d = deleting { doDelete(d) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: {
            Text("会提交一次删除，之后仍可以在 GitHub 的历史记录里恢复。")
        }
        .neonBackground()
        .navigationTitle(embedded ? repo.name : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func destination(_ it: ContentItem) -> some View {
        if it.type == "dir" {
            FilesView(repo: repo, path: it.path, embedded: false)
        } else {
            FileView(repo: repo, item: it)
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.borderless)
    }

    private func handleImport(_ result: Result<[URL], Error>, folder: Bool) {
        switch result {
        case .failure(let e):
            errorMsg = errText(e)
        case .success(let urls):
            let base = path
            Task { @MainActor in
                do {
                    let batch = try await Task.detached {
                        try UploadBatch.read(urls: urls, folder: folder, baseDir: base)
                    }.value
                    if batch.files.isEmpty {
                        errorMsg = "没有读取到可上传的文件"
                    } else {
                        sheet = .upload(batch)
                    }
                } catch {
                    errorMsg = errText(error)
                }
            }
        }
    }

    private func doDelete(_ it: ContentItem) {
        busy = true
        errorMsg = nil
        info = nil
        progressText = "准备删除…"
        Task { @MainActor in
            do {
                var changes: [FileChange] = []
                if it.type == "dir" {
                    for b in try await GitCommitter.blobs(in: repo, under: it.path) {
                        changes.append(.delete(b.path))
                    }
                } else {
                    changes = [.delete(it.path)]
                }
                if changes.isEmpty { throw APIError.http(0, "没有找到要删除的文件") }
                try await GitCommitter.commit(repo: repo, changes: changes, message: "删除 \(it.name)") { s in
                    progressText = s
                }
                info = "已删除 \(it.name)，已提交。"
                await load()
            } catch {
                errorMsg = errText(error)
            }
            busy = false
        }
    }

    private func load() async {
        do {
            let url = path.isEmpty
                ? "/repos/\(repo.fullName)/contents"
                : "/repos/\(repo.fullName)/contents/\(encPath(path))"
            let list: [ContentItem] = try await API.shared.get(url)
            items = list.sorted { a, b in
                if (a.type == "dir") != (b.type == "dir") { return a.type == "dir" }
                return a.name.lowercased() < b.name.lowercased()
            }
            errorMsg = nil
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}

// MARK: - 新建文件

struct NewFileSheet: View {
    let repo: Repo
    var onDone: () -> Void
    @Environment(\.presentationMode) private var mode
    @State private var path: String
    @State private var content = ""
    @State private var message = "新建文件"
    @State private var busy = false
    @State private var progressText = ""
    @State private var errorMsg: String?

    init(repo: Repo, dir: String, onDone: @escaping () -> Void) {
        self.repo = repo
        self.onDone = onDone
        _path = State(initialValue: dir.isEmpty ? "" : dir + "/")
    }

    private var cleanPath: String { joinPath("", path) }
    private var valid: Bool { !cleanPath.isEmpty && !path.hasSuffix("/") }

    var body: some View {
        Form {
            Section(
                header: Text("路径"),
                footer: Text("要新建文件夹，直接写「文件夹/文件名」即可，例如 Sources/New.swift。")
            ) {
                TextField("例如 .github/workflows/build.yml", text: $path)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            Section(header: Text("内容")) {
                TextEditor(text: $content)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 240)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button {
                    if let s = UIPasteboard.general.string { content = s }
                } label: {
                    Label("粘贴剪贴板内容", systemImage: "doc.on.clipboard")
                }
            }
            Section(header: Text("提交说明")) {
                TextField("提交说明", text: $message)
            }
            Section {
                Button {
                    commit()
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(busy ? progressText : "提交到 \(repo.defaultBranch ?? "main")")
                    }
                }
                .disabled(!valid || busy)
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
            }
        }
        .neonBackground()
        .navigationTitle("新建文件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { mode.wrappedValue.dismiss() }
            }
        }
    }

    private func commit() {
        busy = true
        errorMsg = nil
        let p = cleanPath
        let data = Data(content.utf8)
        let msg = message.isEmpty ? "新建 \(p)" : message
        Task { @MainActor in
            do {
                try await GitCommitter.commit(repo: repo, changes: [.upsert(p, data)], message: msg) { s in
                    progressText = s
                }
                onDone()
                mode.wrappedValue.dismiss()
            } catch {
                errorMsg = errText(error)
            }
            busy = false
        }
    }
}

// MARK: - 上传文件 / 文件夹

struct UploadSheet: View {
    let repo: Repo
    var onDone: () -> Void
    @Environment(\.presentationMode) private var mode
    @State private var batch: UploadBatch
    @State private var message: String
    @State private var busy = false
    @State private var progressText = ""
    @State private var errorMsg: String?

    init(repo: Repo, batch: UploadBatch, onDone: @escaping () -> Void) {
        self.repo = repo
        self.onDone = onDone
        _batch = State(initialValue: batch)
        _message = State(initialValue: "上传 \(batch.files.count) 个文件")
    }

    private var totalSize: Int { batch.files.reduce(0) { $0 + $1.data.count } }

    var body: some View {
        Form {
            Section(
                header: Text("目标目录"),
                footer: Text("留空表示仓库根目录。上传整个项目文件夹时，把这里清空，文件就会直接放在仓库根目录。")
            ) {
                TextField("例如 Sources", text: $batch.prefix)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            Section(header: Text("将上传 \(batch.files.count) 个文件（\(sizeText(totalSize))）")) {
                ForEach(Array(batch.files.prefix(40))) { f in
                    Text(joinPath(batch.prefix, f.relPath))
                        .font(.system(.caption, design: .monospaced))
                }
                if batch.files.count > 40 {
                    Text("…还有 \(batch.files.count - 40) 个文件").font(.caption).foregroundColor(.secondary)
                }
                if !batch.skipped.isEmpty {
                    Text("已跳过（超过 25MB）：\(batch.skipped.joined(separator: "、"))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Section(header: Text("提交说明")) {
                TextField("提交说明", text: $message)
            }
            Section {
                Button {
                    commit()
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(busy ? progressText : "一次提交到 \(repo.defaultBranch ?? "main")")
                    }
                }
                .disabled(busy || batch.files.isEmpty)
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
            }
        }
        .neonBackground()
        .navigationTitle("上传")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { mode.wrappedValue.dismiss() }
            }
        }
    }

    private func commit() {
        busy = true
        errorMsg = nil
        let changes = batch.files.map { FileChange.upsert(joinPath(batch.prefix, $0.relPath), $0.data) }
        let msg = message.isEmpty ? "上传文件" : message
        Task { @MainActor in
            do {
                try await GitCommitter.commit(repo: repo, changes: changes, message: msg) { s in
                    progressText = s
                }
                onDone()
                mode.wrappedValue.dismiss()
            } catch {
                errorMsg = errText(error)
            }
            busy = false
        }
    }
}

// MARK: - 重命名 / 移动

struct RenameSheet: View {
    let repo: Repo
    let item: ContentItem
    var onDone: () -> Void
    @Environment(\.presentationMode) private var mode
    @State private var newPath: String
    @State private var busy = false
    @State private var progressText = ""
    @State private var errorMsg: String?

    init(repo: Repo, item: ContentItem, onDone: @escaping () -> Void) {
        self.repo = repo
        self.item = item
        self.onDone = onDone
        _newPath = State(initialValue: item.path)
    }

    private var target: String { joinPath("", newPath) }

    var body: some View {
        Form {
            Section(
                header: Text("新的完整路径"),
                footer: Text("改文件名或移动到别的文件夹，都是修改这条路径。会作为一次提交完成。")
            ) {
                TextField("路径", text: $newPath)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            Section {
                Button {
                    run()
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(busy ? progressText : "提交")
                    }
                }
                .disabled(busy || target.isEmpty || target == item.path)
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
            }
        }
        .neonBackground()
        .navigationTitle("重命名 / 移动")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { mode.wrappedValue.dismiss() }
            }
        }
    }

    private func run() {
        busy = true
        errorMsg = nil
        let newBase = target
        Task { @MainActor in
            do {
                var changes: [FileChange] = []
                if item.type == "dir" {
                    let blobs = try await GitCommitter.blobs(in: repo, under: item.path)
                    for b in blobs {
                        let rest = String(b.path.dropFirst(item.path.count + 1))
                        changes.append(.reuse(joinPath(newBase, rest), sha: b.sha))
                        changes.append(.delete(b.path))
                    }
                } else {
                    guard let sha = item.sha else {
                        throw APIError.http(0, "缺少文件标识，请下拉刷新后重试")
                    }
                    changes = [.reuse(newBase, sha: sha), .delete(item.path)]
                }
                if changes.isEmpty { throw APIError.http(0, "没有找到要移动的文件") }
                try await GitCommitter.commit(repo: repo, changes: changes, message: "移动 \(item.path) → \(newBase)") { s in
                    progressText = s
                }
                onDone()
                mode.wrappedValue.dismiss()
            } catch {
                errorMsg = errText(error)
            }
            busy = false
        }
    }
}

// MARK: - 文件查看 / 编辑

struct FileView: View {
    let repo: Repo
    let item: ContentItem
    var highlightLine: Int? = nil
    @State private var fullText: String?
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var info: String?
    @State private var zh = false
    @State private var editing = false
    @State private var draft = ""
    @State private var message = ""
    @State private var busy = false
    @State private var progressText = ""

    private var isMD: Bool {
        let n = item.name.lowercased()
        return n.hasSuffix(".md") || n.hasSuffix(".markdown")
    }

    private var canEdit: Bool {
        guard let t = fullText else { return false }
        return !t.isEmpty && t.count <= 300_000
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let i = info {
                    Text(i).font(.footnote).foregroundColor(.green)
                }
                if let e = errorMsg {
                    Text(e).font(.footnote).foregroundColor(.red)
                }
                if editing {
                    editor
                } else {
                    viewer
                }
            }
            .padding()
        }
        .neonBackground()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if canEdit && !editing {
                    Button("编辑") {
                        draft = fullText ?? ""
                        message = "更新 \(item.name)"
                        editing = true
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: 查看

    @ViewBuilder
    private var viewer: some View {
        snippet
        if isMD { TranslateBar(on: $zh) }
        if loading {
            ProgressView()
        } else if let t = fullText, !t.isEmpty {
            if isMD {
                TranslatableMarkdown(text: String(t.prefix(60_000)), translate: zh)
            } else {
                ScrollView(.horizontal) {
                    Text(String(t.prefix(60_000)))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } else {
            Text(errorMsg ?? "无法预览此文件（二进制或为空）").foregroundColor(.secondary)
        }
    }

    /// 报错位置附近的代码
    @ViewBuilder
    private var snippet: some View {
        if let hl = highlightLine, let t = fullText {
            let lines = t.components(separatedBy: "\n")
            let lo = max(hl - 5, 1)
            let hi = min(hl + 5, lines.count)
            if lo <= hi {
                VStack(alignment: .leading, spacing: 2) {
                    Text("报错位置：第 \(hl) 行")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                    ForEach(lo...hi, id: \.self) { n in
                        Text("\(n)  \(lines[n - 1])")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(n == hl ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(n == hl ? Color.red.opacity(0.15) : Color.clear)
                    }
                }
                .neonCard()
            }
        }
    }

    // MARK: 编辑

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { draft = s }
                } label: {
                    Label("用剪贴板内容替换", systemImage: "doc.on.clipboard")
                }
                Spacer()
                NavigationLink(
                    destination: AIChatView(
                        contextTitle: item.path,
                        contextText: String(draft.prefix(12000)),
                        quickPrompts: ["检查这个文件有没有错误", "帮我优化这段代码", "解释这个文件的作用"]
                    )
                ) {
                    Label("问 AI", systemImage: "sparkles")
                }
            }
            .font(.footnote.bold())

            TextEditor(text: $draft)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 360)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .background(Theme.card)
                .cornerRadius(10)

            TextField("提交说明", text: $message)
                .neonField()

            HStack(spacing: 10) {
                Button("取消") { editing = false }
                    .buttonStyle(.bordered)
                Button {
                    save()
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(busy ? progressText : "保存并提交")
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(busy)
            }
        }
    }

    private func save() {
        busy = true
        errorMsg = nil
        info = nil
        let text = draft
        let msg = message.isEmpty ? "更新 \(item.name)" : message
        Task { @MainActor in
            do {
                try await GitCommitter.commit(repo: repo, changes: [.upsert(item.path, Data(text.utf8))], message: msg) { s in
                    progressText = s
                }
                fullText = text
                editing = false
                info = "✅ 已提交。Actions 会自动开始构建，可以到「构建」页查看结果。"
            } catch {
                errorMsg = errText(error)
            }
            busy = false
        }
    }

    private func load() async {
        do {
            let t = try await API.shared.raw("/repos/\(repo.fullName)/contents/\(encPath(item.path))")
            fullText = t
        } catch {
            errorMsg = errText(error)
        }
        loading = false
    }
}
