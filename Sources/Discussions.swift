import SwiftUI

struct DiscussionItem: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let body: String
    let url: String?
    let createdAt: String?
    let author: String
    let avatar: String?
    let category: String
    let comments: Int
    let upvotes: Int
}

struct DiscussionCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
}

struct DiscussionsView: View {
    let fullName: String
    @State private var repoID = ""
    @State private var items: [DiscussionItem] = []
    @State private var categories: [DiscussionCategory] = []
    @State private var error: String?
    @State private var loading = true
    @State private var showNew = false

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && items.isEmpty { ProgressView() }
            if !loading && items.isEmpty && error == nil {
                EmptyHint(title: "没有讨论", systemImage: "bubble.left.and.bubble.right", message: "仓库可能没有开启讨论。")
            }
            ForEach(items) { d in
                NavigationLink { DiscussionDetailView(fullName: fullName, number: d.number) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.title).font(.body).lineLimit(2)
                        Text("\(d.category) · \(d.author) · \(d.comments) 条评论 · \(relTime(d.createdAt))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("讨论")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .disabled(categories.isEmpty)
                    .accessibilityLabel("新建讨论")
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                NewDiscussionView(repoID: repoID, categories: categories) { Task { await load() } }
            }
        }
    }

    private func load() async {
        loading = items.isEmpty
        let parts = splitRepo(fullName)
        let q = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            id
            discussionCategories(first: 20) { nodes { id name emoji } }
            discussions(first: 30, orderBy: {field: UPDATED_AT, direction: DESC}) {
              nodes {
                id number title body url createdAt upvoteCount
                author { login avatarUrl }
                category { name }
                comments { totalCount }
              }
            }
          }
        }
        """
        do {
            let data = try await API.shared.gql(q, ["owner": parts.owner, "name": parts.name])
            let repo = data["repository"] as? [String: Any] ?? [:]
            repoID = repo["id"] as? String ?? ""
            categories = ((repo["discussionCategories"] as? [String: Any])?["nodes"] as? [Any] ?? []).compactMap { n in
                guard let o = n as? [String: Any], let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
                return DiscussionCategory(id: id, name: name, emoji: o["emoji"] as? String ?? "")
            }
            items = ((repo["discussions"] as? [String: Any])?["nodes"] as? [Any] ?? []).compactMap(parseDiscussion)
            error = nil
        } catch { self.error = errText(error) }
        loading = false
    }
}

func parseDiscussion(_ any: Any) -> DiscussionItem? {
    guard let o = any as? [String: Any], let number = o["number"] as? Int else { return nil }
    let author = o["author"] as? [String: Any]
    let comments = (o["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0
    return DiscussionItem(
        id: o["id"] as? String ?? "\(number)",
        number: number,
        title: o["title"] as? String ?? "",
        body: o["body"] as? String ?? "",
        url: o["url"] as? String,
        createdAt: o["createdAt"] as? String,
        author: author?["login"] as? String ?? "",
        avatar: author?["avatarUrl"] as? String,
        category: (o["category"] as? [String: Any])?["name"] as? String ?? "",
        comments: comments,
        upvotes: o["upvoteCount"] as? Int ?? 0
    )
}

struct DiscussionDetailView: View {
    let fullName: String
    let number: Int
    @State private var item: DiscussionItem?
    @State private var comments: [(String, String, String, String)] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var zh = false

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let d = item {
                Section {
                    Text(d.title).font(.title3.bold())
                    Text("\(d.category) · \(d.author) · \(relTime(d.createdAt)) · \(d.upvotes) 赞")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("点赞") { Task { await react(d.id) } }
                    if let u = d.url.flatMap(URL.init(string:)) { Link("在 Safari 中打开", destination: u) }
                    TranslateBar(on: $zh)
                    TranslatableMarkdown(text: d.body, translate: zh)
                }
                Section("评论 \(comments.count)") {
                    ForEach(comments.indices, id: \.self) { i in
                        let c = comments[i]
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(c.1) · \(relTime(c.2))").font(.caption).foregroundStyle(.secondary)
                            TranslatableMarkdown(text: c.3, translate: zh)
                        }
                    }
                    TextField("回复", text: $draft, axis: .vertical)
                    Button("发送") { Task { await reply() } }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if error == nil { ProgressView() }
        }
        .navigationTitle("#\(number)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let parts = splitRepo(fullName)
        let q = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            discussion(number: $number) {
              id number title body url createdAt upvoteCount
              author { login avatarUrl }
              category { name }
              comments(first: 50) {
                nodes {
                  id body createdAt
                  author { login }
                  replies(first: 20) { nodes { id body createdAt author { login } } }
                }
              }
            }
          }
        }
        """
        do {
            let data = try await API.shared.gql(q, ["owner": parts.owner, "name": parts.name, "number": number])
            let d = ((data["repository"] as? [String: Any])?["discussion"] as? [String: Any]) ?? [:]
            guard let parsed = parseDiscussion(d) else { error = "没有找到讨论"; return }
            item = parsed
            var rows: [(String, String, String, String)] = []
            let nodes = ((d["comments"] as? [String: Any])?["nodes"] as? [Any]) ?? []
            for n in nodes {
                guard let o = n as? [String: Any] else { continue }
                let id = o["id"] as? String ?? UUID().uuidString
                let who = (o["author"] as? [String: Any])?["login"] as? String ?? ""
                rows.append((id, who, o["createdAt"] as? String ?? "", o["body"] as? String ?? ""))
                let replies = ((o["replies"] as? [String: Any])?["nodes"] as? [Any]) ?? []
                for r in replies {
                    guard let rr = r as? [String: Any] else { continue }
                    let rw = (rr["author"] as? [String: Any])?["login"] as? String ?? ""
                    rows.append((rr["id"] as? String ?? UUID().uuidString, "↳ \(rw)", rr["createdAt"] as? String ?? "", rr["body"] as? String ?? ""))
                }
            }
            comments = rows
            error = nil
        } catch { self.error = errText(error) }
    }

    private func reply() async {
        guard let id = item?.id else { return }
        let q = """
        mutation($id: ID!, $body: String!) {
          addDiscussionComment(input: {discussionId: $id, body: $body}) { comment { id } }
        }
        """
        do {
            _ = try await API.shared.gql(q, ["id": id, "body": draft])
            draft = ""
            await load()
        } catch { self.error = errText(error) }
    }

    private func react(_ id: String) async {
        let q = """
        mutation($id: ID!) {
          addReaction(input: {subjectId: $id, content: THUMBS_UP}) { reaction { content } }
        }
        """
        do { _ = try await API.shared.gql(q, ["id": id]); await load() }
        catch { self.error = errText(error) }
    }
}

struct NewDiscussionView: View {
    let repoID: String
    let categories: [DiscussionCategory]
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var cat = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("分类", selection: $cat) {
                ForEach(categories) { c in Text("\(c.emoji) \(c.name)").tag(c.id) }
            }
            TextField("标题", text: $title)
            TextField("正文", text: $bodyText, axis: .vertical).lineLimit(6...16)
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await create() } } label: {
                HStack { if busy { ProgressView() }; Text("发布") }
            }
            .disabled(busy || title.isEmpty || cat.isEmpty)
        }
        .navigationTitle("新建讨论")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .onAppear { if cat.isEmpty { cat = categories.first?.id ?? "" } }
    }

    private func create() async {
        busy = true
        let q = """
        mutation($id: ID!, $cat: ID!, $title: String!, $body: String!) {
          createDiscussion(input: {repositoryId: $id, categoryId: $cat, title: $title, body: $body}) {
            discussion { number }
          }
        }
        """
        do {
            _ = try await API.shared.gql(q, ["id": repoID, "cat": cat, "title": title, "body": bodyText])
            onDone()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}
