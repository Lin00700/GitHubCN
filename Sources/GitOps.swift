import SwiftUI

// MARK: - Git Data API 的响应模型

struct GitObj: Codable { let sha: String }
struct GitRef: Codable { let object: GitObj }
struct GitCommitInfo: Codable { let sha: String; let tree: GitObj }
struct GitSha: Codable { let sha: String }
struct GitTreeEntry: Codable { let path: String; let type: String; let sha: String }
struct GitTreeList: Codable { let tree: [GitTreeEntry] }

struct Job: Codable, Identifiable {
    let id: Int
    let name: String
    let conclusion: String?
}

struct JobList: Codable { let jobs: [Job] }

// MARK: - 一次提交里的文件变更

struct FileChange {
    let path: String
    let data: Data?
    let existingSha: String?

    static func upsert(_ path: String, _ data: Data) -> FileChange {
        FileChange(path: path, data: data, existingSha: nil)
    }
    static func delete(_ path: String) -> FileChange {
        FileChange(path: path, data: nil, existingSha: nil)
    }
    /// 复用已有的文件内容（重命名/移动时用，不用重新上传）
    static func reuse(_ path: String, sha: String) -> FileChange {
        FileChange(path: path, data: nil, existingSha: sha)
    }
}

func joinPath(_ a: String, _ b: String) -> String {
    let trim = CharacterSet(charactersIn: "/ ")
    let x = a.trimmingCharacters(in: trim)
    let y = b.trimmingCharacters(in: trim)
    if x.isEmpty { return y }
    if y.isEmpty { return x }
    return x + "/" + y
}

enum GitCommitter {
    /// 把多项变更合并成「一次提交」，这样只会触发一次构建
    static func commit(repo: Repo, changes: [FileChange], message: String,
                       progress: @MainActor (String) -> Void) async throws {
        let base = "/repos/\(repo.fullName)"
        let branch = repo.defaultBranch ?? "main"
        var pending = changes
        var headOpt: GitRef?

        await progress("读取分支 \(branch)…")
        do {
            headOpt = try await API.shared.get("\(base)/git/ref/heads/\(branch)")
        } catch APIError.http(let code, _) where code == 404 || code == 409 {
            // 空仓库：先用 Contents API 创建第一个文件
            guard let first = pending.first(where: { $0.data != nil }), let d = first.data else {
                throw APIError.http(code, "仓库是空的，请先添加文件")
            }
            await progress("空仓库，创建首个文件…")
            try await API.shared.post(
                "\(base)/contents/\(encPath(first.path))",
                body: ["message": message, "content": d.base64EncodedString()],
                method: "PUT"
            )
            pending.removeAll { $0.path == first.path }
            if pending.isEmpty { return }
            headOpt = try await API.shared.get("\(base)/git/ref/heads/\(branch)")
        }
        guard let head = headOpt else {
            throw APIError.http(0, "读取分支失败，请确认仓库里已有提交")
        }

        let parent: GitCommitInfo = try await API.shared.get("\(base)/git/commits/\(head.object.sha)")

        var entries: [[String: Any]] = []
        var i = 0
        for c in pending {
            i += 1
            if let d = c.data {
                await progress("上传 \(i)/\(pending.count)：\(c.path)")
                let b: GitSha = try await API.shared.write(
                    "\(base)/git/blobs",
                    method: "POST",
                    body: ["content": d.base64EncodedString(), "encoding": "base64"]
                )
                entries.append(["path": c.path, "mode": "100644", "type": "blob", "sha": b.sha])
            } else if let s = c.existingSha {
                entries.append(["path": c.path, "mode": "100644", "type": "blob", "sha": s])
            } else {
                entries.append(["path": c.path, "mode": "100644", "type": "blob", "sha": NSNull()])
            }
        }

        await progress("生成提交…")
        let tree: GitSha = try await API.shared.write(
            "\(base)/git/trees",
            method: "POST",
            body: ["base_tree": parent.tree.sha, "tree": entries]
        )
        let commit: GitSha = try await API.shared.write(
            "\(base)/git/commits",
            method: "POST",
            body: ["message": message, "tree": tree.sha, "parents": [head.object.sha]]
        )
        try await API.shared.post(
            "\(base)/git/refs/heads/\(branch)",
            body: ["sha": commit.sha],
            method: "PATCH"
        )
        await progress("完成")
    }

    /// 某个文件夹下的所有文件（递归）
    static func blobs(in repo: Repo, under folder: String) async throws -> [GitTreeEntry] {
        let branch = repo.defaultBranch ?? "main"
        let list: GitTreeList = try await API.shared.get("/repos/\(repo.fullName)/git/trees/\(branch)?recursive=1")
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return list.tree.filter { $0.type == "blob" && $0.path.hasPrefix(prefix) }
    }
}

// MARK: - 从「文件」App 读取要上传的内容

struct UploadFile: Identifiable {
    let id = UUID()
    let relPath: String
    let data: Data
}

struct UploadBatch: Identifiable {
    let id = UUID()
    var files: [UploadFile]
    var skipped: [String]
    var prefix: String

    static func read(urls: [URL], folder: Bool, baseDir: String) throws -> UploadBatch {
        var files: [UploadFile] = []
        var skipped: [String] = []
        var prefix = baseDir
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if folder {
                prefix = joinPath(baseDir, url.lastPathComponent)
                try walk(url, "", &files, &skipped)
            } else {
                let d = try Data(contentsOf: url)
                if d.count > 25_000_000 {
                    skipped.append(url.lastPathComponent)
                } else {
                    files.append(UploadFile(relPath: url.lastPathComponent, data: d))
                }
            }
        }
        return UploadBatch(files: files, skipped: skipped, prefix: prefix)
    }

    private static func walk(_ dir: URL, _ rel: String, _ out: inout [UploadFile], _ skipped: inout [String]) throws {
        let fm = FileManager.default
        let kids = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        for k in kids {
            let name = k.lastPathComponent
            if name == ".DS_Store" || name == ".git" { continue }
            let isDir = (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let childRel = rel.isEmpty ? name : rel + "/" + name
            if isDir {
                try walk(k, childRel, &out, &skipped)
            } else {
                let d = try Data(contentsOf: k)
                if d.count > 25_000_000 {
                    skipped.append(childRel)
                } else {
                    out.append(UploadFile(relPath: childRel, data: d))
                }
            }
        }
    }
}

// MARK: - 从构建日志里提取编译错误

struct BuildError: Identifiable {
    let id = UUID()
    let path: String?
    let line: Int?
    let message: String
}

enum BuildErrorParser {
    static func parse(_ log: String) -> [BuildError] {
        var out: [BuildError] = []
        let pattern = #"/Users/runner/work/[^/\s]+/[^/\s]+/([^\s:]+):(\d+):\d+: error: (.+)$"#
        let re = try? NSRegularExpression(pattern: pattern)
        for raw in log.components(separatedBy: "\n") {
            if !raw.contains("error") { continue }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = line as NSString
            if let re = re,
               let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges == 4 {
                out.append(BuildError(
                    path: ns.substring(with: m.range(at: 1)),
                    line: Int(ns.substring(with: m.range(at: 2))),
                    message: ns.substring(with: m.range(at: 3))
                ))
            } else if !line.contains("warning:") && line.contains("error: ") {
                let cleaned = line.replacingOccurrences(
                    of: #"^\d{4}-\d{2}-\d{2}T[\d:.]+Z\s*"#,
                    with: "",
                    options: .regularExpression
                )
                out.append(BuildError(path: nil, line: nil, message: String(cleaned.prefix(240))))
            }
            if out.count >= 80 { break }
        }
        return out
    }
}

struct BuildErrorRow: View {
    let e: BuildError

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let p = e.path {
                let loc = e.line.map { ":\($0)" } ?? ""
                Text("\(p)\(loc)")
                    .font(.caption.bold())
                    .foregroundColor(Theme.cyan)
            }
            Text(e.message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(4)
        }
    }
}
