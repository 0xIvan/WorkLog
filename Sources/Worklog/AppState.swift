import AppKit
import Combine
import Foundation
import SwiftUI
import WorklogCore

@MainActor
final class AppState: ObservableObject {
    @Published var currentSnapshot: ActivitySnapshot?
    @Published var currentClassification: ClassificationResult?
    @Published var currentStateLabel = "Starting"
    @Published var todaySummary = DaySummary.empty(on: Date())
    @Published var weekSummary: [WeekDaySummary] = []
    @Published var reviewSegments: [ClassifiedSegment] = []
    @Published var recentSegments: [ClassifiedSegment] = []
    @Published var activityDate = Date()
    @Published var activitySegments: [ClassifiedSegment] = []
    @Published var rules: [Rule] = []
    @Published var categories: [WorklogCore.Category] = []
    @Published var projects: [Project] = []
    @Published var errorMessage: String?
    @Published var accessibilityTrusted = false
    @Published var selectedSection: WorklogSection = .overview

    private let reader = ActiveWindowReader()
    private let idleMonitor = IdleMonitor()
    private let classifier = ActivityClassifier()
    private let rememberedRuleFactory = RememberedRuleFactory()
    private let formatter = TimeFormatting()
    private var store: WorklogStore?
    private var timer: Timer?
    private var activeDraft: ActiveDraft?
    private var visibleAppWindows: Set<String> = []
    private var dashboardWindow: NSWindow?
    private let pollInterval: TimeInterval = 5
    private let minimumSegmentDuration: TimeInterval = 3
    private let idleThreshold: TimeInterval = 300

    init() {
        do {
            let databaseURL = try WorklogStore.defaultDatabaseURL()
            store = try WorklogStore(databaseURL: databaseURL)
            if !reader.accessibilityIsTrusted() {
                reader.requestAccessibilityPermission()
            }
            try refresh()
            startTracking()
            DispatchQueue.main.async { [weak self] in
                self?.hideFromDockIfNoWindowsAreOpen()
            }
        } catch {
            errorMessage = error.localizedDescription
            currentStateLabel = "Setup failed"
        }
    }

    var menuBarTitle: String {
        let workDuration = formatter.menuBarWorkDuration(todaySummary.workSeconds)
        let totalDuration = formatter.menuBarWorkDuration(todayTrackedSeconds)

        return "\(workDuration) | \(totalDuration)"
    }

    var todayTrackedSeconds: TimeInterval {
        todaySummary.workSeconds + todaySummary.personalSeconds + todaySummary.reviewSeconds
    }

    func prepareToOpenAppWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDashboardWindow() {
        openWorklogWindow(section: .overview)
    }

    func openSettingsWindow() {
        openWorklogWindow(section: .rules)
    }

    private func openWorklogWindow(section: WorklogSection) {
        selectedSection = section
        prepareToOpenAppWindow()

        if dashboardWindow == nil {
            let controller = NSHostingController(
                rootView: DashboardView()
                    .environmentObject(self)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Worklog"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1_020, height: 720))
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }

        appWindowDidAppear(id: "dashboard")
        dashboardWindow?.makeKeyAndOrderFront(nil)
        reload()
    }

    func appWindowDidAppear(id: String) {
        visibleAppWindows.insert(id)
        prepareToOpenAppWindow()
    }

    func appWindowDidDisappear(id: String) {
        visibleAppWindows.remove(id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else {
                return
            }

            self.hideFromDockIfNoWindowsAreOpen()
        }
    }

    func requestAccessibilityPermission() {
        reader.requestAccessibilityPermission()
        accessibilityTrusted = reader.accessibilityIsTrusted()
    }

    func refresh() throws {
        guard let store else {
            return
        }

        rules = try store.loadRules()
        categories = try store.loadCategories()
        projects = try store.loadProjects()
        todaySummary = try store.daySummary(for: Date())
        weekSummary = try store.weekSummary(containing: Date())
        reviewSegments = try store.reviewSegments()
        activitySegments = try store.activitySegments(for: activityDate)
        recentSegments = try store.recentSegments(limit: 20)
        accessibilityTrusted = reader.accessibilityIsTrusted()
    }

    func reload() {
        do {
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveRule(_ rule: Rule, reclassify scope: ReclassificationScope?) {
        do {
            try store?.saveRule(rule)
            if let scope {
                try store?.reclassify(scope: scope)
            }
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRule(id: UUID, reclassify scope: ReclassificationScope?) {
        do {
            try store?.deleteRule(id: id)
            if let scope {
                try store?.reclassify(scope: scope)
            }
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveCategory(_ category: WorklogCore.Category) -> Bool {
        do {
            try store?.saveCategory(category)
            try refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveProject(_ project: Project) {
        do {
            try store?.saveProject(project)
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectActivityDate(_ date: Date) {
        activityDate = date
        reload()
    }

    func loadReportPair(
        for periodKind: ReportPeriodKind,
        containing date: Date
    ) -> (current: ReportSummary, previous: ReportSummary)? {
        do {
            guard let store else {
                return nil
            }

            let current = try store.reportSummary(for: periodKind, containing: date)
            let previous = try store.previousReportSummary(for: periodKind, containing: date)
            errorMessage = nil

            return (current, previous)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func classifySegment(_ segment: ClassifiedSegment, as kind: ActivityKind) {
        let categoryID = categories.first { $0.kind == kind }?.id

        do {
            if let rule = rememberedRuleFactory.rule(from: segment, kind: kind, categoryID: categoryID) {
                if let ruleID = try store?.saveRememberedRule(rule) {
                    try store?.reclassify(ruleID: ruleID, scope: .allHistory)
                }
            }

            if kind == .ignored {
                try store?.ignoreSegment(id: segment.id)
            } else {
                try store?.overrideSegment(
                    id: segment.id,
                    kind: kind,
                    projectID: segment.classification.projectID,
                    categoryID: categoryID
                )
            }

            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSegmentClassification(_ segment: ClassifiedSegment, as kind: ActivityKind) {
        guard kind != .review else {
            return
        }

        let categoryID = categories.first { $0.kind == kind }?.id

        do {
            if kind == .ignored {
                try store?.ignoreSegment(id: segment.id)
            } else {
                try store?.overrideSegment(
                    id: segment.id,
                    kind: kind,
                    projectID: segment.classification.projectID,
                    categoryID: categoryID
                )
            }

            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hideFromDockIfNoWindowsAreOpen() {
        guard visibleAppWindows.isEmpty else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
    }

    private func startTracking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        tick()
    }

    private func tick() {
        accessibilityTrusted = reader.accessibilityIsTrusted()

        let now = Date()
        let idleSeconds = idleMonitor.secondsSinceLastInput()
        if idleSeconds >= idleThreshold {
            finalizeActiveDraft(endingAt: now.addingTimeInterval(-idleSeconds))
            activeDraft = nil
            currentSnapshot = nil
            currentClassification = nil
            currentStateLabel = "Idle"
            return
        }

        guard let snapshot = reader.currentSnapshot() else {
            finalizeActiveDraft(endingAt: now)
            activeDraft = nil
            currentSnapshot = nil
            currentClassification = nil
            currentStateLabel = "No active window"
            return
        }

        let result = classifier.classify(snapshot: snapshot, rules: rules)
        currentClassification = result

        if result.kind == .ignored {
            finalizeActiveDraft(endingAt: now)
            activeDraft = nil
            currentSnapshot = nil
            currentStateLabel = "Ignored"
            return
        }

        currentSnapshot = snapshot
        currentStateLabel = result.kind.displayName

        guard let activeDraft else {
            self.activeDraft = ActiveDraft(snapshot: snapshot, startedAt: now)
            return
        }

        if activeDraft.snapshot.normalizedSignature != snapshot.normalizedSignature {
            finalizeActiveDraft(endingAt: now)
            self.activeDraft = ActiveDraft(snapshot: snapshot, startedAt: now)
        }
    }

    private func finalizeActiveDraft(endingAt endedAt: Date) {
        guard let activeDraft else {
            return
        }

        let segment = ActivitySegment(
            startedAt: activeDraft.startedAt,
            endedAt: endedAt,
            snapshot: activeDraft.snapshot
        )

        guard segment.duration >= minimumSegmentDuration else {
            return
        }

        let result = classifier.classify(snapshot: activeDraft.snapshot, rules: rules)
        let classification = SegmentClassification(
            segmentID: segment.id,
            kind: result.kind,
            categoryID: result.categoryID,
            projectID: result.projectID,
            ruleID: result.ruleID,
            isManual: false
        )

        do {
            try store?.save(segment: segment, classification: classification)
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActiveDraft {
    var snapshot: ActivitySnapshot
    var startedAt: Date
}
