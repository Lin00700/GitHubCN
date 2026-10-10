import SwiftUI

// MARK: - 对话会话

@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMsg] = []
    @Published var sending = false
    @Published var errorMsg: String?
    private var task: Task<Void, Never>?

    func send(_ text: String, system: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || sending { return }
        guard let p = AIStore.shared.current else {
            errorMsg = "请先添加 AI 服务商（右上角设置）"
            return
        }
        errorMsg = nil
        messages.append(ChatMsg(role: "user", content: t))
        messages.append(ChatMsg(role: "assistant", content: ""))
        let history = Array(messages.dropLast())
        let key = AIStore.shared.key(for: p)
        sending = true
        task = Task {
            do {
                try await AIClient.stream(profile: p, key: key, messages: history, system: system) { piece in
                    self.appendDelta(piece)
                }
            } catch {
                if !(error is CancellationError) {
                    self.errorMsg = errText(error)
                }
            }
            self.sending = false
            if let last = self.messages.last, last.role == "assistant", last.content.isEmpty {
                self.messages.removeLast()
            }
        }
    }

    func stop() { task?.cancel() }

    func clear() {
        task?.cancel()
        messages = []
        errorMsg = nil
        sending = false
    }

    private func appendDelta(_ s: String) {
        if !messages.isEmpty {
            messages[messages.count - 1].content += s
        }
    }
}

// MARK: - 对话界面

struct AIChatView: View {
    var contextTitle: String? = nil
    var contextText: String? = nil
    var quickPrompts: [String] = ["解释一个 GitHub Actions 报错", "帮我写 Swift 项目的 .gitignore", "SideStore 刷新失败怎么排查？"]

    @StateObject private var session = ChatSession()
    @ObservedObject private var store = AIStore.shared
    @State private var input = ""

    private var systemPrompt: String {
        var s = "你是一个熟悉 GitHub、Git、CI/CD 和 iOS 开发的助手。默认使用简体中文回答，回答简洁，代码用 Markdown 代码块。"
        if let t = contextText, !t.isEmpty {
            s += "\n\n用户正在查看「\(contextTitle ?? "")」，内容如下：\n\(t)"
        }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            providerBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.messages.isEmpty { welcome }
                        ForEach(session.messages) { m in
                            bubble(m).id(m.id)
                        }
                        if let e = session.errorMsg {
                            Text(e).font(.footnote).foregroundColor(.red).neonCard()
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages.last?.content) { _ in
                    if let last = session.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            inputBar
        }
        .neonBackground()
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AISettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private var providerBar: some View {
        HStack {
            Menu {
                ForEach(store.profiles) { p in
                    Button("\(p.name) · \(p.model)") { store.selectedID = p.id }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                    Text(store.current.map { "\($0.name) · \($0.model)" } ?? "未配置服务商")
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption)
                }
                .font(.footnote.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
            }
            Spacer()
            Button {
                session.clear()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(session.messages.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI 助手", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.gradient)
            if let t = contextTitle {
                Text("已带入「\(t)」的内容，可以直接提问。")
                    .font(.footnote)
                    .foregroundColor(Theme.textDim)
            }
            if store.profiles.isEmpty {
                Text("还没有配置 AI 服务商。")
                    .font(.footnote)
                    .foregroundColor(Theme.textDim)
                NavigationLink(destination: AISettingsView()) {
                    Label("添加服务商", systemImage: "plus.circle")
                }
            } else {
                ForEach(quickPrompts, id: \.self) { q in
                    Button {
                        session.send(q, system: systemPrompt)
                    } label: {
                        Text(q)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.card))
                            .overlay(Capsule().stroke(Theme.purple.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .neonCard()
    }

    @ViewBuilder
    private func bubble(_ m: ChatMsg) -> some View {
        if m.role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(m.content)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Theme.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if m.content.isEmpty {
                    ProgressView()
                } else {
                    MarkdownView(blocks: MD.parse(m.content, sanitize: false))
                }
                if !m.content.isEmpty && !session.sending {
                    Button {
                        UIPasteboard.general.string = m.content
                    } label: {
                        Label("复制", systemImage: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.cyan)
                }
            }
            .neonCard()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("向 AI 提问…", text: $input)
                .submitLabel(.send)
                .onSubmit { sendInput() }
                .neonField()
            Button {
                if session.sending { session.stop() } else { sendInput() }
            } label: {
                Image(systemName: session.sending ? "stop.fill" : "arrow.up")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.gradient)
                    .clipShape(Circle())
            }
            .disabled(!session.sending && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.bg.opacity(0.92))
    }

    private func sendInput() {
        let t = input
        input = ""
        session.send(t, system: systemPrompt)
    }
}

// MARK: - 服务商设置

struct AISettingsView: View {
    @ObservedObject private var store = AIStore.shared

    var body: some View {
        List {
            Section(
                header: Text("服务商"),
                footer: Text("支持任何 OpenAI 兼容接口（地址填到 /v1 为止）和 Anthropic 接口。API Key 只保存在本机钥匙串。")
            ) {
                ForEach(store.profiles) { p in
                    NavigationLink(destination: AIProfileEditor(profile: p)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name).font(.headline)
                                Text("\(p.model) · \(p.baseURL)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if store.current?.id == p.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.cyan)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { store.remove(store.profiles[i]) }
                }
            }
            Section {
                NavigationLink(destination: AIProfileEditor(profile: nil)) {
                    Label("添加服务商", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .neonBackground()
        .navigationTitle("AI 服务商")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AIProfileEditor: View {
    @ObservedObject private var store = AIStore.shared
    @Environment(\.presentationMode) private var mode
    @State private var profile: AIProfile
    @State private var apiKey: String
    @State private var models: [String] = []
    @State private var busy = false
    @State private var info: String?
    @State private var errorMsg: String?
    private let isNew: Bool

    init(profile: AIProfile?) {
        let p = profile ?? AIProfile(name: "", baseURL: "", model: "")
        isNew = (profile == nil)
        _profile = State(initialValue: p)
        _apiKey = State(initialValue: profile.map { AIStore.shared.key(for: $0) } ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("快速填入")) {
                Menu {
                    ForEach(aiPresets) { pr in
                        Button(pr.name) { apply(pr) }
                    }
                } label: {
                    Label("选择预设服务商", systemImage: "wand.and.stars")
                }
            }
            Section(header: Text("服务商")) {
                TextField("名称（自己起，例如 我的 DeepSeek）", text: $profile.name)
                Picker("协议", selection: $profile.format) {
                    ForEach(AIFormat.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                TextField("API 地址，例如 https://api.openai.com/v1", text: $profile.baseURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                TextField("模型，例如 gpt-4o-mini", text: $profile.model)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !models.isEmpty {
                    Menu {
                        ForEach(models, id: \.self) { m in
                            Button(m) { profile.model = m }
                        }
                    } label: {
                        Label("从 \(models.count) 个模型里选择", systemImage: "list.bullet")
                    }
                }
            }
            Section(header: Text("API Key"), footer: Text("本地模型（如 Ollama）可以留空。")) {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            Section {
                Button {
                    Task { await fetchModels() }
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text("测试连接 / 获取模型列表")
                    }
                }
                .disabled(profile.baseURL.isEmpty || busy)
                if let i = info { Text(i).font(.footnote).foregroundColor(.green) }
                if let e = errorMsg { Text(e).font(.footnote).foregroundColor(.red) }
            }
            Section {
                Button("保存") { save() }
                    .disabled(profile.baseURL.isEmpty || profile.model.isEmpty)
                if !isNew {
                    Button("设为当前服务商") { store.selectedID = profile.id }
                }
            }
        }
        .listStyle(.insetGrouped)
        .neonBackground()
        .navigationTitle(isNew ? "添加服务商" : "编辑服务商")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func apply(_ pr: AIPreset) {
        profile.name = pr.name
        profile.baseURL = pr.baseURL
        profile.model = pr.model
        profile.format = pr.format
        models = []
    }

    private func fetchModels() async {
        busy = true
        info = nil
        errorMsg = nil
        do {
            let list = try await AIClient.listModels(profile: profile, key: apiKey)
            models = list
            info = list.isEmpty ? "连接成功，但没有返回模型列表，请手动填写模型名" : "连接成功，共 \(list.count) 个模型"
        } catch {
            errorMsg = (errText(error) ?? "失败") + "（有些服务不提供模型列表，仍可手动填写模型后保存）"
        }
        busy = false
    }

    private func save() {
        var p = profile
        p.name = p.name.trimmingCharacters(in: .whitespaces)
        if p.name.isEmpty { p.name = URL(string: p.baseURL)?.host ?? "AI" }
        if let i = store.profiles.firstIndex(where: { $0.id == p.id }) {
            store.profiles[i] = p
        } else {
            store.profiles.append(p)
        }
        store.setKey(apiKey, for: p)
        if store.selectedID == nil || isNew { store.selectedID = p.id }
        mode.wrappedValue.dismiss()
    }
}
