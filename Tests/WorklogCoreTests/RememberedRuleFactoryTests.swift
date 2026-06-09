import Foundation
import Testing
import WorklogCore

@Suite
struct RememberedRuleFactoryTests {
    private let factory = RememberedRuleFactory()

    @Test
    func browserSegmentWithHostUsesHostRule() throws {
        let rule = try #require(factory.rule(
            from: classifiedSegment(url: "https://example.com/path", title: "Example"),
            kind: .work,
            categoryID: SeedData.workCategoryID
        ))

        #expect(rule.name == "Remember example.com")
        assertSingleCondition(rule, field: .host, operation: .equals, value: "example.com")
    }

    @Test
    func hostlessBrowserSegmentUsesExactURLRule() throws {
        let fileURL = "file:///Users/ivan/local-preview.html"
        let rule = try #require(factory.rule(
            from: classifiedSegment(url: fileURL),
            kind: .ignored,
            categoryID: nil
        ))

        #expect(rule.name == "Remember \(fileURL)")
        assertSingleCondition(rule, field: .url, operation: .equals, value: fileURL)
    }

    @Test
    func browserSegmentWithoutURLDoesNotCreateAppWideRule() {
        let rule = factory.rule(
            from: classifiedSegment(url: nil, title: ""),
            kind: .ignored,
            categoryID: nil
        )

        #expect(rule == nil)
    }

    @Test
    func nonBrowserSegmentCanUseAppRule() throws {
        let rule = try #require(factory.rule(
            from: classifiedSegment(appName: "Cursor", url: nil, title: "", source: .macOS),
            kind: .work,
            categoryID: SeedData.workCategoryID
        ))

        assertSingleCondition(rule, field: .appName, operation: .equals, value: "Cursor")
    }

    private func assertSingleCondition(
        _ rule: Rule,
        field: RuleField,
        operation: RuleOperation,
        value: String
    ) {
        #expect(rule.conditions.count == 1)
        #expect(rule.conditions.first?.field == field)
        #expect(rule.conditions.first?.operation == operation)
        #expect(rule.conditions.first?.value == value)
    }

    private func classifiedSegment(
        appName: String = "Google Chrome",
        url: String?,
        title: String = "",
        source: ActivitySource = .chrome
    ) -> ClassifiedSegment {
        let segment = ActivitySegment(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            snapshot: ActivitySnapshot(
                appName: appName,
                bundleIdentifier: appName == "Google Chrome" ? "com.google.Chrome" : "test.\(appName)",
                processIdentifier: 1,
                windowTitle: title,
                url: url,
                source: source
            )
        )

        return ClassifiedSegment(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            ),
            projectName: nil,
            categoryName: nil,
            ruleName: nil
        )
    }
}
