import SwiftUI

struct IssueListView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            List(appState.issues) { issue in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("#\(issue.number)")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                        Text(issue.state.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(issue.state == "open" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                            .foregroundColor(issue.state == "open" ? .green : .red)
                            .cornerRadius(4)
                        Spacer()
                    }
                    Text(issue.title)
                        .font(.headline)
                    if let body = issue.body {
                        Text(body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("全网动态")
        }
    }
}
