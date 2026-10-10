import Foundation

enum Translator {
    static let targetLang = "zh-CN"

    static func translate(_ texts: [String]) async -> [String] {
        var out = texts
        var start = 0
        while start < texts.count {
            let end = min(start + 6, texts.count)
            let pairs: [(Int, String)] = await withTaskGroup(of: (Int, String).self) { group in
                for i in start..<end {
                    let t = texts[i]
                    group.addTask { (i, await translateOne(t)) }
                }
                var r: [(Int, String)] = []
                for await p in group { r.append(p) }
                return r
            }
            for (i, s) in pairs { out[i] = s }
            start = end
        }
        return out
    }

    private static func translateOne(_ text: String) async -> String {
        let trimmed = String(text.prefix(3000))
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
