import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        Group {
            if appState.isAuthenticated {
                TabView {
                    RepoListView()
                        .tabItem {
                            Label("探索大盘", systemImage: "sparkles.rectangle.stack.fill")
                        }
                    
                    AIAssistantView()
                        .tabItem {
                            Label("AI 助手", systemImage: "brain.head.profile")
                        }
                    
                    IssueListView()
                        .tabItem {
                            Label("动态看板", systemImage: "waveform.path.ecg")
                        }
                    
                    SettingsView()
                        .tabItem {
                            Label("个人中心", systemImage: "person.crop.circle.fill.badge.checkmark")
                        }
                }
                .accentColor(.purple)
            } else {
                LoginView()
            }
        }
        .environmentObject(appState)
        .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        .task {
            appState.checkExistingSession()
        }
    }
}
