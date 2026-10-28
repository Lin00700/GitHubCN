import SwiftUI

struct WikiView: View {
    let fullName: String
    @State private var pages: [ContentItem] = []
    @State private var error: String?
    @State private var loading = true
    @State private var showNew = false

    private var wikiRepo: String { fullName + ".wiki" }

    var body: some View {
        List {
            if let error { InlineError(message: error) { Task { await load() } } }
            if loading && pages.isEmpty { ProgressView() }
            if !loading && pages.isEmpty && error == nil {
                EmptyHint(title: "没有维基", systemImage: "book", message: "维基是一个单独的 Git 仓库。没有页面或未开启时会是空的。")
            }
            ForEach(pages) { p in
                NavigationLink { WikiPageView(wikiRepo: wikiRepo, path: p.path, title: p.name) } label: {
                    Label(p.name, systemImage: "doc.richtext")
                }
            }
        }
        .navigationTitle("维基")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建页面")
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { WikiEditor(wikiRepo: wikiRepo, path: nil, sha: nil, initial: "") { Task { await load() } } }
        }
    }

    private func load() async {
        loading = pages.isEmpty
        do {
            let list: [ContentItem] = try await API.shared.get("/repos/\(wikiRepo)/contents/")
            pages = list.filter { $0.type == "file" && $0.name.lowercased().hasSuffix(".md") }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
            error = nil
        } catch {
            pages = []
            self.error = errText(error)
        }
        loading = false
    }
}

struct WikiPageView: View {
    let wikiRepo: String
    let path: String
    let title: String
    @State private var text = ""
    @State private var sha: String?
    @State private var zh = false
    @State private var error: String?
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                if text.isEmpty && error == nil { ProgressView() }
                TranslateBar(on: $zh)
                TranslatableMarkdown(text: text, translate: zh)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title.replacingOccurrences(of: ".md", with: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") { editing = true }.disabled(text.isEmpty && sha == nil)
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { WikiEditor(wikiRepo: wikiRepo, path: path, sha: sha, initial: text) { Task { await load() } } }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let file: RemoteFile = try await API.shared.get("/repos/\(wikiRepo)/contents/\(encPath(path))")
            sha = file.sha
            text = file.text ?? ""
            error = nil
        } catch { self.error = errText(error) }
    }
}

struct WikiEditor: View {
    let wikiRepo: String
    var path: String?
    var sha: String?
    var initial: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            if path == nil {
                TextField("页面名，例如 Home", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            TextField("Markdown", text: $text, axis: .vertical).lineLimit(12...30)
                .font(.system(.footnote, design: .monospaced))
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await save() } } label: {
                HStack { if busy { ProgressView() }; Text("提交") }
            }
            .disabled(busy || text.isEmpty || (path == nil && name.isEmpty))
        }
        .navigationTitle(path == nil ? "新建维基页" : "编辑维基")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .onAppear {
            text = initial
            if let path { name = path }
        }
    }

    private func save() async {
        busy = true
        error = nil
        let page = path ?? (name.hasSuffix(".md") ? name : name + ".md")
        var body: [String: Any] = [
            "message": path == nil ? "新建 \(page)" : "更新 \(page)",
            "content": Data(text.utf8).base64EncodedString(),
            "branch": "master"
        ]
        if let sha { body["sha"] = sha }
        do {
            try await API.shared.put("/repos/\(wikiRepo)/contents/\(encPath(page))", body: body)
            onDone()
            dismiss()
        } catch {
            body["branch"] = "main"
            do {
                try await API.shared.put("/repos/\(wikiRepo)/contents/\(encPath(page))", body: body)
                onDone()
                dismiss()
            } catch {
                self.error = errText(error)
            }
        }
        busy = false
    }
}
