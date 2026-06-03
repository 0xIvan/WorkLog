import Foundation
import SQLite3

public enum WorklogStoreError: Error, LocalizedError {
    case failedToOpenDatabase(String)
    case failedToPrepare(String)
    case failedToStep(String)
    case missingDatabase

    public var errorDescription: String? {
        switch self {
        case .failedToOpenDatabase(let message):
            "Could not open database: \(message)"
        case .failedToPrepare(let message):
            "Could not prepare database statement: \(message)"
        case .failedToStep(let message):
            "Could not execute database statement: \(message)"
        case .missingDatabase:
            "Database connection is missing."
        }
    }
}

public enum ReclassificationScope: String, CaseIterable, Identifiable {
    case today
    case allHistory

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .today:
            "Today"
        case .allHistory:
            "All History"
        }
    }
}

private enum SQLiteValue {
    case text(String?)
    case integer(Int)
    case double(Double)
    case bool(Bool)
}

public final class WorklogStore {
    private var database: OpaquePointer?
    private let classifier = ActivityClassifier()

    public init(databaseURL: URL) throws {
        var connection: OpaquePointer?

        if sqlite3_open(databaseURL.path, &connection) != SQLITE_OK {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw WorklogStoreError.failedToOpenDatabase(message)
        }

        database = connection
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
        try seedIfNeeded()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public static func defaultDatabaseURL() throws -> URL {
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("Worklog", isDirectory: true)

        try FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )

        return supportURL.appendingPathComponent("worklog.sqlite")
    }

    public func save(segment: ActivitySegment, classification: SegmentClassification) throws {
        guard classification.kind != .ignored else {
            return
        }

        try execute(
            """
            INSERT OR REPLACE INTO activity_segments (
                id,
                started_at,
                ended_at,
                app_name,
                bundle_id,
                process_id,
                window_title,
                url,
                source
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(segment.id.uuidString),
                .double(segment.startedAt.timeIntervalSince1970),
                .double(segment.endedAt.timeIntervalSince1970),
                .text(segment.appName),
                .text(segment.bundleIdentifier),
                .integer(Int(segment.processIdentifier)),
                .text(segment.windowTitle),
                .text(segment.url),
                .text(segment.source.rawValue)
            ]
        )

        try saveClassification(classification)
    }

    public func loadRules() throws -> [Rule] {
        let rules = try query(
            """
            SELECT id, name, priority, enabled, is_built_in, action_kind, category_id, project_id
            FROM rules
            ORDER BY priority ASC, name ASC
            """
        ) { statement in
            Rule(
                id: uuidColumn(statement, 0),
                name: stringColumn(statement, 1),
                priority: intColumn(statement, 2),
                enabled: boolColumn(statement, 3),
                isBuiltIn: boolColumn(statement, 4),
                action: RuleAction(
                    kind: ActivityKind(rawValue: stringColumn(statement, 5)) ?? .review,
                    categoryID: optionalUUIDColumn(statement, 6),
                    projectID: optionalUUIDColumn(statement, 7)
                ),
                conditions: []
            )
        }

        var populatedRules: [Rule] = []
        for var rule in rules {
            rule.conditions = try loadConditions(ruleID: rule.id)
            populatedRules.append(rule)
        }

        return populatedRules
    }

    public func saveRule(_ rule: Rule) throws {
        try execute(
            """
            INSERT OR REPLACE INTO rules (
                id,
                name,
                priority,
                enabled,
                is_built_in,
                action_kind,
                category_id,
                project_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(rule.id.uuidString),
                .text(rule.name),
                .integer(rule.priority),
                .bool(rule.enabled),
                .bool(rule.isBuiltIn),
                .text(rule.action.kind.rawValue),
                .text(rule.action.categoryID?.uuidString),
                .text(rule.action.projectID?.uuidString)
            ]
        )

        try execute("DELETE FROM rule_conditions WHERE rule_id = ?", bindings: [.text(rule.id.uuidString)])

        for condition in rule.conditions {
            try execute(
                """
                INSERT INTO rule_conditions (id, rule_id, field, operation, value)
                VALUES (?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(condition.id.uuidString),
                    .text(rule.id.uuidString),
                    .text(condition.field.rawValue),
                    .text(condition.operation.rawValue),
                    .text(condition.value)
                ]
            )
        }
    }

    public func deleteRule(id: UUID) throws {
        try execute("DELETE FROM rule_conditions WHERE rule_id = ?", bindings: [.text(id.uuidString)])
        try execute("DELETE FROM rules WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func loadCategories() throws -> [Category] {
        try query(
            """
            SELECT id, name, kind, color_hex
            FROM categories
            ORDER BY name ASC
            """
        ) { statement in
            Category(
                id: uuidColumn(statement, 0),
                name: stringColumn(statement, 1),
                kind: ActivityKind(rawValue: stringColumn(statement, 2)) ?? .review,
                colorHex: stringColumn(statement, 3)
            )
        }
    }

    public func saveCategory(_ category: Category) throws {
        try execute(
            """
            INSERT INTO categories (id, name, kind, color_hex)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                kind = excluded.kind,
                color_hex = excluded.color_hex
            """,
            bindings: [
                .text(category.id.uuidString),
                .text(category.name),
                .text(category.kind.rawValue),
                .text(category.colorHex)
            ]
        )
    }

    public func deleteCategory(id: UUID) throws {
        try execute("DELETE FROM categories WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func loadProjects() throws -> [Project] {
        try query(
            """
            SELECT id, name, color_hex, is_archived
            FROM projects
            ORDER BY is_archived ASC, name ASC
            """
        ) { statement in
            Project(
                id: uuidColumn(statement, 0),
                name: stringColumn(statement, 1),
                colorHex: stringColumn(statement, 2),
                isArchived: boolColumn(statement, 3)
            )
        }
    }

    public func saveProject(_ project: Project) throws {
        try execute(
            """
            INSERT INTO projects (id, name, color_hex, is_archived)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                color_hex = excluded.color_hex,
                is_archived = excluded.is_archived
            """,
            bindings: [
                .text(project.id.uuidString),
                .text(project.name),
                .text(project.colorHex),
                .bool(project.isArchived)
            ]
        )
    }

    public func deleteProject(id: UUID) throws {
        try execute("UPDATE rules SET project_id = NULL WHERE project_id = ?", bindings: [.text(id.uuidString)])
        try execute("DELETE FROM projects WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func overrideSegment(id: UUID, kind: ActivityKind, projectID: UUID?, categoryID: UUID?) throws {
        let classification = SegmentClassification(
            segmentID: id,
            kind: kind,
            categoryID: categoryID,
            projectID: projectID,
            ruleID: nil,
            isManual: true
        )

        try saveClassification(classification)
    }

    public func ignoreSegment(id: UUID) throws {
        try deleteSegment(id: id)
    }

    public func reclassify(scope: ReclassificationScope) throws {
        let startDate: Date?
        switch scope {
        case .today:
            startDate = dayInterval(for: Date()).start
        case .allHistory:
            startDate = nil
        }

        let rules = try loadRules()
        let segments = try loadSegments(startDate: startDate)

        for segment in segments {
            guard let existing = try loadClassification(segmentID: segment.id), !existing.isManual else {
                continue
            }

            let result = classifier.classify(snapshot: segment.snapshot, rules: rules)
            if result.kind == .ignored {
                try deleteSegment(id: segment.id)
                continue
            }

            try saveClassification(
                SegmentClassification(
                    segmentID: segment.id,
                    kind: result.kind,
                    categoryID: result.categoryID,
                    projectID: result.projectID,
                    ruleID: result.ruleID,
                    isManual: false
                )
            )
        }
    }

    public func daySummary(for date: Date) throws -> DaySummary {
        let interval = dayInterval(for: date)
        let segments = try classifiedSegments(startingAt: interval.start, endingBefore: interval.end)

        var workSeconds: TimeInterval = 0
        var personalSeconds: TimeInterval = 0
        var reviewSeconds: TimeInterval = 0
        var appDurations: [String: TimeInterval] = [:]
        var projectDurations: [String: TimeInterval] = [:]

        for item in segments {
            let duration = item.segment.duration
            switch item.classification.kind {
            case .work:
                workSeconds += duration
            case .personal:
                personalSeconds += duration
            case .review:
                reviewSeconds += duration
            case .ignored:
                continue
            }

            appDurations[item.segment.appName, default: 0] += duration

            if let projectName = item.projectName {
                projectDurations[projectName, default: 0] += duration
            }
        }

        return DaySummary(
            date: interval.start,
            workSeconds: workSeconds,
            personalSeconds: personalSeconds,
            reviewSeconds: reviewSeconds,
            topApps: buckets(from: appDurations, kind: .work),
            topProjects: buckets(from: projectDurations, kind: .work)
        )
    }

    public func weekSummary(containing date: Date) throws -> [WeekDaySummary] {
        let start = WorklogCalendar.shared.weekStart(containing: date)

        return try (0..<7).map { offset in
            let day = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
            let summary = try daySummary(for: day)

            return WeekDaySummary(
                date: summary.date,
                workSeconds: summary.workSeconds,
                personalSeconds: summary.personalSeconds,
                reviewSeconds: summary.reviewSeconds
            )
        }
    }

    public func reviewSegments(for date: Date) throws -> [ClassifiedSegment] {
        let interval = dayInterval(for: date)

        return try classifiedSegments(startingAt: interval.start, endingBefore: interval.end)
            .filter { $0.classification.kind == .review }
    }

    public func activitySegments(for date: Date) throws -> [ClassifiedSegment] {
        let interval = dayInterval(for: date)

        return try classifiedSegments(startingAt: interval.start, endingBefore: interval.end)
            .sorted { first, second in
                first.segment.startedAt > second.segment.startedAt
            }
    }

    public func recentSegments(limit: Int) throws -> [ClassifiedSegment] {
        try query(
            """
            SELECT
                s.id,
                s.started_at,
                s.ended_at,
                s.app_name,
                s.bundle_id,
                s.process_id,
                s.window_title,
                s.url,
                s.source,
                c.kind,
                c.category_id,
                c.project_id,
                c.rule_id,
                c.is_manual,
                p.name,
                cat.name,
                r.name
            FROM activity_segments s
            JOIN classifications c ON c.segment_id = s.id
            LEFT JOIN projects p ON p.id = c.project_id
            LEFT JOIN categories cat ON cat.id = c.category_id
            LEFT JOIN rules r ON r.id = c.rule_id
            ORDER BY s.ended_at DESC
            LIMIT ?
            """,
            bindings: [.integer(limit)]
        ) { statement in
            classifiedSegmentColumn(statement)
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS categories (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                color_hex TEXT NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                is_archived INTEGER NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS rules (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                priority INTEGER NOT NULL,
                enabled INTEGER NOT NULL,
                is_built_in INTEGER NOT NULL,
                action_kind TEXT NOT NULL,
                category_id TEXT,
                project_id TEXT,
                FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS rule_conditions (
                id TEXT PRIMARY KEY,
                rule_id TEXT NOT NULL,
                field TEXT NOT NULL,
                operation TEXT NOT NULL,
                value TEXT NOT NULL,
                FOREIGN KEY(rule_id) REFERENCES rules(id) ON DELETE CASCADE
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS activity_segments (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                process_id INTEGER NOT NULL,
                window_title TEXT NOT NULL,
                url TEXT,
                source TEXT NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS classifications (
                segment_id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                category_id TEXT,
                project_id TEXT,
                rule_id TEXT,
                is_manual INTEGER NOT NULL,
                FOREIGN KEY(segment_id) REFERENCES activity_segments(id) ON DELETE CASCADE,
                FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL,
                FOREIGN KEY(rule_id) REFERENCES rules(id) ON DELETE SET NULL
            )
            """
        )

        try execute("CREATE INDEX IF NOT EXISTS activity_segments_started_at_idx ON activity_segments(started_at)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_ended_at_idx ON activity_segments(ended_at)")
        try execute("CREATE INDEX IF NOT EXISTS rules_priority_idx ON rules(priority)")
        try deleteSystemSegments()
    }

    private func seedIfNeeded() throws {
        if try count(table: "categories") == 0 {
            for category in SeedData.categories {
                try saveCategory(category)
            }
        }

        if try count(table: "projects") == 0 {
            for project in SeedData.projects {
                try saveProject(project)
            }
        }

        if try count(table: "rules") == 0 {
            for rule in SeedData.rules {
                try saveRule(rule)
            }
        }
    }

    private func count(table: String) throws -> Int {
        try query("SELECT COUNT(*) FROM \(table)") { statement in
            intColumn(statement, 0)
        }
        .first ?? 0
    }

    private func loadConditions(ruleID: UUID) throws -> [RuleCondition] {
        try query(
            """
            SELECT id, field, operation, value
            FROM rule_conditions
            WHERE rule_id = ?
            ORDER BY rowid ASC
            """,
            bindings: [.text(ruleID.uuidString)]
        ) { statement in
            RuleCondition(
                id: uuidColumn(statement, 0),
                field: RuleField(rawValue: stringColumn(statement, 1)) ?? .windowTitle,
                operation: RuleOperation(rawValue: stringColumn(statement, 2)) ?? .contains,
                value: stringColumn(statement, 3)
            )
        }
    }

    private func saveClassification(_ classification: SegmentClassification) throws {
        try execute(
            """
            INSERT OR REPLACE INTO classifications (
                segment_id,
                kind,
                category_id,
                project_id,
                rule_id,
                is_manual
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(classification.segmentID.uuidString),
                .text(classification.kind.rawValue),
                .text(classification.categoryID?.uuidString),
                .text(classification.projectID?.uuidString),
                .text(classification.ruleID?.uuidString),
                .bool(classification.isManual)
            ]
        )
    }

    private func loadClassification(segmentID: UUID) throws -> SegmentClassification? {
        try query(
            """
            SELECT segment_id, kind, category_id, project_id, rule_id, is_manual
            FROM classifications
            WHERE segment_id = ?
            """,
            bindings: [.text(segmentID.uuidString)]
        ) { statement in
            SegmentClassification(
                segmentID: uuidColumn(statement, 0),
                kind: ActivityKind(rawValue: stringColumn(statement, 1)) ?? .review,
                categoryID: optionalUUIDColumn(statement, 2),
                projectID: optionalUUIDColumn(statement, 3),
                ruleID: optionalUUIDColumn(statement, 4),
                isManual: boolColumn(statement, 5)
            )
        }
        .first
    }

    private func deleteSegment(id: UUID) throws {
        try execute("DELETE FROM activity_segments WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    private func deleteSystemSegments() throws {
        try execute(
            """
            DELETE FROM activity_segments
            WHERE lower(app_name) = 'loginwindow'
                OR lower(bundle_id) = 'com.apple.loginwindow'
            """
        )
    }

    private func loadSegments(startDate: Date?) throws -> [ActivitySegment] {
        if let startDate {
            return try query(
                """
                SELECT id, started_at, ended_at, app_name, bundle_id, process_id, window_title, url, source
                FROM activity_segments
                WHERE started_at >= ?
                ORDER BY started_at ASC
                """,
                bindings: [.double(startDate.timeIntervalSince1970)]
            ) { statement in
                activitySegmentColumn(statement)
            }
        }

        return try query(
            """
            SELECT id, started_at, ended_at, app_name, bundle_id, process_id, window_title, url, source
            FROM activity_segments
            ORDER BY started_at ASC
            """
        ) { statement in
            activitySegmentColumn(statement)
        }
    }

    private func classifiedSegments(startingAt start: Date, endingBefore end: Date) throws -> [ClassifiedSegment] {
        try query(
            """
            SELECT
                s.id,
                s.started_at,
                s.ended_at,
                s.app_name,
                s.bundle_id,
                s.process_id,
                s.window_title,
                s.url,
                s.source,
                c.kind,
                c.category_id,
                c.project_id,
                c.rule_id,
                c.is_manual,
                p.name,
                cat.name,
                r.name
            FROM activity_segments s
            JOIN classifications c ON c.segment_id = s.id
            LEFT JOIN projects p ON p.id = c.project_id
            LEFT JOIN categories cat ON cat.id = c.category_id
            LEFT JOIN rules r ON r.id = c.rule_id
            WHERE s.started_at >= ? AND s.started_at < ?
            ORDER BY s.started_at ASC
            """,
            bindings: [
                .double(start.timeIntervalSince1970),
                .double(end.timeIntervalSince1970)
            ]
        ) { statement in
            classifiedSegmentColumn(statement)
        }
    }

    private func dayInterval(for date: Date) -> DateInterval {
        WorklogCalendar.shared.dayInterval(containing: date)
    }

    private func buckets(from durations: [String: TimeInterval], kind: ActivityKind) -> [TimeBucket] {
        durations
            .sorted { first, second in
                first.value > second.value
            }
            .prefix(8)
            .map { name, seconds in
                TimeBucket(id: "\(kind.rawValue)-\(name)", name: name, seconds: seconds, kind: kind)
            }
    }

    private func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        guard let database else {
            throw WorklogStoreError.missingDatabase
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw WorklogStoreError.failedToPrepare(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WorklogStoreError.failedToStep(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        map: (OpaquePointer?) throws -> T
    ) throws -> [T] {
        guard let database else {
            throw WorklogStoreError.missingDatabase
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw WorklogStoreError.failedToPrepare(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(try map(statement))
        }

        return rows
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let sqliteIndex = Int32(index + 1)
            switch value {
            case .text(let text):
                if let text {
                    sqlite3_bind_text(statement, sqliteIndex, text, -1, sqliteTransient)
                } else {
                    sqlite3_bind_null(statement, sqliteIndex)
                }
            case .integer(let integer):
                sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(integer))
            case .double(let double):
                sqlite3_bind_double(statement, sqliteIndex, double)
            case .bool(let bool):
                sqlite3_bind_int(statement, sqliteIndex, bool ? 1 : 0)
            }
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func activitySegmentColumn(_ statement: OpaquePointer?) -> ActivitySegment {
    let snapshot = ActivitySnapshot(
        appName: stringColumn(statement, 3),
        bundleIdentifier: stringColumn(statement, 4),
        processIdentifier: Int32(intColumn(statement, 5)),
        windowTitle: stringColumn(statement, 6),
        url: optionalStringColumn(statement, 7),
        source: ActivitySource(rawValue: stringColumn(statement, 8)) ?? .macOS
    )

    return ActivitySegment(
        id: uuidColumn(statement, 0),
        startedAt: Date(timeIntervalSince1970: doubleColumn(statement, 1)),
        endedAt: Date(timeIntervalSince1970: doubleColumn(statement, 2)),
        snapshot: snapshot
    )
}

private func classifiedSegmentColumn(_ statement: OpaquePointer?) -> ClassifiedSegment {
    let segment = activitySegmentColumn(statement)
    let classification = SegmentClassification(
        segmentID: segment.id,
        kind: ActivityKind(rawValue: stringColumn(statement, 9)) ?? .review,
        categoryID: optionalUUIDColumn(statement, 10),
        projectID: optionalUUIDColumn(statement, 11),
        ruleID: optionalUUIDColumn(statement, 12),
        isManual: boolColumn(statement, 13)
    )

    return ClassifiedSegment(
        segment: segment,
        classification: classification,
        projectName: optionalStringColumn(statement, 14),
        categoryName: optionalStringColumn(statement, 15),
        ruleName: optionalStringColumn(statement, 16)
    )
}

private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String {
    guard let text = sqlite3_column_text(statement, index) else {
        return ""
    }

    return String(cString: text)
}

private func optionalStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }

    return stringColumn(statement, index)
}

private func intColumn(_ statement: OpaquePointer?, _ index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
}

private func boolColumn(_ statement: OpaquePointer?, _ index: Int32) -> Bool {
    sqlite3_column_int(statement, index) == 1
}

private func doubleColumn(_ statement: OpaquePointer?, _ index: Int32) -> Double {
    sqlite3_column_double(statement, index)
}

private func uuidColumn(_ statement: OpaquePointer?, _ index: Int32) -> UUID {
    UUID(uuidString: stringColumn(statement, index)) ?? UUID()
}

private func optionalUUIDColumn(_ statement: OpaquePointer?, _ index: Int32) -> UUID? {
    guard let value = optionalStringColumn(statement, index) else {
        return nil
    }

    return UUID(uuidString: value)
}
