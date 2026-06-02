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

Release builds are ad hoc signed and not notarized. On first launch, macOS may require right-clicking `Worklog.app` and choosing `Open`.

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

The release workflow runs tests, packages `Worklog.app`, ad hoc signs it, zips it, writes a checksum, and uploads both files to the GitHub release.

## Defaults

The app ships with editable default categories and rules for common work, personal, review, and privacy cases. Users can add, remove, or edit rules, projects, categories, and ignore patterns in the app.

## License

MIT
