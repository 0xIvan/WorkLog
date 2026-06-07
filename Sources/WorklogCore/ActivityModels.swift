import Foundation

public enum ActivityKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case work
    case personal
    case review
    case ignored

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .review:
            "Needs Review"
        case .ignored:
            "Ignored"
        }
    }
}

public enum ActivitySource: String, CaseIterable, Codable, Identifiable, Sendable {
    case macOS
    case chrome

    public var id: String {
        rawValue
    }
}

public struct ActivitySnapshot: Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String
    public var processIdentifier: Int32
    public var windowTitle: String
    public var url: String?
    public var source: ActivitySource
    public var isPrivate: Bool

    public init(
        appName: String,
        bundleIdentifier: String,
        processIdentifier: Int32,
        windowTitle: String,
        url: String?,
        source: ActivitySource,
        isPrivate: Bool = false
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.source = source
        self.isPrivate = isPrivate
    }

    public var normalizedSignature: String {
        [
            appName,
            bundleIdentifier,
            windowTitle,
            url ?? "",
            isPrivate ? "private" : "public"
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }

    public var host: String {
        guard let url else {
            return ""
        }

        return URL(string: url)?.host?.lowercased() ?? ""
    }
}

public struct ActivitySegment: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var appName: String
    public var bundleIdentifier: String
    public var processIdentifier: Int32
    public var windowTitle: String
    public var url: String?
    public var source: ActivitySource

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        snapshot: ActivitySnapshot
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        appName = snapshot.appName
        bundleIdentifier = snapshot.bundleIdentifier
        processIdentifier = snapshot.processIdentifier
        windowTitle = snapshot.windowTitle
        url = snapshot.url
        source = snapshot.source
    }

    public var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    public var snapshot: ActivitySnapshot {
        ActivitySnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowTitle: windowTitle,
            url: url,
            source: source
        )
    }
}

public struct SegmentClassification: Equatable, Sendable {
    public var segmentID: UUID
    public var kind: ActivityKind
    public var categoryID: UUID?
    public var projectID: UUID?
    public var ruleID: UUID?
    public var isManual: Bool

    public init(
        segmentID: UUID,
        kind: ActivityKind,
        categoryID: UUID?,
        projectID: UUID?,
        ruleID: UUID?,
        isManual: Bool
    ) {
        self.segmentID = segmentID
        self.kind = kind
        self.categoryID = categoryID
        self.projectID = projectID
        self.ruleID = ruleID
        self.isManual = isManual
    }
}

public struct ClassifiedSegment: Identifiable, Equatable, Sendable {
    public var segment: ActivitySegment
    public var classification: SegmentClassification
    public var projectName: String?
    public var categoryName: String?
    public var ruleName: String?

    public init(
        segment: ActivitySegment,
        classification: SegmentClassification,
        projectName: String?,
        categoryName: String?,
        ruleName: String?
    ) {
        self.segment = segment
        self.classification = classification
        self.projectName = projectName
        self.categoryName = categoryName
        self.ruleName = ruleName
    }

    public var id: UUID {
        segment.id
    }
}

public struct TimeBucket: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var seconds: TimeInterval
    public var kind: ActivityKind

    public init(id: String, name: String, seconds: TimeInterval, kind: ActivityKind) {
        self.id = id
        self.name = name
        self.seconds = seconds
        self.kind = kind
    }
}

public struct DaySummary: Equatable, Sendable {
    public var date: Date
    public var workSeconds: TimeInterval
    public var personalSeconds: TimeInterval
    public var reviewSeconds: TimeInterval
    public var topApps: [TimeBucket]
    public var topProjects: [TimeBucket]

    public init(
        date: Date,
        workSeconds: TimeInterval,
        personalSeconds: TimeInterval,
        reviewSeconds: TimeInterval,
        topApps: [TimeBucket],
        topProjects: [TimeBucket]
    ) {
        self.date = date
        self.workSeconds = workSeconds
        self.personalSeconds = personalSeconds
        self.reviewSeconds = reviewSeconds
        self.topApps = topApps
        self.topProjects = topProjects
    }

    public static func empty(on date: Date) -> DaySummary {
        DaySummary(
            date: date,
            workSeconds: 0,
            personalSeconds: 0,
            reviewSeconds: 0,
            topApps: [],
            topProjects: []
        )
    }
}

public struct WeekDaySummary: Identifiable, Equatable, Sendable {
    public var id: Date {
        date
    }

    public var date: Date
    public var workSeconds: TimeInterval
    public var personalSeconds: TimeInterval
    public var reviewSeconds: TimeInterval

    public init(
        date: Date,
        workSeconds: TimeInterval,
        personalSeconds: TimeInterval,
        reviewSeconds: TimeInterval
    ) {
        self.date = date
        self.workSeconds = workSeconds
        self.personalSeconds = personalSeconds
        self.reviewSeconds = reviewSeconds
    }
}

public enum ReportPeriodKind: String, CaseIterable, Identifiable, Sendable {
    case week
    case month

    public var id: String {
        rawValue
    }
}

public enum ReportBucketKind: Sendable {
    case day
    case week
}

public struct ReportBucket: Identifiable, Equatable, Sendable {
    public var id: Date {
        startDate
    }

    public var startDate: Date
    public var endDate: Date
    public var workSeconds: TimeInterval
    public var personalSeconds: TimeInterval
    public var reviewSeconds: TimeInterval

    public init(
        startDate: Date,
        endDate: Date,
        workSeconds: TimeInterval,
        personalSeconds: TimeInterval,
        reviewSeconds: TimeInterval
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.workSeconds = workSeconds
        self.personalSeconds = personalSeconds
        self.reviewSeconds = reviewSeconds
    }
}

public struct ReportSummary: Equatable, Sendable {
    public var periodKind: ReportPeriodKind
    public var startDate: Date
    public var endDate: Date
    public var workSeconds: TimeInterval
    public var personalSeconds: TimeInterval
    public var reviewSeconds: TimeInterval
    public var topApps: [TimeBucket]
    public var topProjects: [TimeBucket]
    public var buckets: [ReportBucket]

    public init(
        periodKind: ReportPeriodKind,
        startDate: Date,
        endDate: Date,
        workSeconds: TimeInterval,
        personalSeconds: TimeInterval,
        reviewSeconds: TimeInterval,
        topApps: [TimeBucket],
        topProjects: [TimeBucket],
        buckets: [ReportBucket]
    ) {
        self.periodKind = periodKind
        self.startDate = startDate
        self.endDate = endDate
        self.workSeconds = workSeconds
        self.personalSeconds = personalSeconds
        self.reviewSeconds = reviewSeconds
        self.topApps = topApps
        self.topProjects = topProjects
        self.buckets = buckets
    }

    public var totalSeconds: TimeInterval {
        workSeconds + personalSeconds + reviewSeconds
    }

    public var workRatio: Double {
        guard totalSeconds > 0 else {
            return 0
        }

        return workSeconds / totalSeconds
    }
}
