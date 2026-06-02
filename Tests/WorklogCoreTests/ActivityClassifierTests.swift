import Testing
import WorklogCore

@Suite
struct ActivityClassifierTests {
    private let classifier = ActivityClassifier()
    private let rules = SeedData.rules

    @Test
    func cursorIsWork() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Cursor", title: "Example Project"),
            rules: rules
        )

        #expect(result.kind == .work)
        #expect(result.projectID == nil)
    }

    @Test
    func localhostChromeIsWork() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Google Chrome",
                title: "Local app",
                url: "http://localhost:5173/dashboard"
            ),
            rules: rules
        )

        #expect(result.kind == .work)
    }

    @Test
    func finderIsPersonal() {
        let result = classifier.classify(snapshot: snapshot(appName: "Finder"), rules: rules)

        #expect(result.kind == .personal)
    }

    @Test
    func chromeExtensionPagesAreIgnored() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Google Chrome",
                title: "Extension",
                url: "chrome-extension://example/options.html"
            ),
            rules: rules
        )

        #expect(result.kind == .ignored)
    }

    @Test
    func privateSnapshotIsIgnored() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", title: "Example", isPrivate: true),
            rules: []
        )

        #expect(result.kind == .ignored)
    }

    @Test
    func unknownChromeNeedsReview() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", title: "Search"),
            rules: rules
        )

        #expect(result.kind == .review)
    }

    private func snapshot(
        appName: String,
        title: String = "",
        url: String? = nil,
        isPrivate: Bool = false
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            appName: appName,
            bundleIdentifier: appName == "Google Chrome" ? "com.google.Chrome" : "test.\(appName)",
            processIdentifier: 1,
            windowTitle: title,
            url: url,
            source: url == nil ? .macOS : .chrome,
            isPrivate: isPrivate
        )
    }
}
