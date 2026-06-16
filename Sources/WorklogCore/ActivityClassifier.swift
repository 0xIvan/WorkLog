import Foundation

public struct ActivityClassifier {
    public init() {}

    public func classify(snapshot: ActivitySnapshot, rules: [Rule]) -> ClassificationResult {
        classify(snapshot: snapshot, preparedRules: preparedRules(from: rules))
    }

    public func preparedRules(from rules: [Rule]) -> [Rule] {
        rules
            .filter(\.enabled)
            .filter { !isUnsafeRememberedBrowserAppRule($0) }
            .sorted { first, second in
                if first.priority == second.priority {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }

                return first.priority < second.priority
            }
    }

    public func classify(snapshot: ActivitySnapshot, preparedRules: [Rule]) -> ClassificationResult {
        if snapshot.isPrivate {
            return ClassificationResult(kind: .ignored, categoryID: nil, projectID: nil, ruleID: nil)
        }

        if isSystemSnapshot(snapshot: snapshot) {
            return ClassificationResult(kind: .ignored, categoryID: nil, projectID: nil, ruleID: nil)
        }

        if let rule = preparedRules.first(where: { matches(rule: $0, snapshot: snapshot) }) {
            return ClassificationResult(
                kind: rule.action.kind,
                categoryID: rule.action.categoryID,
                projectID: rule.action.projectID,
                ruleID: rule.id
            )
        }

        if isBrowser(snapshot: snapshot) {
            return ClassificationResult(kind: .review, categoryID: nil, projectID: nil, ruleID: nil)
        }

        return ClassificationResult(kind: .personal, categoryID: nil, projectID: nil, ruleID: nil)
    }

    public func matches(rule: Rule, snapshot: ActivitySnapshot) -> Bool {
        guard !rule.conditions.isEmpty else {
            return false
        }

        return rule.conditions.allSatisfy { condition in
            matches(condition: condition, snapshot: snapshot)
        }
    }

    private func matches(condition: RuleCondition, snapshot: ActivitySnapshot) -> Bool {
        let source = value(for: condition.field, snapshot: snapshot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let target = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !target.isEmpty else {
            return false
        }

        switch condition.operation {
        case .contains:
            return source.localizedCaseInsensitiveContains(target)
        case .equals:
            return source.caseInsensitiveCompare(target) == .orderedSame
        case .startsWith:
            return source.lowercased().hasPrefix(target.lowercased())
        case .endsWith:
            return source.lowercased().hasSuffix(target.lowercased())
        case .regex:
            return source.range(of: target, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private func value(for field: RuleField, snapshot: ActivitySnapshot) -> String {
        switch field {
        case .appName:
            snapshot.appName
        case .bundleIdentifier:
            snapshot.bundleIdentifier
        case .windowTitle:
            snapshot.windowTitle
        case .url:
            snapshot.url ?? ""
        case .host:
            snapshot.host
        }
    }

    private func isBrowser(snapshot: ActivitySnapshot) -> Bool {
        let app = snapshot.appName.lowercased()
        let bundle = snapshot.bundleIdentifier.lowercased()

        return app.contains("chrome")
            || app.contains("safari")
            || app.contains("arc")
            || app.contains("firefox")
            || bundle.contains("chrome")
            || bundle.contains("safari")
            || bundle.contains("arc")
            || bundle.contains("firefox")
    }

    private func isUnsafeRememberedBrowserAppRule(_ rule: Rule) -> Bool {
        guard !rule.isBuiltIn,
              rule.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("remember "),
              rule.conditions.count == 1,
              let condition = rule.conditions.first,
              condition.operation == .equals,
              condition.field == .appName || condition.field == .bundleIdentifier else {
            return false
        }

        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.contains("chrome")
            || value.contains("safari")
            || value.contains("arc")
            || value.contains("firefox")
    }

    private func isSystemSnapshot(snapshot: ActivitySnapshot) -> Bool {
        let app = snapshot.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bundle = snapshot.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return app == "loginwindow" || bundle == "com.apple.loginwindow"
    }
}
