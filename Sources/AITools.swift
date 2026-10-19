import Foundation

// MARK: - 工具调用数据结构

struct AIToolCall: Identifiable {
    let id: String
    let name: String
    let argumentsJSON: String
    var args: [String: Any] {
        guard let d = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return obj
    }
}

struct AIToolResult {
    let toolCallId: String
    let name: String
    let content: String
    let isError: Bool
}

enum AIToolKind {
    case read
    case write
}

// MARK: - 工具定义与执行

enum AITools {

    /// 写操作需要用户确认
    static func kind(of name: String) -> AIToolKind {
        switch name {
        case "create_issue", "comment_issue", "update_issue",
             "commit_files", "delete_path",
             "trigger_workflow", "rerun_workflow",
             "star_repo", "unstar_repo",
             "create_repo":
            return .write
        default:
            return .read
        }
    }

    static func humanSummary(_ call: AIToolCall) -> String {
        let a = call.args
        func s(_ k: String) -> String { (a[k] as? String) ?? "" }
        func i(_ k: String) -> Int? {
            if let n = a[k] as? Int { return n }
            if let n = a[k] as? Double { return Int(n) }
            if let n = a[k] as? String { return Int(n) }
            return nil
        }
        switch call.name {
        case "list_my_repos":
            return "列出我的仓库"
        case "get_repo":
            return "查看仓库 \(s("repo"))"
        case "list_issues":
            return "列出 \(s("repo")) 的议题/PR（\(s("state").isEmpty ? "open" : s("state"))）"
        case "get_issue":
            return "查看 \(s("repo"))#\(i("number") ?? 0)"
        case "create_issue":
            return "在 \(s("repo")) 创建议题：\(s("title"))"
        case "comment_issue":
            return "评论 \(s("repo"))#\(i("number") ?? 0)"
        case "update_issue":
            let st = s("state")
            if st == "closed" { return "关闭 \(s("repo"))#\(i("number") ?? 0)" }
            if st == "open" { return "重新打开 \(s("repo"))#\(i("number") ?? 0)" }
            return "更新 \(s("repo"))#\(i("number") ?? 0)"
        case "list_files":
            let p = s("path")
            return "列出 \(s("repo")) 文件\(p.isEmpty ? "" : "：\(p)")"
        case "get_file":
            return "读取 \(s("repo"))/\(s("path"))"
        case "commit_files":
            return "提交文件到 \(s("repo"))：\(s("message"))"
        case "delete_path":
            return "删除 \(s("repo"))/\(s("path"))"
        case "list_workflows":
            return "列出 \(s("repo")) 的工作流"
        case "trigger_workflow":
            return "触发工作流 \(s("workflow")) @ \(s("repo"))"
        case "list_runs":
            return "列出 \(s("repo")) 的构建记录"
        case "rerun_workflow":
            return "重新运行构建 #\(i("run_id") ?? 0) @ \(s("repo"))"
        case "get_run_log_errors":
            return "分析构建失败日志 \(s("repo")) run=\(i("run_id") ?? 0)"
        case "search_issues":
            return "搜索议题：\(s("query"))"
        case "star_repo":
            return "给 \(s("repo")) 加星标"
        case "unstar_repo":
            return "取消 \(s("repo")) 星标"
        case "create_repo":
            return "创建仓库 \(s("name"))"
        default:
            return call.name
        }
    }

    /// OpenAI tools / Anthropic tools JSON
    static func openAIToolsJSON() -> [[String: Any]] {
        definitions.map { def in
            [
                "type": "function",
                "function": [
                    "name": def.name,
                    "description": def.description,
                    "parameters": def.parameters
                ] as [String: Any]
            ]
        }
    }

    static func anthropicToolsJSON() -> [[String: Any]] {
        definitions.map { def in
            [
                "name": def.name,
                "description": def.description,
                "input_schema": def.parameters
            ]
        }
    }

    private struct Def {
        let name: String
        let description: String
        let parameters: [String: Any]
    }

    private static let definitions: [Def] = [
        Def(name: "list_my_repos", description: "列出当前登录用户的仓库（最多 50 个）",
            parameters: ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]),
        Def(name: "get_repo", description: "获取仓库基本信息",
            parameters: [
                "type": "object",
                "properties": ["repo": ["type": "string", "description": "owner/name"]] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "list_issues", description: "列出仓库的议题或 PR",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string", "description": "owner/name"],
                    "state": ["type": "string", "description": "open 或 closed，默认 open"],
                    "pulls": ["type": "boolean", "description": "true 表示只要 PR，false 只要议题，默认 false"]
                ] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "get_issue", description: "获取议题或 PR 详情与最近评论",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "number": ["type": "integer"]
                ] as [String: Any],
                "required": ["repo", "number"]
            ]),
        Def(name: "create_issue", description: "在仓库创建新议题",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "title": ["type": "string"],
                    "body": ["type": "string"]
                ] as [String: Any],
                "required": ["repo", "title"]
            ]),
        Def(name: "comment_issue", description: "给议题或 PR 添加评论",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "number": ["type": "integer"],
                    "body": ["type": "string"]
                ] as [String: Any],
                "required": ["repo", "number", "body"]
            ]),
        Def(name: "update_issue", description: "更新议题状态或标题（state: open/closed）",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "number": ["type": "integer"],
                    "state": ["type": "string", "description": "open 或 closed，可选"],
                    "title": ["type": "string", "description": "新标题，可选"]
                ] as [String: Any],
                "required": ["repo", "number"]
            ]),
        Def(name: "list_files", description: "列出仓库某目录下的文件与文件夹",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "path": ["type": "string", "description": "目录路径，空表示根目录"]
                ] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "get_file", description: "读取仓库中某个文本文件内容（过大时截断）",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "path": ["type": "string"]
                ] as [String: Any],
                "required": ["repo", "path"]
            ]),
        Def(name: "commit_files", description: "向默认分支提交一个或多个文件的创建/更新。files 为数组，每项含 path 与 content",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "message": ["type": "string", "description": "提交说明"],
                    "files": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "path": ["type": "string"],
                                "content": ["type": "string"]
                            ] as [String: Any],
                            "required": ["path", "content"]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["repo", "message", "files"]
            ]),
        Def(name: "delete_path", description: "删除仓库中的文件或整个文件夹（会生成一次提交）",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "path": ["type": "string"],
                    "message": ["type": "string"]
                ] as [String: Any],
                "required": ["repo", "path"]
            ]),
        Def(name: "list_workflows", description: "列出仓库的 GitHub Actions 工作流",
            parameters: [
                "type": "object",
                "properties": ["repo": ["type": "string"]] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "trigger_workflow", description: "触发指定工作流（workflow 可为工作流文件名如 build.yml 或数字 id）",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "workflow": ["type": "string"],
                    "ref": ["type": "string", "description": "分支名，默认仓库默认分支"]
                ] as [String: Any],
                "required": ["repo", "workflow"]
            ]),
        Def(name: "list_runs", description: "列出最近的 Actions 运行记录",
            parameters: [
                "type": "object",
                "properties": ["repo": ["type": "string"]] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "rerun_workflow", description: "重新运行某次 workflow run",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "run_id": ["type": "integer"]
                ] as [String: Any],
                "required": ["repo", "run_id"]
            ]),
        Def(name: "get_run_log_errors", description: "读取失败构建的日志并提取 error 行",
            parameters: [
                "type": "object",
                "properties": [
                    "repo": ["type": "string"],
                    "run_id": ["type": "integer"]
                ] as [String: Any],
                "required": ["repo", "run_id"]
            ]),
        Def(name: "search_issues", description: "用 GitHub 搜索语法搜索议题/PR，例如 involves:me is:open",
            parameters: [
                "type": "object",
                "properties": ["query": ["type": "string"]] as [String: Any],
                "required": ["query"]
            ]),
        Def(name: "star_repo", description: "给仓库加星标",
            parameters: [
                "type": "object",
                "properties": ["repo": ["type": "string"]] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "unstar_repo", description: "取消仓库星标",
            parameters: [
                "type": "object",
                "properties": ["repo": ["type": "string"]] as [String: Any],
                "required": ["repo"]
            ]),
        Def(name: "create_repo", description: "为当前用户创建新仓库",
            parameters: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "description": ["type": "string"],
                    "private": ["type": "boolean"],
                    "auto_init": ["type": "boolean", "description": "是否添加 README，默认 true"]
                ] as [String: Any],
                "required": ["name"]
            ])
    ]

    // MARK: - 执行

    static func execute(_ call: AIToolCall) async -> AIToolResult {
        do {
            let text = try await run(call.name, call.args)
            return AIToolResult(toolCallId: call.id, name: call.name, content: text, isError: false)
        } catch {
            let msg = errText(error) ?? error.localizedDescription
            return AIToolResult(toolCallId: call.id, name: call.name, content: "错误：\(msg)", isError: true)
        }
    }

    private static func str(_ a: [String: Any], _ k: String) -> String {
        (a[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func int(_ a: [String: Any], _ k: String) -> Int? {
        if let n = a[k] as? Int { return n }
        if let n = a[k] as? Double { return Int(n) }
        if let n = a[k] as? String { return Int(n) }
        return nil
    }

    private static func bool(_ a: [String: Any], _ k: String, default d: Bool = false) -> Bool {
        if let b = a[k] as? Bool { return b }
        if let s = a[k] as? String { return s == "true" || s == "1" }
        return d
    }

    private static func run(_ name: String, _ a: [String: Any]) async throws -> String {
        switch name {
        case "list_my_repos":
            let list: [Repo] = try await API.shared.get("/user/repos?per_page=50&sort=updated")
            if list.isEmpty { return "没有仓库" }
            return list.map {
                "\($0.fullName)\($0.isPrivate ? " [私有]" : "") · ★\($0.stargazersCount) · \($0.language ?? "-") · \($0.description ?? "")"
            }.joined(separator: "\n")

        case "get_repo":
            let repo = str(a, "repo")
            let r: Repo = try await API.shared.get("/repos/\(repo)")
            return """
            名称：\(r.fullName)
            描述：\(r.description ?? "无")
            默认分支：\(r.defaultBranch ?? "main")
            语言：\(r.language ?? "-")
            Star：\(r.stargazersCount)  Fork：\(r.forksCount)  议题：\(r.openIssuesCount)
            私有：\(r.isPrivate)
            URL：\(r.htmlUrl)
            """.trimmingCharacters(in: .whitespacesAndNewlines)

        case "list_issues":
            let repo = str(a, "repo")
            let state = str(a, "state").isEmpty ? "open" : str(a, "state")
            let pulls = bool(a, "pulls")
            let all: [Issue] = try await API.shared.get("/repos/\(repo)/issues?state=\(state)&per_page=40")
            let items = all.filter { $0.isPR == pulls }
            if items.isEmpty { return pulls ? "没有 PR" : "没有议题" }
            return items.map {
                "#\($0.number) [\($0.state)] \($0.title) · \($0.user.login) · 评论\($0.comments ?? 0)"
            }.joined(separator: "\n")

        case "get_issue":
            let repo = str(a, "repo")
            guard let number = int(a, "number") else { return "缺少 number" }
            let issue: Issue = try await API.shared.get("/repos/\(repo)/issues/\(number)")
            let comments: [Comment] = (try? await API.shared.get("/repos/\(repo)/issues/\(number)/comments?per_page=20")) ?? []
            var t = "#\(issue.number) \(issue.title)\n状态：\(issue.state)\n作者：\(issue.user.login)\n\n\(issue.body ?? "")\n"
            for c in comments.suffix(10) {
                t += "\n--- \(c.user.login) ---\n\(c.body ?? "")\n"
            }
            return String(t.prefix(12000))

        case "create_issue":
            let repo = str(a, "repo")
            let title = str(a, "title")
            let body = str(a, "body")
            guard !title.isEmpty else { return "标题不能为空" }
            try await API.shared.post("/repos/\(repo)/issues", body: ["title": title, "body": body])
            return "已创建议题：\(title)"

        case "comment_issue":
            let repo = str(a, "repo")
            guard let number = int(a, "number") else { return "缺少 number" }
            let body = str(a, "body")
            guard !body.isEmpty else { return "评论内容不能为空" }
            try await API.shared.post("/repos/\(repo)/issues/\(number)/comments", body: ["body": body])
            return "已添加评论到 #\(number)"

        case "update_issue":
            let repo = str(a, "repo")
            guard let number = int(a, "number") else { return "缺少 number" }
            var body: [String: Any] = [:]
            let state = str(a, "state")
            if state == "open" || state == "closed" { body["state"] = state }
            let title = str(a, "title")
            if !title.isEmpty { body["title"] = title }
            guard !body.isEmpty else { return "没有要更新的字段" }
            try await API.shared.post("/repos/\(repo)/issues/\(number)", body: body, method: "PATCH")
            return "已更新 #\(number)：\(body)"

        case "list_files":
            let repo = str(a, "repo")
            let path = str(a, "path")
            let url = path.isEmpty
                ? "/repos/\(repo)/contents"
                : "/repos/\(repo)/contents/\(encPath(path))"
            let list: [ContentItem] = try await API.shared.get(url)
            if list.isEmpty { return "目录为空" }
            return list.sorted { a, b in
                if (a.type == "dir") != (b.type == "dir") { return a.type == "dir" }
                return a.name.lowercased() < b.name.lowercased()
            }.map { "\($0.type == "dir" ? "📁" : "📄") \($0.path)" }.joined(separator: "\n")

        case "get_file":
            let repo = str(a, "repo")
            let path = str(a, "path")
            let text = try await API.shared.raw("/repos/\(repo)/contents/\(encPath(path))")
            if text.isEmpty { return "（空文件或无法读取）" }
            return String(text.prefix(14000))

        case "commit_files":
            let repoName = str(a, "repo")
            let message = str(a, "message").isEmpty ? "AI 提交" : str(a, "message")
            guard let files = a["files"] as? [[String: Any]], !files.isEmpty else {
                return "files 不能为空"
            }
            let repo: Repo = try await API.shared.get("/repos/\(repoName)")
            var changes: [FileChange] = []
            for f in files {
                let p = (f["path"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                let c = f["content"] as? String ?? ""
                guard !p.isEmpty else { continue }
                changes.append(.upsert(p, Data(c.utf8)))
            }
            guard !changes.isEmpty else { return "没有有效文件" }
            try await GitCommitter.commit(repo: repo, changes: changes, message: message) { _ in }
            return "已提交 \(changes.count) 个文件到 \(repo.defaultBranch ?? "main")：\(message)"

        case "delete_path":
            let repoName = str(a, "repo")
            let path = str(a, "path").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            let message = str(a, "message").isEmpty ? "删除 \(path)" : str(a, "message")
            guard !path.isEmpty else { return "path 不能为空" }
            let repo: Repo = try await API.shared.get("/repos/\(repoName)")
            // 判断是文件还是目录：先尝试树
            let branch = repo.defaultBranch ?? "main"
            let list: GitTreeList = try await API.shared.get("/repos/\(repo.fullName)/git/trees/\(branch)?recursive=1")
            let prefix = path + "/"
            let under = list.tree.filter { $0.type == "blob" && ($0.path == path || $0.path.hasPrefix(prefix)) }
            var changes: [FileChange]
            if under.isEmpty {
                changes = [.delete(path)]
            } else {
                changes = under.map { .delete($0.path) }
            }
            try await GitCommitter.commit(repo: repo, changes: changes, message: message) { _ in }
            return "已删除 \(path)（共 \(changes.count) 个文件），并提交"

        case "list_workflows":
            let repo = str(a, "repo")
            let w: WorkflowList = try await API.shared.get("/repos/\(repo)/actions/workflows")
            let active = w.workflows.filter { $0.state == "active" }
            if active.isEmpty { return "没有可用工作流" }
            return active.map { "id=\($0.id) · \($0.name)" }.joined(separator: "\n")

        case "trigger_workflow":
            let repo = str(a, "repo")
            let workflow = str(a, "workflow")
            var ref = str(a, "ref")
            if ref.isEmpty {
                let r: Repo = try await API.shared.get("/repos/\(repo)")
                ref = r.defaultBranch ?? "main"
            }
            try await API.shared.post(
                "/repos/\(repo)/actions/workflows/\(encPath(workflow))/dispatches",
                body: ["ref": ref]
            )
            return "已触发工作流 \(workflow)（分支 \(ref)）"

        case "list_runs":
            let repo = str(a, "repo")
            let r: RunList = try await API.shared.get("/repos/\(repo)/actions/runs?per_page=15")
            if r.workflowRuns.isEmpty { return "没有构建记录" }
            return r.workflowRuns.map {
                let conc = $0.conclusion ?? $0.status ?? "?"
                return "#\($0.runNumber ?? 0) id=\($0.id) [\(conc)] \($0.displayTitle ?? $0.name ?? "") · \($0.headBranch ?? "")"
            }.joined(separator: "\n")

        case "rerun_workflow":
            let repo = str(a, "repo")
            guard let runId = int(a, "run_id") else { return "缺少 run_id" }
            try await API.shared.action("/repos/\(repo)/actions/runs/\(runId)/rerun", method: "POST")
            return "已重新运行 run \(runId)"

        case "get_run_log_errors":
            let repo = str(a, "repo")
            guard let runId = int(a, "run_id") else { return "缺少 run_id" }
            let jl: JobList = try await API.shared.get("/repos/\(repo)/actions/runs/\(runId)/jobs")
            let failed = jl.jobs.filter { $0.conclusion == "failure" }
            let targets = Array((failed.isEmpty ? jl.jobs : failed).prefix(2))
            var found: [BuildError] = []
            for j in targets {
                let log = try await API.shared.jobLog(repo: repo, jobId: j.id)
                found += BuildErrorParser.parse(log)
            }
            if found.isEmpty { return "未从日志中解析到 error 行" }
            return found.prefix(30).map { e in
                let loc = e.line.map { ":\($0)" } ?? ""
                return "\(e.path ?? "")\(loc) \(e.message)"
            }.joined(separator: "\n")

        case "search_issues":
            let q = str(a, "query")
            let r: IssueSearch = try await API.shared.get("/search/issues?q=\(enc(q))&sort=updated&per_page=30")
            if r.items.isEmpty { return "无结果" }
            return r.items.map {
                "\($0.repoFullName ?? "")#\($0.number) [\($0.state)] \($0.title)"
            }.joined(separator: "\n")

        case "star_repo":
            let repo = str(a, "repo")
            try await API.shared.action("/user/starred/\(repo)", method: "PUT")
            return "已给 \(repo) 加星标"

        case "unstar_repo":
            let repo = str(a, "repo")
            try await API.shared.action("/user/starred/\(repo)", method: "DELETE")
            return "已取消 \(repo) 星标"

        case "create_repo":
            let name = str(a, "name")
            guard !name.isEmpty else { return "名称不能为空" }
            let desc = str(a, "description")
            let isPrivate = bool(a, "private")
            let autoInit = bool(a, "auto_init", default: true)
            try await API.shared.post("/user/repos", body: [
                "name": name,
                "description": desc,
                "private": isPrivate,
                "auto_init": autoInit
            ])
            return "已创建仓库 \(name)"

        default:
            return "未知工具：\(name)"
        }
    }
}
