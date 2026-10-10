import Foundation

/// 翻译服务。默认使用 Google 的 gtx 接口（大陆需要代理才能访问）。
/// 想换成别的服务，只改 translateOne 即可。
enum Translator {
    static let targetLang = "zh-CN"

    static func translate(_ texts: [String]) async -> [String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for (i, t) in texts.enumerated() {
                group.addTask { (i, await translateOne(t)) }
            }
            var out = texts
            for await (i, s) in group { out[i] = s }
            return out
        }
    }

    private static func translateOne(_ text: String) async -> String {
        let trimmed = String(text.prefix(1500))
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLang),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = comps.url else { return text }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let segs = root.first as? [Any] else { return text }
            let result = segs.compactMap { ($0 as? [Any])?.first as? String }.joined()
            return result.isEmpty ? text : result
        } catch {
            return text
        }
    }
}
