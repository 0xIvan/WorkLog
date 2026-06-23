import Foundation
import Testing
import WorklogCore

@Suite
struct WorklogStoreTests {
    @Test
    func reclassifyTodayUpdatesMatchingReviewSegments() throws {
        let store = try makeStore()
        let segmentA = segment(url: "https://clerk.com/docs")
        let segmentB = segment(url: "https://clerk.com/dashboard", offset: 600)

        try store.save(
            segment: segmentA,
            classification: SegmentClassification(
                segmentID: segmentA.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: segmentB,
            classification: SegmentClassification(
                segmentID: segmentB.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        try store.saveRule(
            Rule(
                name: "Remember clerk.com",
                priority: 150,
                enabled: true,
                isBuiltIn: false,
                action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
                conditions: [
                    RuleCondition(field: .host, operation: .equals, value: "clerk.com")
                ]
            )
        )
        try store.reclassify(scope: .today)

        let remainingReviewSegments = try store.reviewSegments(for: Date())

        #expect(remainingReviewSegments.isEmpty)
    }

    @Test
    func reclassifyRuleUpdatesMatchingHistoryOnly() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(url: "https://clerk.com/docs", startedAt: baseDate)
        let otherSegment = segment(url: "https://x.com/home", offset: 600, startedAt: baseDate)
        let rule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001")

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: otherSegment,
            classification: SegmentClassification(
                segmentID: otherSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .work)
        #expect(classifications[matchingSegment.id]?.ruleID == rule.id)
        #expect(classifications[otherSegment.id]?.kind == .review)
    }

    @Test
    func reclassifyRulePreservesHigherPriorityRulesForMatchingHistory() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(url: "https://clerk.com/docs", startedAt: baseDate)
        let higherPriorityRule = Rule(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            name: "Clerk is personal",
            priority: 100,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .equals, value: "clerk.com")
            ]
        )
        let lowerPriorityRule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001")

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(higherPriorityRule)
        try store.saveRule(lowerPriorityRule)

        try store.reclassify(ruleID: lowerPriorityRule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .personal)
        #expect(classifications[matchingSegment.id]?.ruleID == higherPriorityRule.id)
    }

    @Test
    func reclassifyRuleUpdatesExactURLMatches() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(url: "file:///Users/Ivan/Preview.html", startedAt: baseDate)
        let otherSegment = segment(url: "file:///Users/Ivan/Other.html", offset: 600, startedAt: baseDate)
        let rule = Rule(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
            name: "Remember local preview",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .url, operation: .equals, value: "file:///users/ivan/preview.html")
            ]
        )

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: otherSegment,
            classification: SegmentClassification(
                segmentID: otherSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .work)
        #expect(classifications[matchingSegment.id]?.ruleID == rule.id)
        #expect(classifications[otherSegment.id]?.kind == .review)
    }

    @Test
    func reclassifyRuleUpdatesAppNameMatches() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(
            appName: "Linear",
            bundleIdentifier: "com.linear",
            windowTitle: "Issue list",
            url: nil,
            source: .macOS,
            startedAt: baseDate
        )
        let otherSegment = segment(
            appName: "Finder",
            bundleIdentifier: "com.apple.finder",
            windowTitle: "Downloads",
            url: nil,
            source: .macOS,
            offset: 600,
            startedAt: baseDate
        )
        let rule = Rule(
            id: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!,
            name: "Remember Linear",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .appName, operation: .equals, value: "linear")
            ]
        )

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: otherSegment,
            classification: SegmentClassification(
                segmentID: otherSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .work)
        #expect(classifications[matchingSegment.id]?.ruleID == rule.id)
        #expect(classifications[otherSegment.id]?.kind == .review)
    }

    @Test
    func saveRememberedRuleDoesNotCreateDuplicates() throws {
        let store = try makeStore()

        try store.saveRememberedRule(rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001"))
        try store.saveRememberedRule(rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000002"))

        let rememberedRules = try store.loadRules()
            .filter { $0.name == "Remember clerk.com" }

        #expect(rememberedRules.count == 1)
        #expect(rememberedRules.first?.id == UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))
    }

    @Test
    func deduplicateRememberedRulesKeepsActivityRuleReferences() throws {
        let store = try makeStore()
        let keeperRule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001")
        let duplicateRule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000002")
        let segment = segment(url: "https://clerk.com/docs")

        try store.saveRule(keeperRule)
        try store.saveRule(duplicateRule)
        try store.save(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: duplicateRule.id,
                isManual: false
            )
        )

        try store.deduplicateRememberedRules()

        let rememberedRules = try store.loadRules()
            .filter { $0.name == "Remember clerk.com" }
        let activitySegments = try store.activitySegments(for: Date())

        #expect(rememberedRules.count == 1)
        #expect(activitySegments.first?.classification.ruleID == keeperRule.id)
    }

    @Test
    func startupAddsMissingBuiltInRulesAndReclassifiesHistory() throws {
        let databaseURL = try temporaryDatabaseURL()
        let segment = segment(
            appName: "Discord",
            bundleIdentifier: "com.hnc.Discord",
            windowTitle: "#work | Jian Yang - Discord",
            url: nil,
            source: .macOS
        )

        do {
            let store = try WorklogStore(databaseURL: databaseURL)
            let rules = try store.loadRules()
            let discordWorkRule = try #require(rules.first { $0.name == "Discord Jian Yang #work is work" })
            try store.deleteRule(id: discordWorkRule.id)
            try store.save(
                segment: segment,
                classification: SegmentClassification(
                    segmentID: segment.id,
                    kind: .personal,
                    categoryID: SeedData.personalCategoryID,
                    projectID: nil,
                    ruleID: nil,
                    isManual: false
                )
            )
        }

        let reopenedStore = try WorklogStore(databaseURL: databaseURL)
        let rules = try reopenedStore.loadRules()
        let discordWorkRule = try #require(rules.first { $0.name == "Discord Jian Yang #work is work" })
        let activitySegments = try reopenedStore.activitySegments(for: Date())

        #expect(activitySegments.first?.classification.kind == .work)
        #expect(activitySegments.first?.classification.categoryID == SeedData.workCategoryID)
        #expect(activitySegments.first?.classification.ruleID == discordWorkRule.id)
    }

    @Test
    func activitySegmentsForDateReflectManualClassificationEdits() throws {
        let store = try makeStore()
        let segment = segment(url: "https://example.com")

        try store.save(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.overrideSegment(
            id: segment.id,
            kind: .personal,
            projectID: nil,
            categoryID: SeedData.personalCategoryID
        )

        let activitySegments = try store.activitySegments(for: Date())

        #expect(activitySegments.count == 1)
        #expect(activitySegments.first?.classification.kind == .personal)
        #expect(activitySegments.first?.classification.isManual == true)
    }

    @Test
    func daySummaryAggregatesChromeActivityByHost() throws {
        let store = try makeStore()
        let firstSegment = segment(url: "https://clerk.com/docs")
        let secondSegment = segment(url: "https://clerk.com/dashboard", offset: 600)
        let thirdSegment = segment(url: "https://x.com/home", offset: 1_200)

        for segment in [firstSegment, secondSegment, thirdSegment] {
            try store.save(
                segment: segment,
                classification: SegmentClassification(
                    segmentID: segment.id,
                    kind: .work,
                    categoryID: SeedData.workCategoryID,
                    projectID: nil,
                    ruleID: nil,
                    isManual: false
                )
            )
        }

        let summary = try store.daySummary(for: Date())

        #expect(summary.topApps.map(\.name) == ["clerk.com", "x.com"])
        #expect(summary.topApps.map(\.seconds) == [240, 120])
    }

    @Test
    func reviewSegmentsReturnsEntireBacklogNewestFirst() throws {
        let store = try makeStore()
        let olderSegment = segment(url: "https://older.example.com", offset: -172_800)
        let newerSegment = segment(url: "https://newer.example.com", offset: -86_400)

        try store.save(
            segment: olderSegment,
            classification: SegmentClassification(
                segmentID: olderSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: newerSegment,
            classification: SegmentClassification(
                segmentID: newerSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        let reviewSegments = try store.reviewSegments()

        #expect(reviewSegments.map(\.id) == [newerSegment.id, olderSegment.id])
    }

    @Test
    func saveCategoryKeepsExistingActivityAttached() throws {
        let store = try makeStore()
        let segment = segment(url: "https://example.com")

        try store.save(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        try store.saveCategory(
            Category(
                id: SeedData.workCategoryID,
                name: "Deep Work",
                kind: .work,
                colorHex: "#111111"
            )
        )

        let activitySegments = try store.activitySegments(for: Date())

        #expect(activitySegments.first?.classification.categoryID == SeedData.workCategoryID)
        #expect(activitySegments.first?.categoryName == "Deep Work")
    }

    @Test
    func weekReportAggregatesTotalsBucketsAndPreviousPeriod() throws {
        let store = try makeStore()
        let workSegment = segment(url: "https://example.com")
        let personalSegment = segment(url: "https://x.com", offset: 600)

        try store.save(
            segment: workSegment,
            classification: SegmentClassification(
                segmentID: workSegment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: personalSegment,
            classification: SegmentClassification(
                segmentID: personalSegment.id,
                kind: .personal,
                categoryID: SeedData.personalCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        let report = try store.reportSummary(for: .week, containing: Date())
        let previousReport = try store.previousReportSummary(for: .week, containing: Date())

        #expect(report.workSeconds == 120)
        #expect(report.personalSeconds == 120)
        #expect(report.totalSeconds == 240)
        #expect(report.buckets.count == 7)
        #expect(report.topApps.map(\.name) == ["example.com", "x.com"])
        #expect(report.topApps.map(\.seconds) == [120, 120])
        #expect(previousReport.totalSeconds == 0)
    }

    private func makeStore() throws -> WorklogStore {
        try WorklogStore(databaseURL: temporaryDatabaseURL())
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("worklog.sqlite")
    }

    private func classificationsBySegmentID(
        store: WorklogStore,
        date: Date
    ) throws -> [UUID: SegmentClassification] {
        try Dictionary(
            uniqueKeysWithValues: store.activitySegments(for: date).map { item in
                (item.id, item.classification)
            }
        )
    }

    private func middayToday() -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func segment(
        appName: String = "Google Chrome",
        bundleIdentifier: String = "com.google.Chrome",
        windowTitle: String = "Clerk",
        url: String?,
        source: ActivitySource = .chrome,
        offset: TimeInterval = 0,
        startedAt: Date = Date()
    ) -> ActivitySegment {
        let start = startedAt.addingTimeInterval(offset)
        let end = start.addingTimeInterval(120)
        let snapshot = ActivitySnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 1,
            windowTitle: windowTitle,
            url: url,
            source: source
        )

        return ActivitySegment(startedAt: start, endedAt: end, snapshot: snapshot)
    }

    private func rememberedRule(id: String) -> Rule {
        Rule(
            id: UUID(uuidString: id)!,
            name: "Remember clerk.com",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .equals, value: "clerk.com")
            ]
        )
    }
}
