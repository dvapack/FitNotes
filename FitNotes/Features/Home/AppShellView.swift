import SwiftUI

struct AppShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }

            NavigationStack {
                ImportView()
            }
            .tabItem {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
    }
}

#Preview {
    AppShellView()
}
