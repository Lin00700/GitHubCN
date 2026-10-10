import SwiftUI

struct MarkdownRenderer: View {
    let content: String
    @State private var translatedText: String = ""
    @State private var isTranslating: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: {
                        Task {
                            isTranslating = true
                            translatedText = await Translator.shared.translate(text: content)
                            isTranslating = false
                        }
                    }) {
                        Label(isTranslating ? "翻译中..." : "一键AI翻译", systemImage: "globe")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                    Spacer()
                }
                
                Text(LocalizedStringKey(translatedText.isEmpty ? content : translatedText))
                    .font(.body)
                    .lineSpacing(6)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
