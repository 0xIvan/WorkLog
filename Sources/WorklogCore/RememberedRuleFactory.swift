import Foundation

public struct RememberedRuleFactory {
    public init() {}

    public func rule(
        from segment: ClassifiedSegment,
        kind: ActivityKind,
        categoryID: UUID?
    ) -> Rule? {
        guard let condition = condition(for: segment.segment.snapshot) else {
            return nil
        }

        return Rule(
            name: "Remember \(condition.value)",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(
                kind: kind,
                categoryID: categoryID,
                projectID: segment.classification.projectID
            ),
            conditions: [condition]
        )
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
        if !windowTitle.isEmpty {
            return RuleCondition(field: .windowTitle, operation: .contains, value: windowTitle)
        }

        let appName = snapshot.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return nil
        }

        return RuleCondition(field: .appName, operation: .equals, value: appName)
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
