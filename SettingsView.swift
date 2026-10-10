import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Google 账户") {
                    HStack(spacing: 16) {
                        AsyncImage(url: URL(string: appState.userAvatarURL ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill").font(.system(size: 50))
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.userName ?? "Google 开发者")
                                .font(.headline)
                            Text(appState.userEmail ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("自定义 AI 入口配置 (Custom API)") {
                    TextField("API Endpoint URL", text: $appState.customAPIEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("模型名称 (如 deepseek-chat)", text: $appState.customModelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    SecureField("API Key", text: $appState.customAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section("外观与偏好") {
                    Toggle("沉浸深色模式", isOn: $appState.isDarkMode)
                }
                
                Section {
                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Text("安全登出")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("个人与设置")
        }
    }
}
