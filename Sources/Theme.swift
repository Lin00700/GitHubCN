import SwiftUI
import UIKit

/// 跟随系统的浅色 / 深色，使用语义色和系统字体，符合 Apple HIG。
enum Theme {
    static let accent = Color.accentColor
    static let cyan = Color.accentColor
    static let purple = Color.purple
    static let pink = Color.pink
    static let textDim = Color.secondary
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let gradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let open = Color.green
    static let closed = Color.purple
    static let merged = Color.purple
    static let danger = Color.red

    static func setupAppearance() {
        // 使用系统导航栏和列表外观，不强制深色、不改表格底色。
    }
}

struct NeonBackground: View {
    var body: some View { Color(uiColor: .systemGroupedBackground) }
}

struct NeonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func neonBackground() -> some View { self }

    func neonCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func neonField() -> some View {
        self
            .padding(10)
            .background(Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

func tapHaptic(_ kind: UINotificationFeedbackGenerator.FeedbackType = .success) {
    UINotificationFeedbackGenerator().notificationOccurred(kind)
}
