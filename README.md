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
No separate test project or external packages are required. Simulator runs do not require an Apple development team; physical-device runs require signing setup.

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
