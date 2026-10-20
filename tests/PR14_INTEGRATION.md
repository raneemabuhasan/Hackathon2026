# PR #14 integration with main

Integration branch: `integrate/pr14-main`.
Parents: PR #14 `2fadeb3`, main `62ec023` (includes calendar sheet PR #17).

## Preserved behavior

- Main: calendar month picker, period controls sheet, past-period editor, cycle insights,
  symptom comparison, account-scoped Firestore storage, selected-date logging,
  and save failure feedback.
- PR #14: searchable month-grouped history, field/date filters and suggestions,
  saved-log previews, calendar log indicators, mood/symptom rename, emoji selection,
  removal and reordering, and bounded prediction-bar geometry.
- Calendar-day taps open main's period sheet with the saved-log preview inside it.
  Opening the full log dismisses that sheet before presenting the log preview.
  The + button opens editing directly; history rows open a preview with an Edit button.

## Period storage and corrections

Flow entries create durable `users/{uid}/periods/{UUID}` records. Date edits keep
that UUID. Deleting a daily log does not delete or reconstruct a corrected period.
An ongoing period can be ended on a later selected date without logging that date first.
An explicit None entry ends an ongoing period on the prior day (or the last known
flow when the gap exceeds seven days). Completed, explicitly edited periods are
not truncated by None entries. Flow after a ten-day gap closes an open record
and starts another. Main's nearby historical-flow grouping is retained.
Log and period changes are committed together in one Firestore batch.

The profile baseline and period records come from the signed-in user's Firestore
paths. The PR's unscoped UserDefaults history, baseline, and corrections are never
loaded into an account. They cannot be safely assigned to a particular user;
old local-only corrections must be re-entered. The obsolete values are retained
until explicit Delete all my data, which removes them along with the user's
server records and profile. No production data was migrated by the review tools.

## Automated checks

```sh
swift test --package-path daria-initial-ui --scratch-path /tmp/PetalIntegrationTests
swiftc daria-initial-ui/Petal/PeriodHistory.swift tests/PeriodHistoryChecks.swift -o /tmp/period-checks
/tmp/period-checks
swiftc daria-initial-ui/Petal/PeriodHistory.swift tests/RecordedCycleChecks.swift -o /tmp/cycle-checks
/tmp/cycle-checks
xcodebuild -project daria-initial-ui/Petal.xcodeproj -scheme Petal \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PetalPR14Review CODE_SIGNING_ALLOWED=NO build
```

## Validation results (2026-10-19)

- Xcode 27.1 simulator build: passed (arm64 and x86_64).
- Swift package: 20 tests passed, zero failures (11 period regressions, 9 comparisons).
- Standalone PeriodHistoryChecks and RecordedCycleChecks: passed.
- Fresh iPhone 15 Pro / iOS 17.5 simulator: installed and launched to the sign-in
  screen successfully. No account was signed in and no production data was written.
- Full authenticated UI and Firebase persistence checks below remain unverified.
- Build retains existing nonfatal unused-result warnings in Firestore calls.

## Signed-in acceptance checks

Use disposable test accounts, not personal health data. These checks remain manual:

1. Search a symptom, mood, flow and private note across more than 20 entries;
   combine each with date filters and clear the filters. Confirm notes stay hidden
   until the full log preview opens.
2. Tap a logged calendar date, view its preview and full log, then Edit. Use + on a
   different selected date; verify the correct date and existing fields load.
3. Rename, reorder, remove and add tags; save and relaunch. Historic labels remain
   visible when reopening older entries.
4. Log flow yesterday, then end the period today in the calendar sheet. Correct its
   start/end, delete the original first daily log, and relaunch. Dates must persist.
5. Sign out of account A and into B on the same simulator. A's period history,
   baseline, tags and corrections must not appear in B.
6. Delete all data in the test account, relaunch and onboard again. Confirm the
   previous baseline and periods do not return.
7. Verify period editing, past-period insertion and symptom comparisons still work.
8. Reject/disconnect a save and confirm an error rather than a success toast or a
   partial calendar update. Restore connectivity before repeating persistence checks.

The repository's existing Firestore rules must be deployed for the `/periods`
collection. This integration does not change those rules or deploy any backend.
