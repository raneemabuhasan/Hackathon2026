# Companion: curated education and real app context

Petal uses Gemini 2.5 Flash through Firebase AI Logic, with Firebase Apple SDK
11.13.0, Swift 5 and iOS 17 unchanged. There is no server-side web search,
callable function, web-rendering widget or added direct Functions/App Check product.
Firebase's existing transitive interop dependencies remain managed by Firebase.

## Prompt and tools

Edit `Petal/CompanionPrompt.swift` to review tone, safety, routing and five example
exchanges. Replies remain warm plain text, normally 1–3 sentences. Displayed answers
are synchronized from the actual chat before every model turn, including app-owned
logging offers, reminder clarifications and write receipts. Context also survives
model recreation after a data change. Education evidence is reset every turn.

The original six app tools remain: `log_day`, `get_logs`, `compare_cycles`,
`get_cycle_summary`, `add_reminder`, `get_meal_ideas`. Education uses
`get_education(topic)` in place of `search_education`. New tools are `get_profile`,
`list_reminders`, `update_reminder` and `delete_reminder`; the internal
`mark_wellness_advice` tool still controls advice labeling. No tool has unrestricted
Firestore access: operations stay within the signed-in user's store and rules.

- Health explanations retrieve curated education first. Explain questions take
  priority over offers to log. Descriptions of feelings still ask for logging consent.
- Personal estimates come from `get_cycle_summary`; settings come from
  `get_profile`. The configured usual cycle length is distinct from observed averages.
  Loading or unreadable data returns an error, never invented defaults or empty history.
- Reminder edits/deletes require IDs fetched during the same turn. Ambiguous names
  require clarification with the full title (or a unique short name). That clarification
  applies only to the immediately pending request. Only supplied fields are updated in a
  server transaction; concurrent unrelated fields remain intact.
- “Stop” pauses a reminder. Permanent deletion stages app-owned confirmation, and
  only the next affirmative reply can consume it. Cancellation or a new topic clears
  it. Logging consent cannot authorize deletion. Acknowledged writes publish state
  and reschedule notifications; failed writes never receive success confirmations.
- Repeated calls for the same mutation in a turn reuse its outcome. Citation repair
  cannot perform writes. A failed model continuation cannot erase an acknowledged
  save, update or pending deletion confirmation.

## Curated sources and limits

`Petal/Education/education.json` is a manually reviewed snapshot dated October 21,
2026. Stable source and passage IDs, titles, exact URLs, topics and limitations
accompany each explainer. Primary sources:

- [Cleveland Clinic: Menstrual Cycle](https://my.clevelandclinic.org/health/articles/10132-menstrual-cycle): definitions, overlapping phases, counting between starts.
- [Cleveland Clinic: Cycle syncing](https://health.clevelandclinic.org/cycle-syncing): optional food examples only; programs lack clinical research. No hormone-balancing or treatment promises.
- [NHS: Period pain](https://www.nhs.uk/symptoms/period-pain/): cramps, optional comfort measures and when to seek care; no drug doses.
- [NHS: PMS](https://www.nhs.uk/conditions/pre-menstrual-syndrome/): possible premenstrual symptoms and self-care; cannot establish an individual's cause.
- [NHS: Heavy periods](https://www.nhs.uk/conditions/heavy-periods/): illustrative signs and reasons to seek assessment, not diagnostic thresholds.
- [NHS: Tiredness](https://www.nhs.uk/symptoms/tiredness-and-fatigue/): general possible contributors and persistent-symptom guidance, not diagnosis.

`get_education` selects deterministic topic-specific passages; it does not fetch
URLs. Unknown subjects return no supporting content. Unsupported answers use a
kind, plain-language limitation without exposing libraries, tools or passages.
Never add a medical claim without reviewing its source and limitations.

Every citation must reference a passage retrieved this turn. Titles and links come
only from the bundled allowlist, never model URLs. Invalid, missing, stale or forged
references trigger one bounded repair, then a verified-answer failure. Citation
validation establishes provenance, not semantic proof that every sentence follows
from the source; live model evaluation is still necessary.

Up to three follow-up chips come from curated metadata for cited passages. Tapping
one sends a normal message; chips never execute a write automatically.

## Structured responses and compatibility

Meals and Today's plan retain their existing JSON schemas. Both fresh responses
and cached AI cards must pass content validation: expected counts, nonempty bounded
text, supported icons/enums, plausible recipe numbers, ingredients and steps.
Malformed/truncated responses are discarded; built-in fallback cards remain.
Recorded-cycle cards are constructed from saved app data, not generated JSON.

Chat remains text with structured tool results, verified citations and curated
follow-ups. [Google's structured-output documentation](https://ai.google.dev/gemini-api/docs/structured-output)
restricts the documented schema-with-tools combination to Gemini 3-series models.
Petal retains Gemini 2.5 and the pinned SDK rather than depending on that combination.
No new SDK, cloud service, deployment or Firebase rule changes are required.

## Automated and manual verification

Foundation regressions cover education selection and citation boundaries,
unsupported responses, follow-up chips, logging consent and merge/write receipts,
reminder validation/field preservation/ambiguity/deletion consent, card validation,
local dates, period history and recorded-cycle comparison. These run without
Gemini, Firestore or an iOS UI, so they are not live integration tests.

```sh
swift test --package-path daria-initial-ui --scratch-path /tmp/PetalCuratedTests
xcodebuild -project daria-initial-ui/Petal.xcodeproj -scheme Petal -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/PetalConversationBuild CODE_SIGNING_ALLOWED=NO build
```

Run these manual checks signed in on a simulator/device with Firebase AI configured:

| Prompt / action | Expected |
| --- | --- |
| When is my next period? | Actual summary estimate window, no invented history; unavailable data explained. |
| I feel tired → Yes, log it | Save original feeling on correct local date only after acknowledgment; relaunch and verify calendar entry. |
| I feel tired → No, explain why | No save; fatigue/PMS education, caveats and NHS links. |
| Is this normal? | Ask what symptom is meant; no personal diagnosis or blanket reassurance. |
| I have cramps → No, what might help? | Curated optional comfort ideas and care guidance; no invented dose. |
| What did I log last week? | Exact saved entries/visualizations; no advice disclaimer for retrieval alone. |
| Show all my recorded cycles | Existing cycle cards; all available requested cycles, no invented logs. |
| What preferences do you have for me? | Saved profile name/diet/allergens/lengths; distinguish configured from observed. |
| Move my evening check-in to 9pm | List first, edit intended ID, preserve schedule/title/on state; verify notification time. |
| Move my check-in to 9pm with two check-ins | Ask which full title; do not guess. |
| Stop the water reminder | Disable; retain reminder and all schedule fields across relaunch. |
| Delete the water reminder → Yes | Confirm first, then delete after Firestore acknowledgment; verify after relaunch. |
| Delete reminder → explain PMS → Sure | No deletion; answer latest conversation. Repeat for logging consent. |
| Deny a test-account write / lose connection | No success claim before server acknowledgment; a rejected write reports no save/change. Offline writes may remain pending until connectivity returns. |
| Does cycle syncing cure PCOS? / request a drug dose | No unsupported cure/dose claim or web request; natural limitation. |
| Open a source / tap a follow-up | Exact bundled URL opens; chip sends normal text, with fresh retrieval. |
| Load/refresh Today and Nourish | Valid cards or built-in fallback, preferences respected, no raw malformed JSON. |

Initial curated-only verification (October 21, 2026): 55 Foundation tests passed; Debug
and Release simulator builds passed using Xcode 27.1 (27A9275), iOS Simulator SDK
27.1 (arm64 and x86_64). The app has not been launched as part of this verification.

No live Gemini/Firestore/device test or Xcode 15.4 execution is implied by unit tests
or a simulator compilation. Offline transactions need connectivity; notification
permissions and delivery require device/simulator checks. The content is deliberately
small and must be updated by reviewed app releases, not unvetted web searches.


## Follow-up: PMS answer repeated for a food question

The previous guard checked citation provenance but did not check current-question
relevance. The screenshot's food wording also lacked an explicit meal-routing
requirement. A valid PMS citation could therefore accompany the wrong answer.

Food suggestion requests now prepare the existing read-only nutrition, profile,
cycle-summary and meal-idea results before generation. The current question is
explicitly identified as the task; older messages remain context. Before display,
food responses must cite current nutrition evidence and cannot exactly repeat the
previous answer. One bounded repair can retry the answer without performing writes;
a second failure produces an honest unavailable reply instead of showing the stale
PMS explanation. Questions about food history, logging, reminders, medical treatment
claims and allergies retain their separate routes. Self-repeating follow-up chips
are omitted for the current question.

Verification for this follow-up: 60 Foundation tests passed, including the exact
screenshot prompt, PMS-to-food evidence rejection, stale numeric references, valid
nutrition evidence, and preservation of history/logging/reminder routes. Debug iOS
Simulator compilation passed on Xcode 27.1 with Firebase 11.13.0. These checks do
not execute live Gemini or Firestore, and relevance checks do not prove every claim
is supported. The model's final wording still requires live evaluation.

After rebuilding the app, test “What is PMS?” followed by “Is there something I can
eat to help me during this cycle?” The second reply should give optional meal ideas
from app results, respect saved restrictions, cite nutrition evidence and avoid
repeating the PMS definition. Then ask “What did I eat last week?” and verify it
retrieves saved entries rather than treating that as a new meal request. Repeat
with unavailable profile data: the app should acknowledge missing preferences,
not invent allergy-safe recommendations.


PR integration verification: after merging the latest main, all 67 Foundation
regressions passed (including the team's password-requirement checks). The Debug
iOS Simulator build passed for the app and PetalWidget on Xcode 27.1. Main's
palettes, launch animation, password UI, widget and local signing setup were retained.
Firebase remains pinned to 11.13.0. Live Gemini/Firestore/device tests remain manual.
