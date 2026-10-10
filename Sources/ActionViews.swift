import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 140, height: 140)
                        .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 10)
                    
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .pink, .cyan], startPoint: .top, endPoint: .bottom))
                }
                
                VStack(spacing: 12) {
                    Text("DEV NEXUS 2026")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("连接全球开发者，体验极致流畅的开源大盘与 AI 工作台")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                Button(action: {
                    Task { await appState.signInWithGoogle() }
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundColor(.yellow)
                        
                        Text("使用 Google 账号尊享登录")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
                    )
                    .cornerRadius(20)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 60)
            }
            
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
    }
}

struct AIAssistantView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputPrompt: String = ""
    
    let availableModels = ["OpenAI GPT-4o", "Claude 3.5 Sonnet", "Google Gemini 1.5 Pro", "自定义 AI (Custom API)"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(availableModels, id: \.self) { model in
                                Button(action: {
                                    appState.selectedAIModel = model
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(appState.selectedAIModel == model ? Color.purple : Color.gray)
                                            .frame(width: 8, height: 8)
                                        Text(model)
                                            .font(.caption.bold())
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(appState.selectedAIModel == model ? Color.purple.opacity(0.2) : Color(.secondarySystemBackground))
                                    .foregroundColor(appState.selectedAIModel == model ? .purple : .primary)
                                    .cornerRadius(16)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(.ultraThinMaterial)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(appState.aiChatHistory) { message in
                                    HStack {
                                        if message.role == "user" { Spacer() }
                                        
                                        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                                            Text(message.role == "user" ? "您" : appState.selectedAIModel)
                                                .font(.caption2.bold())
                                                .foregroundColor(.secondary)
                                            
                                            Text(message.content)
                                                .font(.body)
                                                .padding(14)
                                                .background(message.role == "user" ? Color.purple : Color(.secondarySystemBackground))
                                                .foregroundColor(message.role == "user" ? .white : .primary)
                                                .cornerRadius(18)
                                        }
                                        
                                        if message.role == "assistant" { Spacer() }
                                    }
                                    .id(message.id)
                                }
                                
                                if appState.isAILoading {
                                    HStack {
                                        ProgressView()
                                            .padding()
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(12)
                                        Spacer()
                                    }
                                }
                            }
                            .padding()
                        }
                        .onChange(of: appState.aiChatHistory.count) { _, _ in
                            if let last = appState.aiChatHistory.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        TextField("向 AI 询问架构、代码或重构方案...", text: $inputPrompt)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                        
                        Button(action: {
                            let textToSend = inputPrompt
                            inputPrompt = ""
                            Task { await appState.sendAIMessage(prompt: textToSend) }
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.purple)
                        }
                        .disabled(inputPrompt.isEmpty || appState.isAILoading)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("AI 智能大模型中心")
        }
    }
}
