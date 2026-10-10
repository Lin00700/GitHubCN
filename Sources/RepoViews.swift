import SwiftUI

struct RepoListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(["stars", "forks", "updated"], id: \.self) { sortOption in
                                    Button(action: {
                                        appState.selectedSort = sortOption
                                        Task { await appState.searchRepositories() }
                                    }) {
                                        Text(sortOption.uppercased())
                                            .font(.caption.bold())
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(appState.selectedSort == sortOption ? Color.purple : Color(.secondarySystemBackground))
                                            .foregroundColor(appState.selectedSort == sortOption ? .white : .primary)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)
                        
                        ForEach(appState.repositories) { repo in
                            NavigationLink(destination: RepoDetailView(repo: repo)) {
                                VCard(repo: repo, appState: appState)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .searchable(text: $appState.searchText, prompt: "探索百万开源仓库...")
            .onChange(of: appState.searchText) { _, _ in
                Task { await appState.searchRepositories() }
            }
            .navigationTitle("开源星河")
            .task {
                if appState.repositories.isEmpty {
                    await appState.searchRepositories()
                }
            }
        }
    }
}

struct VCard: View {
    let repo: Repository
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                AsyncImage(url: URL(string: repo.owner?.avatarURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.purple.opacity(0.3)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.purple.opacity(0.5), lineWidth: 1))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.fullName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(repo.owner?.login ?? "GitHub")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    appState.toggleFavorite(for: repo.id)
                }) {
                    Image(systemName: appState.favorites.contains(repo.id) ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.title3)
                }
            }
            
            if let desc = repo.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                if let lang = repo.language {
                    Text(lang)
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(8)
                }
                
                Spacer()
                
                HStack(spacing: 14) {
                    Label("\(repo.stargazersCount)", systemImage: "star.fill")
                        .foregroundColor(.yellow)
                    Label("\(repo.forksCount)", systemImage: "tuningfork")
                        .foregroundColor(.cyan)
                }
                .font(.caption.bold())
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct RepoDetailView: View {
    let repo: Repository
    var body: some View {
        MarkdownRenderer(content: """
        # \(repo.fullName)
        
        > **项目描述**: \(repo.description ?? "暂无描述")
        
        - **主要语言**: \(repo.language ?? "通用")
        - **获得星标**: ⭐ \(repo.stargazersCount)
        - **代码分支**: 🔀 \(repo.forksCount)
        
        ### 快速开始 (Quick Start)
        [\(repo.htmlURL)](\(repo.htmlURL))
        """)
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
