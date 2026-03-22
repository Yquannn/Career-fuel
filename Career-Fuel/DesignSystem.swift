import SwiftUI
import UIKit

enum AppPalette {
    static let primary = Color(hex: 0x1D4ED8)
    static let accent = Color(hex: 0xF59E0B)
    static let success = Color(hex: 0x10B981)
    static let danger = Color(hex: 0xEF4444)

    static let background = Color.dynamic(light: 0xF9FAFB, dark: 0x0B0F1A)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x111827)
    static let surfaceSecondary = Color.dynamic(light: 0xF3F4F6, dark: 0x171E2C)
    static let textPrimary = Color.dynamic(light: 0x111827, dark: 0xF3F4F6)
    static let textSecondary = Color.dynamic(light: 0x6B7280, dark: 0x9CA3AF)
    static let border = Color.dynamic(light: 0xE5E7EB, dark: 0x253041)
    static let ringTrack = Color.dynamic(light: 0xD7DCE5, dark: 0x263246)
    static let shadow = Color.dynamic(light: 0x0F172A, dark: 0x020617).opacity(0.16)
}

extension StatusTone {
    var color: Color {
        switch self {
        case .info:
            AppPalette.primary
        case .success:
            AppPalette.success
        case .warning:
            AppPalette.accent
        case .danger:
            AppPalette.danger
        }
    }

    var fill: Color {
        color.opacity(0.14)
    }

    var border: Color {
        color.opacity(0.22)
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppPalette.background, AppPalette.background],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(AppPalette.primary.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 30)
                .offset(x: -90, y: -80)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AppPalette.accent.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 28)
                .offset(x: 90, y: -70)
        }
        .ignoresSafeArea()
    }
}

struct SurfaceCard<Content: View>: View {
    var spotlight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppPalette.surface)
                    .overlay {
                        if spotlight {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AppPalette.primary.opacity(0.10),
                                            AppPalette.surface,
                                            AppPalette.accent.opacity(0.07),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppPalette.border, lineWidth: 1)
                    )
                    .shadow(color: AppPalette.shadow, radius: 26, x: 0, y: 14)
            }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StatusBadge: View {
    let label: String
    let tone: StatusTone

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tone.border, lineWidth: 1)
            )
    }
}

struct InfoChip: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppPalette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(AppPalette.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            )
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let tone: StatusTone
    let symbol: String
    let footnote: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tone.color)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(tone.fill)
                        )

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Text(value)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.18), value: value)

                Text(footnote)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 172, alignment: .topLeading)
        }
    }
}

struct MiniStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.18), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

struct ActivityPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(AppPalette.primary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(AppPalette.surfaceSecondary)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

struct LoadingStateCard: View {
    let title: String
    let message: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                ActivityPill(title: title)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 148, alignment: .topLeading)
        }
    }
}

struct RunwayGauge: View {
    let daysLeft: Int
    let tone: StatusTone

    private var progress: CGFloat {
        max(0.12, min(CGFloat(daysLeft) / 45, 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppPalette.ringTrack, style: StrokeStyle(lineWidth: 18, lineCap: .round))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [tone.color.opacity(0.35), tone.color, tone.color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: progress)

            Circle()
                .fill(AppPalette.surface)
                .padding(26)
                .overlay(
                    Circle()
                        .stroke(AppPalette.border, lineWidth: 1)
                        .padding(26)
                )

            VStack(spacing: 4) {
                Text("\(daysLeft)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(tone.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("days left")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
            }
        }
        .padding(6)
    }
}

struct SmallChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppPalette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(AppPalette.surfaceSecondary)
            )
    }
}

enum AppFormatters {
    static let philippineCurrency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_PH")
        formatter.currencyCode = "PHP"
        formatter.currencySymbol = "PHP "
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static let decimalCompact: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_PH")
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

extension Double {
    var currencyString: String {
        AppFormatters.philippineCurrency.string(from: NSNumber(value: self)) ?? "PHP 0"
    }

    var compactCurrencyString: String {
        guard abs(self) >= 1_000 else { return currencyString }

        let compact = AppFormatters.decimalCompact.string(from: NSNumber(value: self / 1_000)) ?? "0"
        return "PHP \(compact)K"
    }
}

extension Color {
    static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }

    init(hex: UInt, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }
}

private extension UIColor {
    convenience init(hex: UInt, alpha: Double = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
