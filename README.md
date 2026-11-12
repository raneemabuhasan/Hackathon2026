# Sync — Hackathon 2026

The shared app is Daria’s Sync boilerplate in `daria-initial-ui/`.
`MenstrualCycleWellnessCompanion/` is the earlier starter project; use Sync for new app work.

## Run locally

1. Clone this repository, or pull the latest `main` after this compatibility PR is merged.
2. Open `daria-initial-ui/Sync.xcodeproj` in Xcode.
3. Select the **Sync** app scheme and an installed iPhone simulator running iOS 17 or later.
4. Press **Command-R** to build and run.

Xcode 15.4 is the compatibility baseline. The deployment target is iOS 17.0.
Newer Xcode versions should be checked by teammates; compatibility with every version is not guaranteed.
There is no separate test project. Simulator runs do not require an Apple development team; physical-device runs require signing setup.

Swift packages (Firebase, GoogleSignIn, Lottie) download automatically the first time Xcode opens the project. Their versions are pinned so they still build on Xcode 15.4: Firebase exactly 11.13.0, GoogleSignIn 9.0.x, Lottie 4.5.x and swift-protobuf exactly 1.33.1. Newer releases need Xcode 16+ (Firebase 11.14+ uses Swift 6 syntax even though its package says 5.9), so don't upgrade them without checking with the team.

The backend is Firebase project `hackathon-2026-8f327`. Firestore security rules live in `firestore.rules` at the repo root; deploy changes with `firebase deploy --only firestore`.

## Local phone signing

The app is registered under Raneem's **Individual** Apple Developer account.
Shared defaults in `daria-initial-ui/Signing.xcconfig` use her official team and IDs:
`com.raneem.sync` (app) and `com.raneem.sync.SyncWidget` (widget).
Raneem does not need any local overrides for development or release builds.

Teammates building on their own phones use their own Apple Account/signing team
and a unique development bundle ID. One-time setup:

1. From the repository root, copy the example if you do not already have a local file:
   `cp daria-initial-ui/Local.xcconfig.example daria-initial-ui/Local.xcconfig`.
   If the file already exists, update it using the example instead of overwriting it.
2. Set `SYNC_DEVELOPMENT_TEAM` to your own Team ID and
   `SYNC_APP_BUNDLE_IDENTIFIER` to a unique ID such as `com.alex.sync.dev`.
   Replace old `DEVELOPMENT_TEAM` or `PETAL_WIDGET_BUNDLE_IDENTIFIER` entries with
   these new variable names. The widget ID is derived automatically by appending
   `.SyncWidget`; no separate widget override is needed.
3. Sign into your own Apple Account in Xcode > Settings > Accounts. Open
   `daria-initial-ui/Sync.xcodeproj`, select the app scheme (**Sync**), select your
   connected phone, and press Command-R. Complete any device trust or Developer
   Mode setup Xcode requests. Automatic signing remains enabled for both targets.
4. Commit your code changes normally. `Local.xcconfig` is ignored by Git; verify
   with `git check-ignore -v daria-initial-ui/Local.xcconfig`. Do not force-add it.

Keep personal Team IDs and bundle IDs out of the targets' Signing & Capabilities
fields and Build Settings; edit only `Local.xcconfig`. Keep the project file tracked:
legitimate changes such as adding source files still belong in commits. Review its
diff so personal signing changes are not included.

Local overrides apply to Debug **and Release** on that Mac. Release uploads for the
official app are made by Raneem using the official defaults. This setup grants no
access to her developer account. Simulator-only work does not require personal
signing overrides. Separate development IDs may need additional Firebase,
authentication, or Apple capability configuration; a successful UI build does not
verify those integrations. Test merged official builds through TestFlight.

## Team workflow

Create a feature branch from updated `main`, make and test changes, then push and open a pull request.
Keep the shared project file tracked. Add new Swift files to the Sync target through Xcode so their project references are committed too.
Do not commit personal Xcode settings or build output. Discuss project-format or minimum-iOS upgrades before accepting them.

For compatibility checks, report your Xcode version, simulator iOS version, and whether the app launches. If it fails, include the first compiler error and file/line.

## Build check

```sh
xcodebuild -project daria-initial-ui/Sync.xcodeproj -scheme Sync -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/SyncBuild CODE_SIGNING_ALLOWED=NO build
```

The simulator build checks compilation; manually exercise the tabs and logging flow after launch.

## Calendar and onboarding checks

- Tap a calendar date once: it becomes selected without opening a sheet. Tap that
  selected date again to open period controls. Tapping a different date only selects it.
- Finish onboarding with a known period start. Cycle must show that start without
  entering it again; no end date is inferred.
- Profiles without `periodRecords` use their onboarding start as the initial
  calendar record. An explicitly saved empty history stays empty after reload.
- Edit or delete that calendar record, then relaunch. Comparison must use the
  saved history without adding the old onboarding date back.
- Select a past date in Cycle and press +. Log date must match the selection and
  load any existing entry for that day. On other tabs, + opens today's log.
- Select a future calendar date. The + button is disabled for that date.
- Change the most recent period start in Settings. Cycle and comparison must
  reflect the corrected date; invalid or overlapping dates must show an error.

## Companion

Curated education, profile and reminder tools require no web service. See [EDUCATION.md](daria-initial-ui/EDUCATION.md) for behavior and manual acceptance checks.

## Home screen widget checks

The `SyncWidget` extension adds a "Quick log" widget in small, medium and large sizes. It shows no cycle or
health details, and tapping it opens `petal://log`.

- Add the widget from the home screen gallery (search "Sync"). Each size shows
  only the fig from the Sync logo with a + inside it, and "Log today".
- Signed in: tapping it opens today's log sheet, even if Cycle has a past date selected.
- Signed out: tapping it opens sign-in; after signing in (and onboarding for new
  accounts) today's log opens.
- From a terminal: `xcrun simctl openurl booted petal://log`.

## Project name

Open `daria-initial-ui/Sync.xcodeproj`. The app and widget sources now live in
`Sync/` and `SyncWidget/`; the widget ID defaults to `com.raneem.sync.SyncWidget`.
The main app ID remains `com.raneem.sync`. Teammates' local signing setup is
unchanged; their widget ID automatically ends in `.SyncWidget`. Reopen Xcode
after pulling this rename or editing local signing overrides. Existing development
widgets may need to be removed and added again.

The existing `petal://log` link and saved-data keys are intentionally retained for
compatibility. Firebase's downloaded configuration is also retained; renaming the
project does not re-register backend services.
