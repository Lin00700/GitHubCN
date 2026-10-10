import SwiftUI

// MARK: - 轻量 Markdown 解析

enum MDKind: Equatable {
    case heading(Int)
    case paragraph
    case bullet(String)
    case quote
    case code
    case rule
}

struct MDBlock {
    var kind: MDKind
    var text: String
}

enum MD {
    /// 去掉图片、空链接、HTML 标签
    static func clean(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\[\s*\]\([^)]*\)"#, with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return r.trimmingCharacters(in: .whitespaces)
    }

    /// 翻译前把 [文字](链接) 变成 文字，避免链接被翻乱
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
    }

    static func parse(_ src: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var para: [String] = []
        var code: [String] = []
        var inCode = false

        func flush() {
            if !para.isEmpty {
                blocks.append(MDBlock(kind: .paragraph, text: para.joined(separator: " ")))
                para = []
            }
        }

        let lines = src.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let t0 = line.trimmingCharacters(in: .whitespaces)

            if t0.hasPrefix("```") || t0.hasPrefix("~~~") {
                if inCode {
                    blocks.append(MDBlock(kind: .code, text: code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    flush()
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            if t0.isEmpty {
                flush()
                continue
            }

            let t = clean(t0)
            if t.isEmpty { continue }

            if t.hasPrefix("#") {
                let level = t.prefix(while: { $0 == "#" }).count
                let rest = t.dropFirst(level)
                if level <= 6, rest.first == " " {
                    flush()
                    blocks.append(MDBlock(kind: .heading(level), text: rest.trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if t == "---" || t == "***" || t == "___" {
                flush()
                blocks.append(MDBlock(kind: .rule, text: ""))
                continue
            }
            if t.hasPrefix("|") {
                flush()
                let probe = t.replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if probe.isEmpty { continue }
                let cells = t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                blocks.append(MDBlock(kind: .code, text: cells.joined(separator: "  |  ")))
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                flush()
                blocks.append(MDBlock(kind: .bullet("•"), text: String(t.dropFirst(2))))
                continue
            }
            if let r = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flush()
                let marker = String(t[r]).trimmingCharacters(in: .whitespaces)
                blocks.append(MDBlock(kind: .bullet(marker), text: String(t[r.upperBound...])))
                continue
            }
            if t.hasPrefix(">") {
                flush()
                let q = String(t.drop(while: { $0 == ">" || $0 == " " }))
                blocks.append(MDBlock(kind: .quote, text: q))
                continue
            }
            para.append(t)
        }
        if inCode { blocks.append(MDBlock(kind: .code, text: code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// 翻译所有文本块（代码块和分隔线不翻）
    static func translate(_ blocks: [MDBlock]) async -> [MDBlock] {
        var out = blocks
        var idx: [Int] = []
        var texts: [String] = []
        for (i, b) in blocks.enumerated() {
            if b.kind == .code || b.kind == .rule { continue }
            let p = plain(b.text)
            if p.range(of: "[A-Za-z]{3,}", options: .regularExpression) == nil { continue }
            if p.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression) != nil { continue }
            idx.append(i)
            texts.append(p)
        }
        if texts.isEmpty { return out }
        let res = await Translator.translate(texts)
        for (k, i) in idx.enumerated() { out[i].text = res[k] }
        return out
    }
}

// MARK: - 渲染

struct MarkdownView: View {
    let blocks: [MDBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                blockView(b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: opts) {
            return Text(a)
        }
        return Text(s)
    }

    @ViewBuilder
    private func blockView(_ b: MDBlock) -> some View {
        switch b.kind {
        case .heading(let level):
            inline(b.text)
                .font(level <= 1 ? Font.title2.bold() : (level == 2 ? Font.title3.bold() : Font.headline))
                .padding(.top, 6)
        case .paragraph:
            inline(b.text)
        case .bullet(let marker):
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                inline(b.text)
            }
        case .quote:
            HStack(spacing: 8) {
                Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 3)
                inline(b.text).foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(b.text)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(8)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        case .rule:
            Divider()
        }
    }
}

/// 由父视图的开关（translate）控制是否显示译文
struct TranslatableMarkdown: View {
    let text: String
    let translate: Bool
    @State private var translated: [MDBlock]?
    @State private var failed = false

    var body: some View {
        let original = MD.parse(text)
        VStack(alignment: .leading, spacing: 6) {
            if translate && translated == nil && !failed {
                ProgressView()
            }
            if translate && failed {
                Text("翻译失败，请检查网络或代理").font(.caption).foregroundColor(.red)
            }
            MarkdownView(blocks: (translate ? translated : nil) ?? original)
        }
        .task(id: translate) {
            if translate && translated == nil {
                let t = await MD.translate(original)
                let changed = zip(original, t).contains { $0.text != $1.text }
                if changed {
                    translated = t
                } else {
                    failed = true
                }
            }
        }
    }
}

struct TranslateBar: View {
    @Binding var on: Bool
    var body: some View {
        HStack {
            Image(systemName: "character.bubble")
            Text("翻译为中文")
            Spacer()
            Toggle("", isOn: $on).labelsHidden()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
