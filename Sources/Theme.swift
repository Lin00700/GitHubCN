import SwiftUI
import UIKit

/// 深色科技风 · 青紫霓虹
enum Theme {
    static let bg = Color(red: 0.027, green: 0.031, blue: 0.075)
    static let card = Color(red: 0.07, green: 0.075, blue: 0.16).opacity(0.88)
    static let cyan = Color(red: 0.0, green: 0.94, blue: 1.0)
    static let purple = Color(red: 0.66, green: 0.33, blue: 0.97)
    static let pink = Color(red: 1.0, green: 0.25, blue: 0.70)
    static let textDim = Color.white.opacity(0.6)

    static let gradient = LinearGradient(
        colors: [cyan, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func setupAppearance() {
        let dark = UIColor(red: 0.03, green: 0.035, blue: 0.08, alpha: 1)

        let navStd = UINavigationBarAppearance()
        navStd.configureWithOpaqueBackground()
        navStd.backgroundColor = dark.withAlphaComponent(0.96)
        navStd.titleTextAttributes = [.foregroundColor: UIColor.white]
        navStd.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        let navEdge = UINavigationBarAppearance()
        navEdge.configureWithTransparentBackground()
        navEdge.titleTextAttributes = [.foregroundColor: UIColor.white]
        navEdge.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = navStd
        UINavigationBar.appearance().compactAppearance = navStd
        UINavigationBar.appearance().scrollEdgeAppearance = navEdge

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = dark
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = UIColor(white: 1, alpha: 0.05)
        UITableView.appearance().separatorColor = UIColor(cyan).withAlphaComponent(0.15)
        UITextView.appearance().backgroundColor = .clear

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(purple)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(white: 1, alpha: 0.7)], for: .normal)
        UISwitch.appearance().onTintColor = UIColor(purple)
    }
}

struct NeonBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.cyan.opacity(0.18), Color.clear],
                           center: .topLeading, startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Theme.purple.opacity(0.24), Color.clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 440)
        }
    }
}

struct NeonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.gradient.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Theme.purple.opacity(0.5), radius: 10)
    }
}

extension View {
    func neonBackground() -> some View {
        self.background(NeonBackground().ignoresSafeArea())
    }

    func neonCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.cyan.opacity(0.55), Theme.purple.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Theme.cyan.opacity(0.12), radius: 8)
    }

    func neonField() -> some View {
        self
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.cyan.opacity(0.35), lineWidth: 1))
    }
}
