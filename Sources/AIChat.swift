import SwiftUI
import Foundation

// OpenAI-compatible Chat Completions API client.
// Supports OpenAI-compatible providers: set Base URL, API key, and model in Settings.
private struct AIMessage: Codable {
    let role: String
    let content: String
}
private struct AIRequest: Encodable {
    let model: String
    let messages: [AIMessage]
    let stream: Bool
}
private struct AIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let role: String?; let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

@MainActor
final class AIChatModel: ObservableObject {
    @Published var messages: [(role: String, text: String)] = [
        ("assistant", "你好！我可以协助解释 Swift 代码、分析 GitHub 仓库、编写 Issue/PR 草稿。请在设置中填写兼容 OpenAI Chat Completions 的 API 地址、模型和密钥。")
    ]
    @Published var input = ""
    @Published var busy = false
    @Published var error: String?

    private let defaults = UserDefaults.standard
    var baseURL: String {
        get { defaults.string(forKey: "ai_base_url") ?? "https://api.openai.com/v1" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai_base_url") }
    }
    var model: String {
        get { defaults.string(forKey: "ai_model") ?? "gpt-4o-mini" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai_model") }
    }
    var apiKey: String {
        get { defaults.string(forKey: "ai_api_key") ?? "" }
        set { defaults.set(newValue, forKey: "ai_api_key") }
    }

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy else { return }
        guard !apiKey.isEmpty else { error = "请先在右上角设置中填写 AI API Key。"; return }
        guard !model.isEmpty else { error = "模型名称不能为空。"; return }
        guard let base = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            error = "Base URL 无效。"; return
        }

        input = ""
        messages.append(("user", prompt))
        busy = true
        error = nil
        defer { busy = false }

        do {
            var request = URLRequest(url: base)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let history = messages.suffix(20).map { AIMessage(role: $0.role, content: $0.text) }
            request.httpBody = try JSONEncoder().encode(AIRequest(model: model, messages: history, stream: false))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NSError(domain: "AI", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的服务器响应"]) }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "AI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)：\(String(body.prefix(600)))"])
            }
            let decoded = try JSONDecoder().decode(AIResponse.self, from: data)
            guard let answer = decoded.choices.first?.message.content, !answer.isEmpty else {
                throw NSError(domain: "AI", code: -2, userInfo: [NSLocalizedDescriptionKey: "接口返回成功，但没有可显示的文本。"])
            }
            messages.append(("assistant", answer))
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clear() {
        messages = []
        error = nil
    }
}

struct AIChatView: View {
    @StateObject private var vm = AIChatModel()
    @State private var showSettings = false

    private let suggestions = ["解释一段 Swift 代码", "分析 GitHub Actions 失败", "帮我写一个 Issue", "审查这段代码的安全性"]

    var body: some View {
        NavigationView {
            ZStack {
                NeonBackground()
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15).fill(NeonTheme.violet.opacity(0.18)).frame(width: 48, height: 48)
                            Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 22)).foregroundStyle(NeonTheme.violet)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AI DEV COPILOT").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(NeonTheme.cyan)
                            Text("开发者 AI 助手").font(.headline)
                        }
                        Spacer()
                        Circle().fill(NeonTheme.green).frame(width: 7, height: 7)
                        Text(vm.apiKey.isEmpty ? "未配置" : "已配置").font(.caption).foregroundStyle(.white.opacity(0.55))
                    }.padding(.horizontal, 16).padding(.vertical, 12)

                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if vm.messages.count <= 1 {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text("BUILD SOMETHING\nBRILLIANT.")
                                            .font(.system(size: 29, weight: .black, design: .rounded))
                                            .foregroundStyle(LinearGradient(colors: [NeonTheme.cyan, NeonTheme.violet], startPoint: .leading, endPoint: .trailing))
                                        Text("问我代码、仓库、构建日志或开发方案。接入你喜欢的 AI 服务，工作流由你掌控。")
                                            .font(.subheadline).foregroundStyle(.white.opacity(0.58)).lineSpacing(4)
                                        Text("试试这些").font(.caption.bold()).foregroundStyle(.white.opacity(0.45)).padding(.top, 4)
                                        ForEach(suggestions, id: \.self) { suggestion in
                                            Button {
                                                vm.input = suggestion
                                            } label: {
                                                HStack {
                                                    Image(systemName: "arrow.up.right.circle").foregroundStyle(NeonTheme.cyan)
                                                    Text(suggestion).foregroundStyle(.white.opacity(0.86))
                                                    Spacer()
                                                }.padding(12).background(.white.opacity(0.045)).overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.07), lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 13))
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                    .padding(16).background(NeonTheme.panel.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 22))
                                    .padding(.top, 12)
                                }

                                ForEach(Array(vm.messages.enumerated()), id: \.offset) { index, item in
                                    HStack(alignment: .top, spacing: 9) {
                                        if item.role == "assistant" {
                                            Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(NeonTheme.cyan)
                                                .frame(width: 28, height: 28).background(NeonTheme.cyan.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 9))
                                            Text(item.text).textSelection(.enabled)
                                                .font(.system(size: 15)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(13).background(NeonTheme.panel).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 16))
                                        } else {
                                            Spacer(minLength: 32)
                                            Text(item.text).textSelection(.enabled).font(.system(size: 15)).lineSpacing(4)
                                                .padding(13).foregroundStyle(.white)
                                                .background(LinearGradient(colors: [NeonTheme.violet.opacity(0.55), Color.blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                        }
                                    }.id(index)
                                }
                                if vm.busy {
                                    HStack(spacing: 9) { ProgressView().tint(NeonTheme.cyan); Text("AI 正在思考…").font(.caption).foregroundStyle(.white.opacity(0.55)) }
                                        .padding(12).background(NeonTheme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }.padding(.horizontal, 14).padding(.bottom, 18)
                        }
                        .onChange(of: vm.messages.count) { _ in
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(vm.messages.count - 1, anchor: .bottom) }
                        }
                    }

                    if let e = vm.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(e).font(.caption).lineLimit(4)
                        }.foregroundStyle(.red).padding(.horizontal, 14).padding(.vertical, 8)
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("发消息给 AI…", text: $vm.input, axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...5).padding(.horizontal, 14).padding(.vertical, 12)
                            .background(.white.opacity(0.07)).overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.1), lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 17))
                        Button { Task { await vm.send() } } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 46, height: 46)
                                .background(LinearGradient(colors: [NeonTheme.cyan, NeonTheme.green], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                        }.disabled(vm.busy || vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(vm.busy || vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { vm.clear() } label: { Image(systemName: "arrow.counterclockwise").foregroundStyle(.white.opacity(0.7)) }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { vm.clear() } label: { Image(systemName: "trash").foregroundStyle(.white.opacity(0.7)) }
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(NeonTheme.cyan) }
                }
            }
            .sheet(isPresented: $showSettings) { AISettingsView(vm: vm).preferredColorScheme(.dark) }
        }.navigationViewStyle(.stack)
    }
}

struct AISettingsView: View {
    @ObservedObject var vm: AIChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var preset = "自定义 / OpenAI 兼容"
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""

    private let presets: [String: (String, String)] = [
        "OpenAI": ("https://api.openai.com/v1", "gpt-4o-mini"),
        "DeepSeek": ("https://api.deepseek.com/v1", "deepseek-chat"),
        "Google Gemini（OpenAI 兼容入口）": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.5-flash"),
        "OpenRouter": ("https://openrouter.ai/api/v1", "openai/gpt-4o-mini"),
        "自定义 / OpenAI 兼容": ("https://你的服务地址/v1", "你的模型名称")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务商预设")) {
                    Picker("服务商", selection: $preset) {
                        ForEach(Array(presets.keys).sorted(), id: \.self) { Text($0).tag($0) }
                    }.onChange(of: preset) { value in
                        if let p = presets[value] { baseURL = p.0; model = p.1 }
                    }
                }
                Section(header: Text("API 配置"), footer: Text("仅支持兼容 OpenAI Chat Completions 格式的接口。不同服务商的模型名、URL 和参数可能不同；如服务商不兼容，请使用其兼容入口。")) {
                    TextField("Base URL，例如 https://api.openai.com/v1", text: $baseURL)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Button("保存设置") {
                        vm.baseURL = baseURL
                        vm.model = model
                        vm.apiKey = apiKey
                        dismiss()
                    }
                    Button("测试连接") {
                        vm.baseURL = baseURL
                        vm.model = model
                        vm.apiKey = apiKey
                        dismiss()
                        Task { vm.input = "请只回复：连接成功"; await vm.send() }
                    }
                }
                Section(footer: Text("安全提醒：此版本把 API Key 存在本机 UserDefaults 中，不适合高安全场景。不要把密钥提交到 GitHub 仓库；正式发布建议改用 Keychain 或自己的后端代理。")) {
                    EmptyView()
                }
            }
            .navigationTitle("AI 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear {
                baseURL = vm.baseURL
                model = vm.model
                apiKey = vm.apiKey
            }
        }.navigationViewStyle(.stack)
    }
}
