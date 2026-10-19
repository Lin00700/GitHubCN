import SwiftUI

// MARK: - 对话会话（支持工具调用 Agent）

@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMsg] = []
    @Published var sending = false
    @Published var errorMsg: String?
    /// 等待用户确认的写操作
    @Published var pendingWrites: [AIToolCall] = []
    @Published var agentStatus: String?

    private var task: Task<Void, Never>?
    /// 发给模型的完整历史（含 tool 消息），与 UI messages 分离
    private var wireMessages: [[String: Any]] = []
    private var systemPromptCache = ""
    private var confirmContinuation: CheckedContinuation<[AIToolResult], Never>?

    func send(_ text: String, system: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || sending { return }
        guard let p = AIStore.shared.current else {
            errorMsg = "请先添加 AI 服务商（右上角设置）"
            return
        }
        errorMsg = nil
        systemPromptCache = system + agentSystemSuffix
        messages.append(ChatMsg(role: "user", content: t))
        wireMessages.append(["role": "user", "content": t])
        messages.append(ChatMsg(role: "assistant", content: ""))
        let key = AIStore.shared.key(for: p)
        sending = true
        agentStatus = "思考中…"
        task = Task {
            await runAgent(profile: p, key: key)
            self.sending = false
            self.agentStatus = nil
            if let last = self.messages.last, last.role == "assistant", last.content.isEmpty,
               self.pendingWrites.isEmpty {
                self.messages.removeLast()
            }
        }
    }

    func stop() {
        task?.cancel()
        if let cont = confirmContinuation {
            confirmContinuation = nil
            cont.resume(returning: pendingWrites.map {
                AIToolResult(toolCallId: $0.id, name: $0.name, content: "用户取消了操作", isError: true)
            })
        }
        pendingWrites = []
        sending = false
        agentStatus = nil
    }

    func clear() {
        task?.cancel()
        if let cont = confirmContinuation {
            confirmContinuation = nil
            cont.resume(returning: [])
        }
        messages = []
        wireMessages = []
        pendingWrites = []
        errorMsg = nil
        sending = false
        agentStatus = nil
    }

    /// 用户确认执行写操作
    func approvePending() {
        let calls = pendingWrites
        pendingWrites = []
        Task {
            var results: [AIToolResult] = []
            for c in calls {
                agentStatus = "执行：\(AITools.humanSummary(c))"
                results.append(await AITools.execute(c))
            }
            confirmContinuation?.resume(returning: results)
            confirmContinuation = nil
        }
    }

    /// 用户拒绝写操作
    func rejectPending() {
        let calls = pendingWrites
        pendingWrites = []
        let results = calls.map {
            AIToolResult(toolCallId: $0.id, name: $0.name, content: "用户拒绝执行此操作", isError: true)
        }
        confirmContinuation?.resume(returning: results)
        confirmContinuation = nil
    }

    private var agentSystemSuffix: String {
        """


你可以使用工具直接操作用户的 GitHub（通过用户已登录的令牌）。
规则：
1. 需要真实数据时优先调用工具，不要编造仓库/议题/文件内容。
2. 写操作（创建议题、评论、提交文件、删除、触发构建等）会先让用户确认，你只需正常调用工具。
3. repo 参数统一用 owner/name 格式。
4. 用简体中文回复，简洁；代码用 Markdown 代码块。
5. 一次可以并行调用多个只读工具；写操作尽量说明意图。
"""
    }

    private func runAgent(profile p: AIProfile, key: String) async {
        var rounds = 0
        while rounds < 8 {
            rounds += 1
            if Task.isCancelled { return }
            do {
                agentStatus = rounds == 1 ? "思考中…" : "继续处理（第 \(rounds) 轮）…"
                let turn = try await AIClient.agentTurn(
                    profile: p,
                    key: key,
                    messages: wireMessages,
                    system: systemPromptCache
                )

                // 更新最后一条 assistant 气泡
                if !turn.text.isEmpty {
                    appendAssistantText(turn.text)
                }

                if turn.toolCalls.isEmpty {
                    // 结束
                    if turn.text.isEmpty {
                        appendAssistantText("（没有返回内容）")
                    }
                    return
                }

                // 记录 assistant 带 tool_calls 的消息
                if let raw = turn.rawAssistant {
                    if p.format == .openai {
                        wireMessages.append(raw)
                    } else {
                        wireMessages.append(raw)
                    }
                }

                // 展示工具意图
                let summary = turn.toolCalls.map { "• \(AITools.humanSummary($0))" }.joined(separator: "\n")
                messages.append(ChatMsg(
                    role: "assistant",
                    content: "将执行：\n\(summary)",
                    isLocalNotice: true
                ))

                let reads = turn.toolCalls.filter { AITools.kind(of: $0.name) == .read }
                let writes = turn.toolCalls.filter { AITools.kind(of: $0.name) == .write }

                var results: [AIToolResult] = []

                // 只读直接执行
                for c in reads {
                    if Task.isCancelled { return }
                    agentStatus = "执行：\(AITools.humanSummary(c))"
                    let r = await AITools.execute(c)
                    results.append(r)
                    messages.append(ChatMsg(
                        role: "tool",
                        content: r.isError ? "❌ \(r.content)" : "✅ \(String(r.content.prefix(500)))",
                        toolCallId: r.toolCallId,
                        toolName: r.name,
                        isLocalNotice: true
                    ))
                }

                // 写操作等待确认
                if !writes.isEmpty {
                    agentStatus = "等待确认写操作…"
                    pendingWrites = writes
                    let writeResults: [AIToolResult] = await withCheckedContinuation { cont in
                        confirmContinuation = cont
                    }
                    if Task.isCancelled { return }
                    for r in writeResults {
                        results.append(r)
                        messages.append(ChatMsg(
                            role: "tool",
                            content: r.isError ? "❌ \(r.content)" : "✅ \(r.content)",
                            toolCallId: r.toolCallId,
                            toolName: r.name,
                            isLocalNotice: true
                        ))
                    }
                }

                // 把工具结果写回 wire
                appendToolResultsToWire(results, format: p.format)

                // 准备下一条空 assistant 气泡
                messages.append(ChatMsg(role: "assistant", content: ""))

            } catch {
                if !(error is CancellationError) {
                    self.errorMsg = errText(error)
                }
                return
            }
        }
        appendAssistantText("已达到最大工具调用轮数，请根据上方结果继续提问。")
    }

    private func appendAssistantText(_ s: String) {
        if let i = messages.lastIndex(where: { $0.role == "assistant" && !$0.isLocalNotice }) {
            if messages[i].content.isEmpty {
                messages[i].content = s
            } else {
                messages[i].content += s
            }
        } else {
            messages.append(ChatMsg(role: "assistant", content: s))
        }
    }

    private func appendToolResultsToWire(_ results: [AIToolResult], format: AIFormat) {
        switch format {
        case .openai:
            for r in results {
                wireMessages.append([
                    "role": "tool",
                    "tool_call_id": r.toolCallId,
                    "content": r.content
                ])
            }
        case .anthropic:
            // Anthropic: user message with tool_result blocks
            var blocks: [[String: Any]] = []
            for r in results {
                blocks.append([
                    "type": "tool_result",
                    "tool_use_id": r.toolCallId,
                    "content": r.content,
                    "is_error": r.isError
                ])
            }
            wireMessages.append(["role": "user", "content": blocks])
        }
    }
}

// MARK: - 对话界面

struct AIChatView: View {
    var contextTitle: String? = nil
    var contextText: String? = nil
    var quickPrompts: [String] = [
        "列出我最近更新的仓库",
        "帮我查看某个仓库的构建是否失败",
        "在指定仓库创建一条议题",
        "解释一个 GitHub Actions 报错"
    ]

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
                        if let st = session.agentStatus {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(st).font(.footnote).foregroundColor(Theme.textDim)
                            }
                            .neonCard()
                        }
                        if let e = session.errorMsg {
                            Text(e).font(.footnote).foregroundColor(.red).neonCard()
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages.count) { _ in
                    if let last = session.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: session.messages.last?.content) { _ in
                    if let last = session.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            if !session.pendingWrites.isEmpty {
                confirmBar
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

    private var confirmBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("以下操作会修改你的 GitHub，请确认：")
                .font(.footnote.bold())
            ForEach(session.pendingWrites) { c in
                Text("• \(AITools.humanSummary(c))")
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
            }
            HStack {
                Button("拒绝") { session.rejectPending() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("确认执行") { session.approvePending() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Theme.card)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.purple.opacity(0.5)), alignment: .top)
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
            Label("AI 助手 · 可操作 GitHub", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.gradient)
            Text("已支持：列仓库/文件、读写议题、提交代码、触发构建等。写操作会先让你确认。\n请使用支持 tools / function calling 的模型（如 GPT-4o、Claude、DeepSeek 等）。")
                .font(.footnote)
                .foregroundColor(Theme.textDim)
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
        } else if m.role == "tool" || m.isLocalNotice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: m.role == "tool" ? "wrench.and.screwdriver" : "info.circle")
                    .font(.caption)
                    .foregroundColor(Theme.cyan)
                Text(m.content)
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cyan.opacity(0.25), lineWidth: 1))
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
            TextField("向 AI 提问或下达操作指令…", text: $input)
                .submitLabel(.send)
                .onSubmit { sendInput() }
                .neonField()
                .disabled(!session.pendingWrites.isEmpty)
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
            .disabled(!session.sending && (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.pendingWrites.isEmpty))
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
                footer: Text("支持任何 OpenAI 兼容接口（地址填到 /v1 为止）和 Anthropic 接口。API Key 只保存在本机钥匙串。\nAgent 操作需要模型支持 tools / function calling。")
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
