import Foundation

public enum SeedData {
    public static let workCategoryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    public static let personalCategoryID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    public static let reviewCategoryID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    public static var categories: [Category] {
        [
            Category(id: workCategoryID, name: "Work", kind: .work, colorHex: "#2563EB"),
            Category(id: personalCategoryID, name: "Personal", kind: .personal, colorHex: "#16A34A"),
            Category(id: reviewCategoryID, name: "Needs Review", kind: .review, colorHex: "#D97706")
        ]
    }

    public static var projects: [Project] {
        []
    }

    public static var rules: [Rule] {
        ignoreRules + workRules + personalRules
    }

    private static var ignoreRules: [Rule] {
        [
            rule(
                id: "00000000-0000-0000-0000-000000000003",
                name: "Ignore Chrome extension pages",
                priority: 10,
                kind: .ignored,
                field: .url,
                operation: .startsWith,
                value: "chrome-extension://"
            ),
            rule(
                id: "00000000-0000-0000-0000-000000000004",
                name: "Ignore incognito windows",
                priority: 10,
                kind: .ignored,
                field: .windowTitle,
                operation: .contains,
                value: "Incognito"
            )
        ]
    }

    private static var workRules: [Rule] {
        [
            rule(id: "20000000-0000-0000-0000-000000000001", name: "Cursor is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "Cursor"),
            rule(id: "20000000-0000-0000-0000-000000000002", name: "Codex is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "Codex"),
            rule(id: "20000000-0000-0000-0000-000000000003", name: "Slack is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "Slack"),
            rule(id: "20000000-0000-0000-0000-000000000004", name: "Notion is work", priority: 220, kind: .work, field: .appName, operation: .contains, value: "Notion"),
            rule(id: "20000000-0000-0000-0000-000000000005", name: "Google Docs is work", priority: 200, kind: .work, field: .host, operation: .equals, value: "docs.google.com"),
            rule(id: "20000000-0000-0000-0000-000000000006", name: "Figma is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "Figma"),
            rule(id: "20000000-0000-0000-0000-000000000007", name: "Zoom is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "zoom"),
            rule(id: "20000000-0000-0000-0000-000000000008", name: "Terminal is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "Terminal"),
            rule(id: "20000000-0000-0000-0000-000000000009", name: "iTerm is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "iTerm"),
            rule(id: "20000000-0000-0000-0000-000000000010", name: "Warp is work", priority: 200, kind: .work, field: .appName, operation: .contains, value: "Warp"),
            rule(id: "20000000-0000-0000-0000-000000000011", name: "Localhost is work", priority: 120, kind: .work, field: .host, operation: .equals, value: "localhost"),
            rule(id: "20000000-0000-0000-0000-000000000012", name: "127.0.0.1 is work", priority: 120, kind: .work, field: .host, operation: .equals, value: "127.0.0.1"),
            rule(id: "20000000-0000-0000-0000-000000000013", name: "IPv6 localhost is work", priority: 120, kind: .work, field: .url, operation: .contains, value: "[::1]")
        ]
    }

    private static var personalRules: [Rule] {
        [
            rule(id: "30000000-0000-0000-0000-000000000001", name: "Notion Calendar is personal", priority: 40, kind: .personal, field: .appName, operation: .contains, value: "Notion Calendar"),
            rule(id: "30000000-0000-0000-0000-000000000002", name: "calendar.notion.so is personal", priority: 40, kind: .personal, field: .host, operation: .equals, value: "calendar.notion.so"),
            rule(id: "30000000-0000-0000-0000-000000000003", name: "Finder is personal", priority: 300, kind: .personal, field: .appName, operation: .equals, value: "Finder"),
            rule(id: "30000000-0000-0000-0000-000000000004", name: "Discord is personal", priority: 300, kind: .personal, field: .appName, operation: .contains, value: "Discord"),
            rule(id: "30000000-0000-0000-0000-000000000005", name: "Spotify is personal", priority: 300, kind: .personal, field: .appName, operation: .contains, value: "Spotify"),
            rule(id: "30000000-0000-0000-0000-000000000006", name: "Twitter is personal", priority: 300, kind: .personal, field: .host, operation: .equals, value: "twitter.com"),
            rule(id: "30000000-0000-0000-0000-000000000007", name: "X is personal", priority: 300, kind: .personal, field: .host, operation: .equals, value: "x.com"),
            rule(id: "30000000-0000-0000-0000-000000000008", name: "Substack is personal", priority: 300, kind: .personal, field: .host, operation: .contains, value: "substack.com"),
            rule(id: "30000000-0000-0000-0000-000000000009", name: "YouTube is personal", priority: 300, kind: .personal, field: .host, operation: .equals, value: "youtube.com")
        ]
    }

    private static func rule(
        id: String,
        name: String,
        priority: Int,
        kind: ActivityKind,
        projectID: UUID? = nil,
        field: RuleField,
        operation: RuleOperation,
        value: String
    ) -> Rule {
        Rule(
            id: UUID(uuidString: id)!,
            name: name,
            priority: priority,
            enabled: true,
            isBuiltIn: true,
            action: RuleAction(
                kind: kind,
                categoryID: categoryID(for: kind),
                projectID: projectID
            ),
            conditions: [
                RuleCondition(field: field, operation: operation, value: value)
            ]
        )
    }

    private static func categoryID(for kind: ActivityKind) -> UUID? {
        switch kind {
        case .work:
            workCategoryID
        case .personal:
            personalCategoryID
        case .review:
            reviewCategoryID
        case .ignored:
            nil
        }
    }
}
