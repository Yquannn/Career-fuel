import SwiftUI

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppPalette.background,
                    AppPalette.primary.opacity(0.22),
                    AppPalette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppPalette.surface)
                        .frame(width: 108, height: 108)
                        .shadow(color: AppPalette.shadow, radius: 24, x: 0, y: 16)

                    Image("LaunchIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 6) {
                    Text("CareerFuel")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text("Loading your control panel…")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }

                ProgressView()
                    .tint(AppPalette.primary)
                    .scaleEffect(1.15)
                    .padding(.top, 6)
            }
            .padding(28)
        }
    }
}
