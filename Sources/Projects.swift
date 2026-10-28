import SwiftUI

enum ProjectScope {
    case me
    case org(String)
    case repo(String)
}

struct ProjectItem: Identifiable, Hashable {
    let id: String
    let title: String
    let number: Int
    let url: String?
    let closed: Bool
    let summary: String?
}

struct ProjectDetail: Identifiable {
    let id: String
    let title: String
    var fields: [ProjectField]
    var items: [BoardItem]
}

struct ProjectField: Identifiable, Hashable {
    let id: String
    let name: String
    let options: [ProjectOption]
}

struct ProjectOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct BoardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let number: Int?
    let status: String?
    let fieldId: String?
    let optionId: String?
}

struct ProjectListView: View {
    let scope: ProjectScope
    @EnvironmentObject var app: AppState
    @State private var items: [ProjectItem] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && items.isEmpty { ProgressView() }
            if !loading && items.isEmpty && error == nil {
                EmptyHint(title: "没有项目", systemImage: "square.grid.2x2", message: "这里显示 Projects v2。经典项目已停止使用。")
            }
            ForEach(items) { p in
                NavigationLink { ProjectBoardView(id: p.id, title: p.title) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.title).font(.headline)
                        if let s = p.summary, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        Text(p.closed ? "已关闭" : "进行中").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("项目")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = items.isEmpty
        let q: String
        let vars: [String: Any]
        switch scope {
        case .me:
            guard let login = app.user?.login else { loading = false; return }
            q = """
            query($login: String!) { user(login: $login) { projectsV2(first: 20) { nodes { id title number url shortDescription closed } } } }
            """
            vars = ["login": login]
        case .org(let login):
            q = """
            query($login: String!) { organization(login: $login) { projectsV2(first: 20) { nodes { id title number url shortDescription closed } } } }
            """
            vars = ["login": login]
        case .repo(let full):
            let parts = splitRepo(full)
            q = """
            query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { projectsV2(first: 20) { nodes { id title number url shortDescription closed } } } }
            """
            vars = ["owner": parts.owner, "name": parts.name]
        }
        do {
            let data = try await API.shared.gql(q, vars)
            let root = (data["user"] ?? data["organization"] ?? data["repository"]) as? [String: Any]
            let nodes = ((root?["projectsV2"] as? [String: Any])?["nodes"] as? [Any]) ?? []
            items = nodes.compactMap { n in
                guard let o = n as? [String: Any], let id = o["id"] as? String, let title = o["title"] as? String else { return nil }
                return ProjectItem(
                    id: id,
                    title: title,
                    number: o["number"] as? Int ?? 0,
                    url: o["url"] as? String,
                    closed: o["closed"] as? Bool ?? false,
                    summary: o["shortDescription"] as? String
                )
            }
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}

struct ProjectBoardView: View {
    let id: String
    let title: String
    @State private var fields: [ProjectField] = []
    @State private var items: [BoardItem] = []
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if let info { Text(info).font(.footnote).foregroundStyle(.secondary) }
            Text("可以修改单选状态。迭代、人员、日期等字段请在网页看板里编辑。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.body)
                    if let n = item.number { Text("#\(n)").font(.caption).foregroundStyle(.secondary) }
                    if let status = item.status { Text(status).font(.caption) }
                    if let field = fields.first(where: { $0.id == item.fieldId }) ?? fields.first {
                        Menu("更改状态") {
                            ForEach(field.options) { opt in
                                Button(opt.name) { Task { await setStatus(item: item, field: field, option: opt) } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        let q = """
        query($id: ID!) {
          node(id: $id) {
            ... on ProjectV2 {
              fields(first: 20) {
                nodes {
                  ... on ProjectV2SingleSelectField { id name options { id name } }
                }
              }
              items(first: 50) {
                nodes {
                  id
                  content {
                    ... on Issue { title number }
                    ... on PullRequest { title number }
                    ... on DraftIssue { title }
                  }
                  fieldValues(first: 12) {
                    nodes {
                      ... on ProjectV2ItemFieldSingleSelectValue {
                        name
                        optionId
                        field { ... on ProjectV2SingleSelectField { id name } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """
        do {
            let data = try await API.shared.gql(q, ["id": id])
            let node = data["node"] as? [String: Any] ?? [:]
            let fieldNodes = ((node["fields"] as? [String: Any])?["nodes"] as? [Any]) ?? []
            fields = fieldNodes.compactMap { n in
                guard let o = n as? [String: Any], let fid = o["id"] as? String, let name = o["name"] as? String else { return nil }
                let opts = (o["options"] as? [Any] ?? []).compactMap { opt -> ProjectOption? in
                    guard let oo = opt as? [String: Any], let oid = oo["id"] as? String else { return nil }
                    return ProjectOption(id: oid, name: oo["name"] as? String ?? oid)
                }
                return ProjectField(id: fid, name: name, options: opts)
            }
            let itemNodes = ((node["items"] as? [String: Any])?["nodes"] as? [Any]) ?? []
            items = itemNodes.compactMap { n in
                guard let o = n as? [String: Any], let iid = o["id"] as? String else { return nil }
                let content = o["content"] as? [String: Any]
                let values = ((o["fieldValues"] as? [String: Any])?["nodes"] as? [Any]) ?? []
                var status: String?
                var fieldId: String?
                var optionId: String?
                for v in values {
                    guard let vo = v as? [String: Any], let name = vo["name"] as? String else { continue }
                    status = name
                    optionId = vo["optionId"] as? String
                    fieldId = (vo["field"] as? [String: Any])?["id"] as? String
                    break
                }
                return BoardItem(
                    id: iid,
                    title: content?["title"] as? String ?? "未命名",
                    number: content?["number"] as? Int,
                    status: status,
                    fieldId: fieldId,
                    optionId: optionId
                )
            }
            error = nil
        } catch { self.error = errText(error) }
    }

    private func setStatus(item: BoardItem, field: ProjectField, option: ProjectOption) async {
        let q = """
        mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $project, itemId: $item, fieldId: $field,
            value: { singleSelectOptionId: $option }
          }) { projectV2Item { id } }
        }
        """
        do {
            _ = try await API.shared.gql(q, ["project": id, "item": item.id, "field": field.id, "option": option.id])
            info = "已更新「\(item.title)」"
            await load()
        } catch { self.error = errText(error) }
    }
}

struct MergeQueueView: View {
    let repo: Repo
    @State private var rows: [String] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            if rows.isEmpty && error == nil { Text("队列是空的，或此仓库没有开启合并队列。").foregroundStyle(.secondary) }
            ForEach(rows, id: \.self) { Text($0) }
            if let u = URL(string: "https://github.com/\(repo.fullName)/queue") {
                Link("在网页查看合并队列", destination: u)
            }
        }
        .navigationTitle("合并队列")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let parts = splitRepo(repo.fullName)
        let q = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            mergeQueue {
              entries(first: 30) { nodes { position state pullRequest { number title } } }
            }
          }
        }
        """
        do {
            let data = try await API.shared.gql(q, ["owner": parts.owner, "name": parts.name])
            let queue = ((data["repository"] as? [String: Any])?["mergeQueue"] as? [String: Any])
            let nodes = ((queue?["entries"] as? [String: Any])?["nodes"] as? [Any]) ?? []
            rows = nodes.compactMap { n in
                guard let o = n as? [String: Any] else { return nil }
                let pr = o["pullRequest"] as? [String: Any]
                let num = pr?["number"] as? Int ?? 0
                let title = pr?["title"] as? String ?? ""
                let pos = o["position"] as? Int ?? 0
                let state = o["state"] as? String ?? ""
                return "#\(pos) \(state) #\(num) \(title)"
            }
        } catch {
            self.error = errText(error) ?? "当前令牌或 API 无法读取合并队列"
        }
    }
}
