import Charts
import SwiftUI
import WorklogCore

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(WorklogSection.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            selectedSectionView
                .padding()
                .navigationTitle(appState.selectedSection.title)
        }
        .background(WindowLifecycleView(id: "dashboard"))
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewTab()
        case .review:
            ReviewTab()
        case .activity:
            RecentActivityTab()
        case .rules:
            RulesSettingsView()
        case .projects:
            ProjectsSettingsView()
        case .categories:
            CategoriesSettingsView()
        case .privacy:
            PrivacySettingsView()
        }
    }
}
private struct OverviewTab: View {
    @EnvironmentObject private var appState: AppState
    private let formatter = TimeFormatting()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    MetricView(title: "Work", value: formatter.compactDuration(appState.todaySummary.workSeconds), color: .blue)
                    MetricView(title: "Personal", value: formatter.compactDuration(appState.todaySummary.personalSeconds), color: .green)
                    MetricView(title: "Review", value: formatter.compactDuration(appState.todaySummary.reviewSeconds), color: .orange)
                }

                SectionPanel(title: "This Week") {
                    WeeklyChartView(days: appState.weekSummary)
                        .frame(height: 260)
                }

                HStack(alignment: .top, spacing: 16) {
                    SectionPanel(title: "Top Apps") {
                        BucketListView(buckets: appState.todaySummary.topApps)
                    }

                    SectionPanel(title: "Projects") {
                        BucketListView(buckets: appState.todaySummary.topProjects)
                    }
                }
            }
        }
    }
}

private struct ReviewTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            if appState.reviewSegments.isEmpty {
                Text("No review items today")
                    .foregroundStyle(.secondary)
            }

            ForEach(appState.reviewSegments) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.segment.appName)
                                .font(.headline)
                            Text(item.segment.windowTitle.isEmpty ? "Untitled" : item.segment.windowTitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let url = item.segment.url {
                                Text(url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text(TimeFormatting().compactDuration(item.segment.duration))
                            .font(.subheadline.monospacedDigit())
                    }

                    HStack {
                        Button {
                            appState.classifySegment(item, as: .work)
                        } label: {
                            Label("Work", systemImage: "briefcase")
                        }

                        Button {
                            appState.classifySegment(item, as: .personal)
                        } label: {
                            Label("Personal", systemImage: "person")
                        }

                        Button(role: .destructive) {
                            appState.classifySegment(item, as: .ignored)
                        } label: {
                            Label("Ignore", systemImage: "eye.slash")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct RecentActivityTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(appState.recentSegments) { item in
            HStack(spacing: 12) {
                Circle()
                    .fill(color(for: item.classification.kind))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.segment.appName)
                            .font(.headline)
                        if let projectName = item.projectName {
                            Text(projectName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.segment.windowTitle.isEmpty ? item.classification.kind.displayName : item.segment.windowTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(TimeFormatting().compactDuration(item.segment.duration))
                    .font(.subheadline.monospacedDigit())
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .work:
            .blue
        case .personal:
            .green
        case .review:
            .orange
        case .ignored:
            .gray
        }
    }
}

private struct WeeklyChartView: View {
    var days: [WeekDaySummary]

    @State private var selectedDayID: Date?
    @State private var tooltipX: CGFloat?

    private let tooltipWidth: CGFloat = 166

    private var selectedDay: WeekDaySummary? {
        guard let selectedDayID else {
            return nil
        }

        return days.first { $0.id == selectedDayID }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Hours", day.workSeconds / 3_600)
                )
                .foregroundStyle(by: .value("Type", "Work"))

                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Hours", day.personalSeconds / 3_600)
                )
                .foregroundStyle(by: .value("Type", "Personal"))

                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Hours", day.reviewSeconds / 3_600)
                )
                .foregroundStyle(by: .value("Type", "Review"))
            }

            if let selectedDay {
                RuleMark(x: .value("Selected Day", selectedDay.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartForegroundStyleScale([
            "Work": .blue,
            "Personal": .green,
            "Review": .orange
        ])
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateSelection(at: location, proxy: proxy, geometry: geometry)
                            case .ended:
                                clearSelection()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )

                    if let selectedDay, let tooltipX, let plotFrame = proxy.plotFrame {
                        let plotAreaFrame = geometry[plotFrame]

                        WeeklyChartTooltip(day: selectedDay)
                            .frame(width: tooltipWidth)
                            .offset(
                                x: clampedTooltipX(tooltipX, in: geometry),
                                y: plotAreaFrame.minY + 8
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func clearSelection() {
        selectedDayID = nil
        tooltipX = nil
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            clearSelection()
            return
        }

        let plotAreaFrame = geometry[plotFrame]
        let plotX = location.x - plotAreaFrame.origin.x

        guard plotX >= 0, plotX <= plotAreaFrame.width else {
            clearSelection()
            return
        }

        guard let selectedDate = proxy.value(atX: plotX, as: Date.self) else {
            clearSelection()
            return
        }

        selectedDayID = days.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }?.id
        tooltipX = min(max(location.x, plotAreaFrame.minX), plotAreaFrame.maxX)
    }

    private func clampedTooltipX(_ x: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        min(max(x - (tooltipWidth / 2), 0), max(0, geometry.size.width - tooltipWidth))
    }
}

private struct WeeklyChartTooltip: View {
    var day: WeekDaySummary

    private let formatter = TimeFormatting()

    private var totalSeconds: TimeInterval {
        day.workSeconds + day.personalSeconds + day.reviewSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.caption.weight(.semibold))

            Divider()

            tooltipRow("Work", seconds: day.workSeconds, color: .blue)
            tooltipRow("Personal", seconds: day.personalSeconds, color: .green)
            tooltipRow("Review", seconds: day.reviewSeconds, color: .orange)
            tooltipRow("Total", seconds: totalSeconds, color: .primary)
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private func tooltipRow(_ label: String, seconds: TimeInterval, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
            Spacer()
            Text(formatter.compactDuration(seconds))
                .monospacedDigit()
        }
    }
}

private struct BucketListView: View {
    var buckets: [TimeBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if buckets.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(buckets) { bucket in
                HStack {
                    Text(bucket.name)
                        .lineLimit(1)
                    Spacer()
                    Text(TimeFormatting().compactDuration(bucket.seconds))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MetricView: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SectionPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
