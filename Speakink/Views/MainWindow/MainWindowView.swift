import SwiftUI

enum SidebarTab: String, CaseIterable {
    case dashboard = "Dashboard"
    case history = "History"
    case transcribeAudio = "Transcribe Audio"
    case aiModels = "AI Models"
    case dictionary = "Dictionary"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: "chart.bar.fill"
        case .history: "clock.fill"
        case .transcribeAudio: "waveform.badge.plus"
        case .aiModels: "cpu.fill"
        case .dictionary: "text.book.closed.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainWindowView: View {
    @State private var selectedTab: SidebarTab = .dashboard

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // Brand header
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text("Speakink")
                        .font(.headline)
                        .foregroundStyle(Theme.amber)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView()
            case .history:
                HistoryView()
            case .transcribeAudio:
                TranscribeAudioView()
            case .aiModels:
                AIModelsView()
            case .dictionary:
                DictionaryView()
            case .settings:
                SettingsView()
            }
        }
        .background(Theme.bgDark)
    }
}
