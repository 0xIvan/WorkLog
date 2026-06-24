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
        case .reports:
            ReportsView()
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
    private let formatter = TimeFormatting()
    private let suggestionValidator = ReviewAISuggestionValidator()

    var body: some View {
        List {
            reviewAISuggestionsSection

            if appState.reviewSegments.isEmpty {
                Text("No review items")
                    .foregroundStyle(.secondary)
            }

            ForEach(appState.reviewSegments) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.segment.appName)
                                .font(.headline)
                            Text(item.segment.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

    private var reviewAISuggestionsSection: some View {
        Section {
            HStack {
                Button {
                    appState.analyzeReview()
                } label: {
                    Label("Analyze Review", systemImage: "sparkles")
                }
                .disabled(appState.reviewSegments.isEmpty || appState.reviewAIAnalysisState == .analyzing)

                if appState.reviewAIAnalysisState == .analyzing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Text("\(appState.reviewSegments.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch appState.reviewAIAnalysisState {
            case .idle:
                EmptyView()
            case .analyzing:
                Text("Analyzing grouped Review activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed:
                if appState.reviewAISuggestions.isEmpty {
                    Text("No suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(appState.reviewAISuggestions) { suggestion in
                ReviewAISuggestionRow(
                    suggestion: suggestion,
                    validation: suggestionValidator.validationResult(for: suggestion),
                    formattedDuration: formatter.compactDuration(suggestion.affectedDuration)
                ) {
                    appState.applyReviewAISuggestion(suggestion)
                }
            }
        }
    }
}

private struct ReviewAISuggestionRow: View {
    let suggestion: ReviewAISuggestion
    let validation: ReviewAISuggestionValidationResult
    let formattedDuration: String
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Label(suggestion.kind.displayName, systemImage: symbolName)
                        .foregroundStyle(color)
                    Text("\(Int(round(suggestion.confidence * 100)))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(suggestion.affectedCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let condition = suggestion.proposedRuleCondition {
                    Text("\(condition.field.displayName) \(condition.operation.displayName) \(condition.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let sample = suggestion.samples.first {
                    Text(sample.windowTitle.isEmpty ? sample.appName : sample.windowTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if validation.canApply {
                Button("Apply", action: apply)
                    .buttonStyle(.borderedProminent)
            } else if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }

    private var validationMessage: String? {
        switch validation {
        case .applyAllowed:
            nil
        case .manualOnly(let message), .rejected(let message):
            message
        }
    }

    private var symbolName: String {
        switch suggestion.kind {
        case .work:
            "briefcase"
        case .personal:
            "person"
        case .ignored:
            "eye.slash"
        case .unsure:
            "questionmark.circle"
        }
    }

    private var color: Color {
        switch suggestion.kind {
        case .work:
            .blue
        case .personal:
            .green
        case .ignored:
            .gray
        case .unsure:
            .orange
        }
    }
}

private struct RecentActivityTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var kindFilter = ActivityKindFilter.all
    @State private var projectFilterID = ActivityProjectFilter.all
    @State private var sort = ActivitySort.newest

    private let formatter = TimeFormatting()

    private var displayedSegments: [ClassifiedSegment] {
        sortedSegments(filteredSegments(appState.activitySegments))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activityControls

            List {
                if displayedSegments.isEmpty {
                    Text(emptyActivityMessage)
                        .foregroundStyle(.secondary)
                }

                ForEach(displayedSegments) { item in
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

                        Text(formatter.compactDuration(item.segment.duration))
                            .font(.subheadline.monospacedDigit())

                        Menu {
                            Button {
                                appState.updateSegmentClassification(item, as: .work)
                            } label: {
                                Label("Work", systemImage: symbol(for: .work))
                            }

                            Button {
                                appState.updateSegmentClassification(item, as: .personal)
                            } label: {
                                Label("Personal", systemImage: symbol(for: .personal))
                            }

                            Button(role: .destructive) {
                                appState.updateSegmentClassification(item, as: .ignored)
                            } label: {
                                Label("Ignore", systemImage: symbol(for: .ignored))
                            }
                        } label: {
                            Label(categoryName(for: item), systemImage: symbol(for: item.classification.kind))
                                .lineLimit(1)
                        }
                        .menuStyle(.button)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyActivityMessage: String {
        appState.activitySegments.isEmpty ? "No activity for this day" : "No matching activity"
    }

    private var activityControls: some View {
        WrappingHStack(horizontalSpacing: 12, verticalSpacing: 8) {
            DatePicker(
                "Date",
                selection: Binding(
                    get: { appState.activityDate },
                    set: { appState.selectActivityDate($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .fixedSize()

            TextField("Search activity", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Picker("Category", selection: $kindFilter) {
                ForEach(ActivityKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(width: 170)

            Picker("Project", selection: $projectFilterID) {
                Text("All Projects").tag(ActivityProjectFilter.all)
                Text("No Project").tag(ActivityProjectFilter.none)
                ForEach(appState.projects) { project in
                    Text(project.name).tag(project.id.uuidString)
                }
            }
            .frame(width: 190)

            Picker("Sort", selection: $sort) {
                ForEach(ActivitySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .frame(width: 180)
        }
    }

    private func filteredSegments(_ segments: [ClassifiedSegment]) -> [ClassifiedSegment] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return segments.filter { item in
            if let kind = kindFilter.kind, item.classification.kind != kind {
                return false
            }

            if projectFilterID == ActivityProjectFilter.none, item.classification.projectID != nil {
                return false
            }

            if projectFilterID != ActivityProjectFilter.all, projectFilterID != ActivityProjectFilter.none {
                guard item.classification.projectID?.uuidString == projectFilterID else {
                    return false
                }
            }

            guard !trimmedSearchText.isEmpty else {
                return true
            }

            return [
                item.segment.appName,
                item.segment.windowTitle,
                item.segment.url ?? "",
                item.projectName ?? "",
                categoryName(for: item)
            ]
                .contains { value in
                    value.lowercased().contains(trimmedSearchText)
                }
        }
    }

    private func sortedSegments(_ segments: [ClassifiedSegment]) -> [ClassifiedSegment] {
        switch sort {
        case .newest:
            segments.sorted { $0.segment.startedAt > $1.segment.startedAt }
        case .oldest:
            segments.sorted { $0.segment.startedAt < $1.segment.startedAt }
        case .longest:
            segments.sorted { $0.segment.duration > $1.segment.duration }
        case .shortest:
            segments.sorted { $0.segment.duration < $1.segment.duration }
        case .app:
            segments.sorted {
                $0.segment.appName.localizedCaseInsensitiveCompare($1.segment.appName) == .orderedAscending
            }
        case .category:
            segments.sorted {
                categoryName(for: $0).localizedCaseInsensitiveCompare(categoryName(for: $1)) == .orderedAscending
            }
        }
    }

    private func categoryName(for item: ClassifiedSegment) -> String {
        guard let categoryName = item.categoryName, !categoryName.isEmpty else {
            return item.classification.kind.displayName
        }

        return categoryName
    }

    private func symbol(for kind: ActivityKind) -> String {
        switch kind {
        case .work:
            "briefcase"
        case .personal:
            "person"
        case .review:
            "questionmark.circle"
        case .ignored:
            "eye.slash"
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

private enum ActivityKindFilter: String, CaseIterable, Identifiable {
    case all
    case work
    case personal
    case review

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All Categories"
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .review:
            "Needs Review"
        }
    }

    var kind: ActivityKind? {
        switch self {
        case .all:
            nil
        case .work:
            .work
        case .personal:
            .personal
        case .review:
            .review
        }
    }
}

private enum ActivityProjectFilter {
    static let all = "all"
    static let none = "none"
}

private enum ActivitySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case longest
    case shortest
    case app
    case category

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .newest:
            "Newest First"
        case .oldest:
            "Oldest First"
        case .longest:
            "Longest First"
        case .shortest:
            "Shortest First"
        case .app:
            "App A-Z"
        case .category:
            "Category A-Z"
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

struct BucketListView: View {
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

struct SectionPanel<Content: View>: View {
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
