import AppKit
import SwiftUI
import WorklogCore

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState

    var openSettings: () -> Void = {}

    private let formatter = TimeFormatting()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Work today \(formatter.compactDuration(appState.todaySummary.workSeconds))")
                    .font(.title3.weight(.semibold))
                Text("Total today \(formatter.compactDuration(appState.todayTrackedSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(appState.currentStateLabel)
                    .foregroundStyle(kindColor(appState.currentClassification?.kind))
            }

            if let snapshot = appState.currentSnapshot {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.appName)
                        .font(.subheadline.weight(.semibold))
                    if !snapshot.windowTitle.isEmpty {
                        Text(snapshot.windowTitle)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    if let url = snapshot.url, !url.isEmpty {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            VStack(spacing: 8) {
                Button {
                    closeMenu()
                    DispatchQueue.main.async {
                        openSettings()
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Worklog", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }

            if let errorMessage = appState.errorMessage {
                Divider()
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func closeMenu() {
        NSApp.keyWindow?.close()
    }

    private func kindColor(_ kind: ActivityKind?) -> Color {
        switch kind {
        case .work:
            .blue
        case .personal:
            .green
        case .review:
            .orange
        case .ignored:
            .secondary
        case nil:
            .secondary
        }
    }
}
