# Worklog

Worklog is a local macOS menu bar app for tracking active-window time and reviewing how the day was spent.

## What It Tracks

- frontmost app name
- active window title
- Chrome active tab URL and title when Apple Events permission is granted
- idle time, so inactive periods are not counted

Chrome incognito windows are detected before tab URL/title collection and treated as private/ignored.

## Local Storage

Worklog stores data locally in SQLite:

```text
~/Library/Application Support/Worklog/worklog.sqlite
```

The app does not send tracked activity to a server.

Ignored activity is not persisted as detailed activity rows.

## Permissions

Worklog may request:

- Accessibility permission, used to read active window titles.
- Automation/Apple Events permission for Chrome, used to read the active tab URL and title.

Without those permissions, the app can still track app-level activity, but classification is less specific.

## Build

```sh
swift test
swift build -c release --product Worklog
```

## Download And Install

Download the latest `Worklog.app.zip` from [GitHub Releases](https://github.com/0xIvan/WorkLog/releases/latest), unzip it, and move `Worklog.app` to `/Applications`.

You can also install the latest release from Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/0xIvan/WorkLog/main/scripts/install-release.sh | bash
```

Release notes indicate whether a build is notarized. The release workflow is configured for Developer ID signing and notarization once the required Apple secrets are added. Older ad hoc signed releases may require right-clicking `Worklog.app` and choosing `Open` on first launch.

## Local Package And Install

```sh
scripts/install-app.sh
```

The install script packages the app, signs it, copies it to `/Applications/Worklog.app`, and opens it.

By default it uses a local signing identity named `Worklog Local Code Signing` if one exists. Override it with:

```sh
WORKLOG_CODE_SIGN_IDENTITY="Your Identity Name" scripts/install-app.sh
```

If no signing identity is found, the script uses ad hoc signing.

## Releasing

GitHub Releases are created automatically when a version tag is pushed:

```sh
git tag v0.1.0
git push origin v0.1.0
```

After the required secrets are configured, the release workflow runs tests, packages `Worklog.app`, Developer ID signs it, submits it to Apple's notary service, staples the notarization ticket, zips it, writes a checksum, and uploads both files to the GitHub release.

### Release Secrets

Notarized GitHub releases require these repository secrets:

```text
APPLE_CERTIFICATE_BASE64
APPLE_CERTIFICATE_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
```

`APPLE_CERTIFICATE_BASE64` must be a base64-encoded `.p12` export of a Developer ID Application certificate:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

`APPLE_APP_SPECIFIC_PASSWORD` is an app-specific password for the Apple ID used with the notary service.

If any release secret is missing, tag-triggered release builds fail instead of publishing an unnotarized app.

## Defaults

The app ships with editable default categories and rules for common work, personal, review, and privacy cases. Users can add, remove, or edit rules, projects, categories, and ignore patterns in the app.

## License

MIT
