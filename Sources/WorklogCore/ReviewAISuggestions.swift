import Foundation

public enum ReviewAISuggestionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case work
    case personal
    case ignored
    case unsure

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .ignored:
            "Ignored"
        case .unsure:
            "Unsure"
        }
    }

    var activityKind: ActivityKind? {
        switch self {
        case .work:
            .work
        case .personal:
            .personal
        case .ignored:
            .ignored
        case .unsure:
            nil
        }
    }
}

public struct ReviewAISuggestionSample: Equatable, Codable, Sendable {
    public var appName: String
    public var bundleIdentifier: String
    public var windowTitle: String
    public var url: String?
    public var duration: TimeInterval

    public init(
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        url: String?,
        duration: TimeInterval
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.duration = duration
    }
}

public struct ReviewAISuggestionGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var proposedRuleCondition: RuleCondition
    public var affectedCount: Int
    public var affectedDuration: TimeInterval
    public var samples: [ReviewAISuggestionSample]

    public init(
        id: String,
        proposedRuleCondition: RuleCondition,
        affectedCount: Int,
        affectedDuration: TimeInterval,
        samples: [ReviewAISuggestionSample]
    ) {
        self.id = id
        self.proposedRuleCondition = proposedRuleCondition
        self.affectedCount = affectedCount
        self.affectedDuration = affectedDuration
        self.samples = samples
    }
}

public struct ReviewAISuggestionRequest: Equatable, Sendable {
    public var groups: [ReviewAISuggestionGroup]

    public init(groups: [ReviewAISuggestionGroup]) {
        self.groups = groups
    }

    public init(reviewSegments: [ClassifiedSegment], sampleLimit: Int = 3) {
        groups = ReviewAISuggestionGrouper().groups(from: reviewSegments, sampleLimit: sampleLimit)
    }
}

public struct ReviewAISuggestion: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ReviewAISuggestionKind
    public var confidence: Double
    public var reason: String
    public var proposedRuleCondition: RuleCondition?
    public var affectedCount: Int
    public var affectedDuration: TimeInterval
    public var samples: [ReviewAISuggestionSample]

    public init(
        id: String? = nil,
        kind: ReviewAISuggestionKind,
        confidence: Double,
        reason: String,
        proposedRuleCondition: RuleCondition?,
        affectedCount: Int,
        affectedDuration: TimeInterval,
        samples: [ReviewAISuggestionSample]
    ) {
        self.id = id ?? ReviewAISuggestion.stableID(
            kind: kind,
            condition: proposedRuleCondition,
            affectedCount: affectedCount
        )
        self.kind = kind
        self.confidence = confidence
        self.reason = reason
        self.proposedRuleCondition = proposedRuleCondition
        self.affectedCount = affectedCount
        self.affectedDuration = affectedDuration
        self.samples = samples
    }

    private static func stableID(
        kind: ReviewAISuggestionKind,
        condition: RuleCondition?,
        affectedCount: Int
    ) -> String {
        [
            kind.rawValue,
            condition?.field.rawValue ?? "none",
            condition?.operation.rawValue ?? "none",
            condition?.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "none",
            String(affectedCount)
        ]
            .joined(separator: "|")
    }
}

public protocol ReviewAISuggestionProviding: Sendable {
    func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion]
}

public enum ReviewAISuggestionProviderConfiguration: Equatable, Sendable {
    case localHeuristic
    case disabled

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        switch environment["WORKLOG_REVIEW_AI_PROVIDER"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off", "disabled", "none":
            self = .disabled
        default:
            self = .localHeuristic
        }
    }
}

public enum ReviewAISuggestionProviderFactory {
    public static func makeProvider(
        configuration: ReviewAISuggestionProviderConfiguration = ReviewAISuggestionProviderConfiguration()
    ) -> any ReviewAISuggestionProviding {
        switch configuration {
        case .localHeuristic:
            LocalReviewAISuggestionProvider()
        case .disabled:
            DisabledReviewAISuggestionProvider()
        }
    }
}

public struct DisabledReviewAISuggestionProvider: ReviewAISuggestionProviding {
    public init() {}

    public func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        []
    }
}

public struct LocalReviewAISuggestionProvider: ReviewAISuggestionProviding {
    public init() {}

    public func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        request.groups
            .map(suggestion(for:))
            .sorted { first, second in
                if first.kind == .unsure, second.kind != .unsure {
                    return false
                }

                if first.kind != .unsure, second.kind == .unsure {
                    return true
                }

                if first.confidence == second.confidence {
                    return first.affectedDuration > second.affectedDuration
                }

                return first.confidence > second.confidence
            }
    }

    private func suggestion(for group: ReviewAISuggestionGroup) -> ReviewAISuggestion {
        let conditionValue = group.proposedRuleCondition.value.lowercased()
        let sampleText = group.samples
            .flatMap { sample in
                [
                    sample.appName,
                    sample.bundleIdentifier,
                    sample.windowTitle,
                    sample.url ?? ""
                ]
            }
            .joined(separator: " ")
            .lowercased()
        let searchableText = "\(conditionValue) \(sampleText)"

        if let marker = firstMatch(in: searchableText, markers: ignoredMarkers) {
            return suggestion(
                for: group,
                kind: .ignored,
                confidence: 0.86,
                reason: "Matched local ignore signal '\(marker)'."
            )
        }

        if let marker = firstMatch(in: searchableText, markers: workMarkers) {
            return suggestion(
                for: group,
                kind: .work,
                confidence: 0.82,
                reason: "Matched local work signal '\(marker)'."
            )
        }

        if let marker = firstMatch(in: searchableText, markers: personalMarkers) {
            return suggestion(
                for: group,
                kind: .personal,
                confidence: 0.82,
                reason: "Matched local personal signal '\(marker)'."
            )
        }

        return suggestion(
            for: group,
            kind: .unsure,
            confidence: 0.45,
            reason: "No strong local signal for this Review group."
        )
    }

    private func suggestion(
        for group: ReviewAISuggestionGroup,
        kind: ReviewAISuggestionKind,
        confidence: Double,
        reason: String
    ) -> ReviewAISuggestion {
        ReviewAISuggestion(
            id: group.id,
            kind: kind,
            confidence: confidence,
            reason: reason,
            proposedRuleCondition: group.proposedRuleCondition,
            affectedCount: group.affectedCount,
            affectedDuration: group.affectedDuration,
            samples: group.samples
        )
    }

    private func firstMatch(in text: String, markers: [String]) -> String? {
        markers.first { marker in
            text.contains(marker)
        }
    }

    private var workMarkers: [String] {
        [
            "github",
            "gitlab",
            "linear",
            "jira",
            "figma",
            "notion",
            "slack",
            "cursor",
            "xcode",
            "stackoverflow",
            "openai",
            "anthropic",
            "claude",
            "chatgpt",
            "vercel",
            "cloudflare",
            "supabase",
            "convex",
            "stripe",
            "clerk"
        ]
    }

    private var personalMarkers: [String] {
        [
            "youtube",
            "netflix",
            "instagram",
            "facebook",
            "reddit",
            "spotify",
            "twitter",
            "x.com",
            "calendar.notion.so"
        ]
    }

    private var ignoredMarkers: [String] {
        [
            "chrome-extension://",
            "about:blank",
            "loginwindow"
        ]
    }
}

public enum ReviewAISuggestionValidationResult: Equatable, Sendable {
    case applyAllowed
    case manualOnly(String)
    case rejected(String)

    public var canApply: Bool {
        self == .applyAllowed
    }
}

public struct ReviewAISuggestionValidator: Sendable {
    public static let minimumApplyConfidence = 0.75

    public init() {}

    public func validationResult(for suggestion: ReviewAISuggestion) -> ReviewAISuggestionValidationResult {
        guard suggestion.kind != .unsure else {
            return .manualOnly("Unsure suggestions need a manual decision.")
        }

        guard suggestion.kind != .ignored else {
            return .manualOnly("Ignored suggestions stay manual-only.")
        }

        guard suggestion.confidence >= Self.minimumApplyConfidence else {
            return .rejected("Confidence is too low to apply.")
        }

        guard let condition = suggestion.proposedRuleCondition else {
            return .rejected("Missing proposed rule condition.")
        }

        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return .rejected("Empty rule condition.")
        }

        guard supported(condition: condition) else {
            return .rejected("Unsupported rule condition.")
        }

        guard !isBroadBrowserRule(condition: condition, samples: suggestion.samples) else {
            return .rejected("Browser app rules are too broad.")
        }

        return .applyAllowed
    }

    private func supported(condition: RuleCondition) -> Bool {
        switch condition.field {
        case .host:
            condition.operation == .equals
        case .url:
            condition.operation == .equals
        case .appName, .bundleIdentifier:
            condition.operation == .equals
        case .windowTitle:
            condition.operation == .contains || condition.operation == .equals
        }
    }

    private func isBroadBrowserRule(condition: RuleCondition, samples: [ReviewAISuggestionSample]) -> Bool {
        switch condition.field {
        case .appName, .bundleIdentifier:
            return isBrowserText(condition.value)
        case .windowTitle:
            return samples.contains { sample in
                isBrowserText(sample.appName) || isBrowserText(sample.bundleIdentifier)
            }
        case .host, .url:
            return false
        }
    }

    private func isBrowserText(_ value: String) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedValue.contains("chrome")
            || normalizedValue.contains("safari")
            || normalizedValue.contains("arc")
            || normalizedValue.contains("firefox")
    }
}

public struct ReviewAISuggestionGrouper: Sendable {
    public init() {}

    public func groups(from reviewSegments: [ClassifiedSegment], sampleLimit: Int = 3) -> [ReviewAISuggestionGroup] {
        var groupsByID: [String: [ClassifiedSegment]] = [:]
        var conditionsByID: [String: RuleCondition] = [:]

        for item in reviewSegments where item.classification.kind == .review {
            guard let condition = condition(for: item.segment.snapshot) else {
                continue
            }

            let id = groupID(for: condition)
            groupsByID[id, default: []].append(item)
            conditionsByID[id] = condition
        }

        return groupsByID.map { id, items in
            let condition = conditionsByID[id]!

            let sortedItems = items.sorted { first, second in
                first.segment.startedAt > second.segment.startedAt
            }

            return ReviewAISuggestionGroup(
                id: id,
                proposedRuleCondition: condition,
                affectedCount: items.count,
                affectedDuration: items.reduce(0) { $0 + $1.segment.duration },
                samples: sortedItems.prefix(sampleLimit).map { item in
                    sample(from: item, condition: condition)
                }
            )
        }
        .sorted { first, second in
            if first.affectedDuration == second.affectedDuration {
                return first.proposedRuleCondition.value.localizedCaseInsensitiveCompare(
                    second.proposedRuleCondition.value
                ) == .orderedAscending
            }

            return first.affectedDuration > second.affectedDuration
        }
    }

    private func condition(for snapshot: ActivitySnapshot) -> RuleCondition? {
        let host = snapshot.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty {
            return RuleCondition(field: .host, operation: .equals, value: host)
        }

        if let url = snapshot.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            return RuleCondition(field: .url, operation: .equals, value: url)
        }

        if isBrowser(snapshot: snapshot) {
            return nil
        }

        let windowTitle = snapshot.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if windowTitle.count >= 4 {
            return RuleCondition(field: .windowTitle, operation: .contains, value: windowTitle)
        }

        let appName = snapshot.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return nil
        }

        return RuleCondition(field: .appName, operation: .equals, value: appName)
    }

    private func groupID(for condition: RuleCondition) -> String {
        [
            condition.field.rawValue,
            condition.operation.rawValue,
            condition.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
            .joined(separator: "|")
    }

    private func sample(from item: ClassifiedSegment, condition: RuleCondition) -> ReviewAISuggestionSample {
        ReviewAISuggestionSample(
            appName: trimmed(item.segment.appName, limit: 80),
            bundleIdentifier: trimmed(item.segment.bundleIdentifier, limit: 120),
            windowTitle: trimmed(item.segment.windowTitle, limit: 120),
            url: condition.field == .url ? trimmed(item.segment.url, limit: 180) : nil,
            duration: item.segment.duration
        )
    }

    private func trimmed(_ value: String?, limit: Int) -> String? {
        guard let value else {
            return nil
        }

        return trimmedString(value, limit: limit)
    }

    private func trimmed(_ value: String, limit: Int) -> String {
        trimmedString(value, limit: limit)
    }

    private func trimmedString(_ value: String, limit: Int) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.count > limit else {
            return trimmedValue
        }

        return String(trimmedValue.prefix(limit))
    }

    private func isBrowser(snapshot: ActivitySnapshot) -> Bool {
        let appName = snapshot.appName.lowercased()
        let bundleIdentifier = snapshot.bundleIdentifier.lowercased()

        return appName.contains("chrome")
            || appName.contains("safari")
            || appName.contains("arc")
            || appName.contains("firefox")
            || bundleIdentifier.contains("chrome")
            || bundleIdentifier.contains("safari")
            || bundleIdentifier.contains("arc")
            || bundleIdentifier.contains("firefox")
    }
}
