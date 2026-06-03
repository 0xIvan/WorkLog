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

    private func makeStore() throws -> WorklogStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try WorklogStore(databaseURL: directory.appendingPathComponent("worklog.sqlite"))
    }

    private func segment(url: String, offset: TimeInterval = 0) -> ActivitySegment {
        let start = Date().addingTimeInterval(offset)
        let end = start.addingTimeInterval(120)
        let snapshot = ActivitySnapshot(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1,
            windowTitle: "Clerk",
            url: url,
            source: .chrome
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
