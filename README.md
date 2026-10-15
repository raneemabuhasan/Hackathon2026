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

Swift packages (Firebase, GoogleSignIn, Lottie) download automatically the first time Xcode opens the project. Their versions are pinned so they still build on Xcode 15.4: Firebase 11.x, GoogleSignIn 9.0.x, Lottie 4.5.x and swift-protobuf 1.33.1. Newer releases of these need Xcode 16+, so don't upgrade them without checking with the team.

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
