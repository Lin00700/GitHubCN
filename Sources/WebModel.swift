import SwiftUI
import WebKit

/// 避免 WKUserContentController 强引用造成循环引用
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var translating = false
    @Published var uiChinese: Bool

    private var observers: [NSKeyValueObservation] = []
    private let home = URL(string: "https://github.com")!

    override init() {
        let saved = UserDefaults.standard.object(forKey: "uiChinese") as? Bool ?? true
        uiChinese = saved

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let ucc = WKUserContentController()
        if let url = Bundle.main.url(forResource: "zh", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        config.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()

        ucc.add(WeakHandler(self), name: "translate")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observers = [
            webView.observe(\.canGoBack) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoForward = w.canGoForward } },
            webView.observe(\.estimatedProgress) { [weak self] w, _ in DispatchQueue.main.async { self?.progress = w.estimatedProgress } },
            webView.observe(\.isLoading) { [weak self] w, _ in DispatchQueue.main.async { self?.isLoading = w.isLoading } }
        ]
        webView.load(URLRequest(url: home))
    }

    // MARK: 操作
    func goHome() { webView.load(URLRequest(url: home)) }
    func reload() { webView.reload() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func openInSafari() {
        if let url = webView.url { UIApplication.shared.open(url) }
    }

    func toggleUIChinese() {
        uiChinese.toggle()
        UserDefaults.standard.set(uiChinese, forKey: "uiChinese")
        let v = uiChinese ? "1" : "0"
        webView.evaluateJavaScript("localStorage.setItem('gh_zh','\(v)')") { [weak self] _, _ in
            self?.webView.reload()
        }
    }

    func toggleTranslatePage() {
        webView.evaluateJavaScript("window.__ghToggleTranslate && window.__ghToggleTranslate()") { [weak self] result, _ in
            if let on = result as? Bool { DispatchQueue.main.async { self?.translating = on } }
        }
    }

    func clearCache() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            self?.webView.reload()
        }
    }

    // MARK: 翻译桥接
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "translate",
              let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let texts = body["texts"] as? [String] else { return }
        Task { [weak self] in
            let result = await Translator.translate(texts)
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let json = String(data: data, encoding: .utf8) else { return }
            await MainActor.run {
                self?.webView.evaluateJavaScript("window.__ghApply(\(id), \(json))", completionHandler: nil)
            }
        }
    }

    // MARK: WKNavigationDelegate / UIDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        translating = false
    }

    // target=_blank 的链接在当前页面打开
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
