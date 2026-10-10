import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
            }
            WebView(webView: model.webView)
            Divider()
            HStack {
                bar("chevron.left", disabled: !model.canGoBack) { model.goBack() }
                Spacer()
                bar("chevron.right", disabled: !model.canGoForward) { model.goForward() }
                Spacer()
                bar("house") { model.goHome() }
                Spacer()
                bar("arrow.clockwise") { model.reload() }
                Spacer()
                bar("character.bubble", highlighted: model.translating) { model.toggleTranslatePage() }
                Spacer()
                Menu {
                    Button(model.uiChinese ? "关闭界面中文化" : "开启界面中文化") { model.toggleUIChinese() }
                    Button("在 Safari 中打开") { model.openInSafari() }
                    Button("清除缓存并刷新", role: .destructive) { model.clearCache() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    private func bar(_ name: String, disabled: Bool = false, highlighted: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.title3)
                .foregroundColor(highlighted ? .accentColor : nil)
        }
        .disabled(disabled)
    }
}
