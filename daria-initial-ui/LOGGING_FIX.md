# Companion logging fix

## Confirmed defects and original flow

The reported conversation itself has no captured Gemini/tool/Firestore trace, so
we cannot prove whether that particular reply omitted the tool or hit validation.
Inspection found concrete failures on both paths:

1. Assistant.logDay called CycleStore.addCustom for every tag, even existing
   built-ins such as Fatigue and Tired. addCustom delegates to saveEditableTag,
   which rejects an already-existing name. A valid built-in symptom therefore
   returned an error before any Firestore write.
2. A plain model reply could promise a save without invoking log_day. The app
   displayed it without a write receipt.
3. CycleStore recreates Assistant when profile/log/period snapshots change.
   A consent follow-up could lose the original feeling/date from model history.
4. The previous log_day merged from the UI's cached DayLog then replaced the
   Firestore document. Loading lag/concurrent edits could lose unrelated fields.
5. write waited for acknowledgement, but only the listener updated the log array.
   Also, applying default flow=None to a symptom-only entry could end an ongoing
   period even though the user never described bleeding.

Antigravity's partial logDayCalled flag and its undefined guardFalseSave call
have been replaced by a tested execution receipt plus a secondary wording guard.
The root validation/write path is fixed; the wording guard is defense in depth.

## Current path

- LoggingConversation lives in the signed-in CycleStore. Common first-person
  feeling descriptions (including "I'm feeling really tired today") offer to log
  without invoking Gemini or writing anything. Declining or changing topic clears
  the pending offer. Explicit requests authorize logging immediately.
- A confirmation reuses the original words and reference day even after Assistant
  recreation or midnight. Each send refreshes today's local date. Sign-out/data
  deletion clears consent. Unrecognized/ambiguous confirmation asks for details.
- Assistant passes that authorized context to Gemini. log_day refuses calls without
  app-owned consent. An authorized request with no tool call gets one explicit
  retry instruction; if the model still does not execute the tool, the app reports
  that nothing was saved. No silent fallback claims a save.
- Existing built-in/custom tags are canonicalized without creating menu items.
  New custom tags are added to the menu only after the daily log commits.
- Dates use strict local Gregorian YYYY-MM-DD parsing. Today/yesterday and weekday
  references are anchored to the original request. Numeric pain and flow can only
  come from explicit user wording. Descriptive intensity is kept in the original
  text, not converted into a numeric rating. Invalid dates/ratings fail validation.
- appendCompanionLog runs a Firebase transaction: read the current server day,
  decode it (do not overwrite unreadable entries), merge only supplied fields,
  validate, and commit. Untouched symptoms, moods, flow, pain, energy and notes
  remain. Duplicate tags/identical note lines are not appended twice.
- Explicit flow changes retain the existing period-history integration. Omitted
  flow never implicitly ends a period. This does not redesign cross-device
  period-history conflict handling, which still uses the store's period snapshot.
- The acknowledged entry is upserted into store.logs, the same array used by
  CycleView's day lookup, Recent entries, month groups and search. Pending local
  snapshots are not treated as confirmed history; metadata acknowledgements are
  observed. The normal listener remains the source for subsequent remote changes.
- CompanionLogExecution owns success/failure. It cannot confirm before the writer
  returns. Repeated log calls in a turn do not repeat the write. A failed subsequent
  Gemini response cannot erase an already acknowledged save. Logging turns confirm
  using the app's receipt; failed writes say nothing was saved.

The daily-log JSON/Firestore field names are unchanged. No Firestore rules were
changed or deployed. The calendar layout, educational library/citation validator,
other tool registrations, and Firebase 11.13.0 pin remain intact.

## Automated checks

41 Foundation tests pass (10 logging regressions plus the 31 existing tests).
Logging checks cover consent/context, decline/topic changes, explicit requests,
built-in/custom tags, non-destructive merges, duplicate suppression, explicit
ratings/flow, invalid dates/ratings, DST/local dates, writer failure, acknowledgement
ordering and persistence serialization. The writer is injected in tests; its
persistence test is an in-memory database/JSON round trip, not Firestore.
Education checks still cover retrieval, unsupported questions, forged/stale
citations, untrusted URLs, and unchanged noneducational replies. Existing period
and cycle comparisons pass.

The simulator target builds with Xcode 27.1 (27A9275), iOS Simulator SDK 27.1,
Swift 5 language mode and the pinned Firebase SDK. Xcode 15.4 itself and an actual
simulator/device launch were not exercised during this fix.

```sh
swift test --package-path daria-initial-ui --scratch-path /tmp/PetalComparisonTests
xcodebuild -project daria-initial-ui/Petal.xcodeproj -scheme Petal -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/PetalBundleFix CODE_SIGNING_ALLOWED=NO build
```

## Required live Gemini / Firestore / iOS checks

Use a test account and launch daria-initial-ui/Petal.xcodeproj, Petal scheme.

1. Say "I'm feeling really tired today." Expect a consent question and no new
   daily entry. Reply "Yes, log it." Expect a successful dated confirmation only
   after the write, then open Cycle, clear history filters, and check Recent or
   today's month/day. The entry should contain Fatigue/Tired or the user's words;
   it must not invent a numeric pain rating.
2. Relaunch the app. Verify the same entry remains. In Firestore (read-only
   inspection), check users/<test uid>/logs/<local YYYY-MM-DD>, including date,
   symptoms/moods and note. A log is not a new period-start record.
3. Seed that day with another symptom, mood, pain, energy, flow and note using the
   normal editor. Ask "Log fatigue today." Verify the added item appears and every
   unrelated field remains. Confirm duplicate retries do not duplicate note lines.
4. Say "I have a headache yesterday" then "Yes, log it." Verify yesterday's local
   date. Also try an ISO date, "log pain 6/10 today", invalid date 2026-02-30 and a
   future date. Invalid/future requests must not create documents.
5. Ask to log, decline, then say "yes"; or ask an unrelated education question
   before saying "yes". Expect clarification and no stale authorized write.
   To exercise chat recreation, update a test account's profile between the offer
   and confirmation; the original pending words/date should still be available.
6. While signed in, go offline and attempt an explicit log. The transaction must
   not be reported as saved. An unavailable Gemini call may fail before reaching
   Firestore; to test the actual write rejection, use a dedicated test/emulator
   environment with writes denied for the test user. Do not alter production rules.
   After failure/reconnection, verify no new document and unchanged prior fields.
7. Check "Show all my recorded cycles", a saved-log date query, an ordinary
   reminder, and meal ideas. Confirm the original tools still act correctly.
   Ask "What is the follicular phase?" and open its validated Cleveland Clinic
   citation. Ask "Does cycle syncing cure PCOS?" and expect the unsupported message.

Limitations: English intent/date/rating handling is deliberately conservative;
complex phrasing may need clarification. Gemini still chooses/extracts tags and
must invoke log_day; the bounded retry fails honestly if it does not. One authorized
daily-log write is accepted per turn; submit different days separately. Firestore
transactions require network access. Live model tool choice, backend permissions,
transaction retries and actual iOS display/persistence require the checks above.
