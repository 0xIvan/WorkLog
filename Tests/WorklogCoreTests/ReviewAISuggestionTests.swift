import Foundation
import Testing
@testable import WorklogCore

@Suite
struct ReviewAISuggestionTests {
    @Test
    func groupsReviewBacklogByStableSignals() {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(url: "https://clerk.com/docs", offset: 0),
                classifiedSegment(url: "https://clerk.com/dashboard", offset: 120),
                classifiedSegment(url: "file:///Users/ivan/local.html", offset: 240),
                classifiedSegment(
                    appName: "Cursor",
                    bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    windowTitle: "",
                    url: nil,
                    source: .macOS,
                    offset: 360
                )
            ],
            sampleLimit: 1
        )

        let clerkGroup = request.groups.first { $0.proposedRuleCondition.value == "clerk.com" }
        let fileGroup = request.groups.first { $0.proposedRuleCondition.value == "file:///Users/ivan/local.html" }
        let cursorGroup = request.groups.first { $0.proposedRuleCondition.value == "Cursor" }

        #expect(clerkGroup?.proposedRuleCondition.field == .host)
        #expect(clerkGroup?.affectedCount == 2)
        #expect(clerkGroup?.affectedDuration == 240)
        #expect(clerkGroup?.samples.count == 1)
        #expect(fileGroup?.proposedRuleCondition.field == .url)
        #expect(cursorGroup?.proposedRuleCondition.field == .appName)
    }

    @Test
    func unsureSuggestionDoesNotApply() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "https://unknown.example.com").segment

        try saveReviewSegment(segment, in: store)

        let ruleID = try store.applyReviewAISuggestion(
            suggestion(
                kind: .unsure,
                confidence: 0.4,
                condition: RuleCondition(field: .host, operation: .equals, value: "unknown.example.com")
            )
        )

        #expect(ruleID == nil)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test
    func broadBrowserAppRuleIsRejected() {
        let validation = ReviewAISuggestionValidator().validationResult(
            for: suggestion(
                kind: .work,
                confidence: 0.9,
                condition: RuleCondition(field: .appName, operation: .equals, value: "Google Chrome")
            )
        )

        #expect(validation.canApply == false)
    }

    @Test
    func ignoredSuggestionStaysManualOnly() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "chrome-extension://example/options.html").segment
        let suggestion = suggestion(
            kind: .ignored,
            confidence: 0.9,
            condition: RuleCondition(field: .url, operation: .equals, value: "chrome-extension://example/options.html")
        )

        try saveReviewSegment(segment, in: store)
        let validation = ReviewAISuggestionValidator().validationResult(for: suggestion)
        let ruleID = try store.applyReviewAISuggestion(suggestion)

        #expect(validation.canApply == false)
        #expect(ruleID == nil)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test
    func highConfidenceHostSuggestionCreatesRememberedRuleAndReclassifiesHistory() throws {
        let store = try makeStore()
        let firstSegment = classifiedSegment(url: "https://clerk.com/docs").segment
        let secondSegment = classifiedSegment(url: "https://clerk.com/dashboard", offset: 120).segment
        let suggestion = suggestion(
            kind: .work,
            confidence: 0.9,
            condition: RuleCondition(field: .host, operation: .equals, value: "clerk.com")
        )

        try saveReviewSegment(firstSegment, in: store)
        try saveReviewSegment(secondSegment, in: store)

        let ruleID = try #require(try store.applyReviewAISuggestion(suggestion))
        let activitySegments = try store.activitySegments(for: Date())

        #expect(try store.reviewSegments().isEmpty)
        #expect(activitySegments.allSatisfy { $0.classification.kind == .work })
        #expect(activitySegments.allSatisfy { $0.classification.ruleID == ruleID })
        #expect(try store.loadRules().contains { $0.id == ruleID && $0.name == "Remember clerk.com" })
    }

    @Test
    func staleSuggestionWithoutCurrentReviewMatchesDoesNotCreateRule() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "https://clerk.com/docs").segment
        let staleWorkSuggestion = suggestion(
            kind: .work,
            confidence: 0.9,
            condition: RuleCondition(field: .host, operation: .equals, value: "clerk.com")
        )
        let manualPersonalRule = Rule(
            name: "Remember clerk.com",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .equals, value: "clerk.com")
            ]
        )

        try saveReviewSegment(segment, in: store)
        let manualRuleID = try store.saveRememberedRule(manualPersonalRule)
        try store.reclassify(ruleID: manualRuleID, scope: .allHistory)

        let staleRuleID = try store.applyReviewAISuggestion(staleWorkSuggestion)
        let rememberedClerkRules = try store.loadRules()
            .filter { $0.name == "Remember clerk.com" }

        #expect(staleRuleID == nil)
        #expect(try store.reviewSegments().isEmpty)
        #expect(rememberedClerkRules.count == 1)
        #expect(rememberedClerkRules.first?.action.kind == .personal)
    }

    @Test
    func localProviderProducesSuggestionsFromGroupedPayload() async throws {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(url: "https://github.com/0xIvan/WorkLog"),
                classifiedSegment(url: "https://github.com/openai/codex", offset: 120),
                classifiedSegment(url: "https://unknown.example.com", offset: 240)
            ]
        )

        let suggestions = try await LocalReviewAISuggestionProvider().suggestions(for: request)

        #expect(suggestions.first?.kind == .work)
        #expect(suggestions.first?.proposedRuleCondition?.value == "github.com")
        #expect(suggestions.contains { $0.kind == .unsure })
    }

    @Test
    func localProviderTreatsTravelAsPersonal() async throws {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(
                    windowTitle: "Manage a booking | Emirates",
                    url: "https://fly3.emirates.com/manage-booking"
                )
            ]
        )

        let suggestion = try #require(try await LocalReviewAISuggestionProvider().suggestions(for: request).first)

        #expect(suggestion.kind == .personal)
        #expect(suggestion.reason == "Matched local personal signal 'emirates'.")
    }

    @Test
    func ollamaProviderSkipsModelForLocalSignals() async throws {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(url: "https://github.com/0xIvan/WorkLog"),
                classifiedSegment(
                    windowTitle: "Manage a booking | Emirates",
                    url: "https://fly3.emirates.com/manage-booking",
                    offset: 120
                )
            ]
        )
        let provider = OllamaReviewAISuggestionProvider(
            endpoint: URL(string: "http://127.0.0.1:1/api/generate")!,
            model: "unavailable"
        )

        let suggestions = try await provider.suggestions(for: request)

        #expect(suggestions.contains { $0.kind == .work && $0.proposedRuleCondition?.value == "github.com" })
        #expect(suggestions.contains { $0.kind == .personal && $0.proposedRuleCondition?.value == "fly3.emirates.com" })
    }

    @Test
    func providerConfigurationDefaultsToOllama() throws {
        let configuration = ReviewAISuggestionProviderConfiguration(environment: [:])

        guard case .ollama(let endpoint, let model) = configuration else {
            Issue.record("Expected Ollama provider configuration")
            return
        }

        #expect(endpoint == URL(string: "http://localhost:11434/api/generate"))
        #expect(model == "qwen3:4b")
    }

    @Test
    func providerConfigurationKeepsLocalHeuristicOverride() {
        let configuration = ReviewAISuggestionProviderConfiguration(
            environment: ["WORKLOG_REVIEW_AI_PROVIDER": "local"]
        )

        #expect(configuration == .localHeuristic)
    }

    @Test
    func ollamaMapperPreservesAppRuleConditions() throws {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(url: "https://amazon.ae/ref=nav_logo"),
                classifiedSegment(url: "https://github.com/0xIvan/WorkLog", offset: 120)
            ]
        )
        let amazonID = try #require(request.groups.first { $0.proposedRuleCondition.value == "amazon.ae" }?.id)
        let githubID = try #require(request.groups.first { $0.proposedRuleCondition.value == "github.com" }?.id)
        let response = """
        {
          "suggestions": [
            {
              "groupID": "\(amazonID)",
              "kind": "personal",
              "confidence": 0.91,
              "reason": "Shopping site for consumer purchases."
            },
            {
              "groupID": "\(githubID)",
              "kind": "work",
              "confidence": 0.95,
              "reason": "Software development repository."
            }
          ]
        }
        """

        let suggestions = try OllamaReviewAISuggestionMapper.suggestions(from: response, for: request)
        let amazonSuggestion = try #require(suggestions.first { $0.id == amazonID })
        let githubSuggestion = try #require(suggestions.first { $0.id == githubID })

        #expect(amazonSuggestion.kind == .personal)
        #expect(amazonSuggestion.proposedRuleCondition?.field == .host)
        #expect(amazonSuggestion.proposedRuleCondition?.value == "amazon.ae")
        #expect(githubSuggestion.kind == .work)
        #expect(githubSuggestion.proposedRuleCondition?.field == .host)
        #expect(githubSuggestion.proposedRuleCondition?.value == "github.com")
    }

    @Test
    func ollamaMapperCorrectsTravelWorkSuggestionToPersonal() throws {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(
                    windowTitle: "Manage a booking | Emirates",
                    url: "https://fly3.emirates.com/manage-booking"
                )
            ]
        )
        let emiratesID = try #require(request.groups.first?.id)
        let response = """
        {
          "suggestions": [
            {
              "groupID": "\(emiratesID)",
              "kind": "work",
              "confidence": 0.95,
              "reason": "Emirates booking management - work"
            }
          ]
        }
        """

        let suggestion = try #require(try OllamaReviewAISuggestionMapper.suggestions(from: response, for: request).first)

        #expect(suggestion.kind == .personal)
        #expect(suggestion.confidence == 0.9)
        #expect(suggestion.reason == "Matched personal travel or consumer signal.")
    }

    private func makeStore() throws -> WorklogStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try WorklogStore(databaseURL: directory.appendingPathComponent("worklog.sqlite"))
    }

    private func saveReviewSegment(_ segment: ActivitySegment, in store: WorklogStore) throws {
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
    }

    private func suggestion(
        kind: ReviewAISuggestionKind,
        confidence: Double,
        condition: RuleCondition
    ) -> ReviewAISuggestion {
        ReviewAISuggestion(
            kind: kind,
            confidence: confidence,
            reason: "Test",
            proposedRuleCondition: condition,
            affectedCount: 1,
            affectedDuration: 120,
            samples: [
                ReviewAISuggestionSample(
                    appName: "Google Chrome",
                    bundleIdentifier: "com.google.Chrome",
                    windowTitle: "Test",
                    url: nil,
                    duration: 120
                )
            ]
        )
    }

    private func classifiedSegment(
        appName: String = "Google Chrome",
        bundleIdentifier: String = "com.google.Chrome",
        windowTitle: String = "Test",
        url: String?,
        source: ActivitySource = .chrome,
        offset: TimeInterval = 0
    ) -> ClassifiedSegment {
        let start = Date().addingTimeInterval(offset)
        let segment = ActivitySegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            snapshot: ActivitySnapshot(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: 1,
                windowTitle: windowTitle,
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
