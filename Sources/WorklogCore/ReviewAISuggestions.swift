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
    case ollama(endpoint: URL, model: String)
    case localHeuristic
    case disabled

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        switch environment["WORKLOG_REVIEW_AI_PROVIDER"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off", "disabled", "none":
            self = .disabled
        case "local", "heuristic", "local-heuristic":
            self = .localHeuristic
        default:
            self = .ollama(
                endpoint: Self.ollamaEndpoint(from: environment),
                model: Self.ollamaModel(from: environment)
            )
        }
    }

    private static func ollamaEndpoint(from environment: [String: String]) -> URL {
        if let value = environment["WORKLOG_REVIEW_AI_ENDPOINT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }

        return URL(string: "http://localhost:11434/api/generate")!
    }

    private static func ollamaModel(from environment: [String: String]) -> String {
        let value = environment["WORKLOG_REVIEW_AI_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else {
            return "qwen3:4b"
        }

        return value
    }
}

public enum ReviewAISuggestionProviderFactory {
    public static func makeProvider(
        configuration: ReviewAISuggestionProviderConfiguration = ReviewAISuggestionProviderConfiguration()
    ) -> any ReviewAISuggestionProviding {
        switch configuration {
        case .ollama(let endpoint, let model):
            OllamaReviewAISuggestionProvider(endpoint: endpoint, model: model)
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

public struct OllamaReviewAISuggestionProvider: ReviewAISuggestionProviding {
    public var endpoint: URL
    public var model: String

    public init(endpoint: URL = URL(string: "http://localhost:11434/api/generate")!, model: String = "qwen3:4b") {
        self.endpoint = endpoint
        self.model = model
    }

    public func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        guard !request.groups.isEmpty else {
            return []
        }

        let localSuggestions = try await LocalReviewAISuggestionProvider().suggestions(for: request)
        let localSuggestionsByID = Dictionary(
            localSuggestions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let modelGroups = request.groups.filter { group in
            localSuggestionsByID[group.id]?.kind == .unsure
        }

        guard !modelGroups.isEmpty else {
            return sorted(localSuggestions)
        }

        let modelSuggestions = try await modelSuggestions(for: ReviewAISuggestionRequest(groups: modelGroups))
        let modelSuggestionIDs = Set(modelSuggestions.map(\.id))
        let retainedLocalSuggestions = localSuggestions.filter { suggestion in
            suggestion.kind != .unsure && !modelSuggestionIDs.contains(suggestion.id)
        }

        return sorted(retainedLocalSuggestions + modelSuggestions)
    }

    private func modelSuggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: model,
                prompt: prompt(for: request),
                stream: false,
                format: OllamaReviewResponseFormat(),
                think: false,
                options: OllamaGenerateOptions(temperature: 0)
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw OllamaReviewAISuggestionProviderError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaReviewAISuggestionProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaReviewAISuggestionProviderError.httpStatus(httpResponse.statusCode)
        }

        let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let modelResponse = generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseText = modelResponse.isEmpty ? generateResponse.thinking?.trimmingCharacters(in: .whitespacesAndNewlines) : modelResponse

        guard let responseText, !responseText.isEmpty else {
            throw OllamaReviewAISuggestionProviderError.emptyModelResponse
        }

        return try OllamaReviewAISuggestionMapper.suggestions(from: responseText, for: request)
    }

    private func sorted(_ suggestions: [ReviewAISuggestion]) -> [ReviewAISuggestion] {
        suggestions.sorted { first, second in
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

    private func prompt(for request: ReviewAISuggestionRequest) throws -> String {
        let payload = OllamaReviewPromptPayload(
            groups: request.groups.map { group in
                OllamaReviewPromptGroup(
                    groupID: group.id,
                    ruleField: group.proposedRuleCondition.field.rawValue,
                    ruleOperation: group.proposedRuleCondition.operation.rawValue,
                    ruleValue: group.proposedRuleCondition.value,
                    affectedCount: group.affectedCount,
                    affectedMinutes: Int((group.affectedDuration / 60).rounded()),
                    samples: group.samples.map { sample in
                        OllamaReviewPromptSample(
                            appName: sample.appName,
                            bundleIdentifier: sample.bundleIdentifier,
                            windowTitle: sample.windowTitle,
                            url: sample.url
                        )
                    }
                )
            }
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(decoding: data, as: UTF8.self)

        return """
        You classify grouped local activity Review items for a time tracking app.
        Return JSON only. Do not include markdown or commentary.
        For every input group, return one suggestion with the same groupID.
        Allowed kinds are: work, personal, ignored, unsure.
        Work means clear job, business, development, productivity, documentation, design, operations, or admin activity.
        Personal means consumer shopping, entertainment, social media, news, personal finance, travel, or other non-work activity.
        Use ignored only for OS noise, extensions, blank pages, login windows, or tracking artifacts.
        Treat consumer ecommerce sites such as Amazon as personal unless the evidence clearly shows business procurement.
        Treat airline, hotel, booking, loyalty, mileage, and travel-management pages as personal unless the title explicitly shows company travel administration.
        Use unsure when the evidence is weak or ambiguous.
        Use confidence from 0.0 to 1.0.
        Keep reason under 120 characters.
        The response must include a suggestions array with groupID, kind, confidence, and reason.
        Input:
        \(json)
        """
    }
}

public enum OllamaReviewAISuggestionProviderError: Error, LocalizedError, Sendable {
    case requestFailed(String)
    case invalidResponse
    case httpStatus(Int)
    case emptyModelResponse
    case invalidModelJSON

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            "Local AI provider unavailable: \(message)"
        case .invalidResponse:
            "Local AI provider returned an invalid response."
        case .httpStatus(let statusCode):
            "Local AI provider returned HTTP \(statusCode)."
        case .emptyModelResponse:
            "Local AI provider returned an empty response."
        case .invalidModelJSON:
            "Local AI provider returned invalid JSON."
        }
    }
}

struct OllamaReviewAISuggestionMapper {
    static func suggestions(from responseText: String, for request: ReviewAISuggestionRequest) throws -> [ReviewAISuggestion] {
        guard let data = responseText.data(using: .utf8),
              let response = try? JSONDecoder().decode(OllamaReviewModelResponse.self, from: data) else {
            throw OllamaReviewAISuggestionProviderError.invalidModelJSON
        }

        let modelSuggestionsByID = Dictionary(
            response.suggestions.map { ($0.groupID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return request.groups.map { group in
            guard let modelSuggestion = modelSuggestionsByID[group.id] else {
                return suggestion(
                    for: group,
                    kind: .unsure,
                    confidence: 0.2,
                    reason: "Local model did not return a suggestion for this group."
                )
            }

            let kind = ReviewAISuggestionKind(rawValue: modelSuggestion.kind.lowercased()) ?? .unsure
            let confidence = min(max(modelSuggestion.confidence, 0), 1)
            let reason = normalizedReason(modelSuggestion.reason)
            if kind == .work, personalGuardrailMatch(for: group) {
                return suggestion(
                    for: group,
                    kind: .personal,
                    confidence: min(confidence, 0.9),
                    reason: "Matched personal travel or consumer signal."
                )
            }

            return suggestion(
                for: group,
                kind: kind,
                confidence: confidence,
                reason: reason
            )
        }
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

    private static func suggestion(
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

    private static func normalizedReason(_ reason: String) -> String {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            return "Classified by local model."
        }

        guard trimmedReason.count > 120 else {
            return trimmedReason
        }

        return String(trimmedReason.prefix(120))
    }

    private static func personalGuardrailMatch(for group: ReviewAISuggestionGroup) -> Bool {
        let searchableText = searchableText(for: group)
        return personalGuardrailMarkers.contains { marker in
            searchableText.contains(marker)
        }
    }

    private static func searchableText(for group: ReviewAISuggestionGroup) -> String {
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

        return "\(group.proposedRuleCondition.value) \(sampleText)"
            .lowercased()
    }

    private static var personalGuardrailMarkers: [String] {
        [
            "amazon",
            "shopping",
            "emirates",
            "airline",
            "flight",
            "booking",
            "skywards",
            "hotel",
            "marriott",
            "travel"
        ]
    }
}

private struct OllamaGenerateRequest: Encodable {
    var model: String
    var prompt: String
    var stream: Bool
    var format: OllamaReviewResponseFormat
    var think: Bool
    var options: OllamaGenerateOptions
}

private struct OllamaGenerateOptions: Encodable {
    var temperature: Double
}

private struct OllamaGenerateResponse: Decodable {
    var response: String
    var thinking: String?
}

private struct OllamaReviewResponseFormat: Encodable {
    var type = "object"
    var properties = OllamaReviewResponseProperties()
    var required = ["suggestions"]
}

private struct OllamaReviewResponseProperties: Encodable {
    var suggestions = OllamaArraySchema()
}

private struct OllamaArraySchema: Encodable {
    var type = "array"
    var items = OllamaSuggestionSchema()
}

private struct OllamaSuggestionSchema: Encodable {
    var type = "object"
    var properties = OllamaSuggestionProperties()
    var required = ["groupID", "kind", "confidence", "reason"]
}

private struct OllamaSuggestionProperties: Encodable {
    var groupID = OllamaStringSchema()
    var kind = OllamaKindSchema()
    var confidence = OllamaNumberSchema(minimum: 0, maximum: 1)
    var reason = OllamaStringSchema()
}

private struct OllamaStringSchema: Encodable {
    var type = "string"
}

private struct OllamaKindSchema: Encodable {
    var type = "string"
    var values = ["work", "personal", "ignored", "unsure"]

    private enum CodingKeys: String, CodingKey {
        case type
        case values = "enum"
    }
}

private struct OllamaNumberSchema: Encodable {
    var type = "number"
    var minimum: Double
    var maximum: Double
}

private struct OllamaReviewPromptPayload: Encodable {
    var groups: [OllamaReviewPromptGroup]
}

private struct OllamaReviewPromptGroup: Encodable {
    var groupID: String
    var ruleField: String
    var ruleOperation: String
    var ruleValue: String
    var affectedCount: Int
    var affectedMinutes: Int
    var samples: [OllamaReviewPromptSample]
}

private struct OllamaReviewPromptSample: Encodable {
    var appName: String
    var bundleIdentifier: String
    var windowTitle: String
    var url: String?
}

private struct OllamaReviewModelResponse: Decodable {
    var suggestions: [OllamaReviewModelSuggestion]
}

private struct OllamaReviewModelSuggestion: Decodable {
    var groupID: String
    var kind: String
    var confidence: Double
    var reason: String
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

        if let marker = firstMatch(in: searchableText, markers: personalMarkers) {
            return suggestion(
                for: group,
                kind: .personal,
                confidence: 0.82,
                reason: "Matched local personal signal '\(marker)'."
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
            "calendar.notion.so",
            "amazon",
            "shopping",
            "emirates",
            "airline",
            "flight",
            "booking",
            "skywards",
            "hotel",
            "marriott",
            "travel"
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
