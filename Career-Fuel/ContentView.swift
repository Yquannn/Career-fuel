import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            AppTabScreen {
                DashboardView()
            }
            .tag(AppTab.dashboard)
            .tabItem {
                Label("Dashboard", systemImage: "rectangle.grid.2x2.fill")
            }

            AppTabScreen {
                KanbanBoardView()
            }
            .tag(AppTab.applications)
            .tabItem {
                Label("Applications", systemImage: "rectangle.split.3x1.fill")
            }

            AppTabScreen {
                ExpenseView()
            }
            .tag(AppTab.expenses)
            .tabItem {
                Label("Expenses", systemImage: "creditcard.fill")
            }

            AppTabScreen {
                AnalyticsView()
            }
            .tag(AppTab.analytics)
            .tabItem {
                Label("Analytics", systemImage: "chart.xyaxis.line")
            }

            AppTabScreen {
                SettingsView()
            }
            .tag(AppTab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(AppPalette.primary)
    }
}

private struct AppTabScreen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private enum AppTab: String, Hashable {
    case dashboard
    case applications
    case expenses
    case analytics
    case settings
}
