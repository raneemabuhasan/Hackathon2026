# Petal — Hackathon 2026

The shared app is Daria’s Petal boilerplate in `daria-initial-ui/`.
`MenstrualCycleWellnessCompanion/` is the earlier starter project; use Petal for new app work.

## Run locally

1. Clone this repository, or pull the latest `main` after this compatibility PR is merged.
2. Open `daria-initial-ui/Petal.xcodeproj` in Xcode.
3. Select the **Petal** scheme and an installed iPhone simulator running iOS 17 or later.
4. Press **Command-R** to build and run.

Xcode 15.4 is the compatibility baseline. The deployment target is iOS 17.0.
Newer Xcode versions should be checked by teammates; compatibility with every version is not guaranteed.
There is no separate test project. Simulator runs do not require an Apple development team; physical-device runs require signing setup.

Swift packages (Firebase, GoogleSignIn, Lottie) download automatically the first time Xcode opens the project. Their versions are pinned so they still build on Xcode 15.4: Firebase exactly 11.13.0, GoogleSignIn 9.0.x, Lottie 4.5.x and swift-protobuf exactly 1.33.1. Newer releases need Xcode 16+ (Firebase 11.14+ uses Swift 6 syntax even though its package says 5.9), so don't upgrade them without checking with the team.

The backend is Firebase project `hackathon-2026-8f327`. Firestore security rules live in `firestore.rules` at the repo root; deploy changes with `firebase deploy --only firestore`.

## Team workflow

Create a feature branch from updated `main`, make and test changes, then push and open a pull request.
Keep the shared project file tracked. Add new Swift files to the Petal target through Xcode so their project references are committed too.
Do not commit personal Xcode settings or build output. Discuss project-format or minimum-iOS upgrades before accepting them.

For compatibility checks, report your Xcode version, simulator iOS version, and whether the app launches. If it fails, include the first compiler error and file/line.

## Build check

```sh
xcodebuild -project daria-initial-ui/Petal.xcodeproj -scheme Petal -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/PetalBuild CODE_SIGNING_ALLOWED=NO build
```

The simulator build checks compilation; manually exercise the tabs and logging flow after launch.

## Calendar and onboarding checks

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
