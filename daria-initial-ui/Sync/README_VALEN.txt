# valen/cycle symptom logging

**Files changed:** `CycleStore.swift`, `LogSheet.swift`, `CycleView.swift`.

### Changes
- The logger can select a date up to today and loads existing data for that date.
- Saving replaces that day's entry. Logs are stored in Firestore under users/{uid}/logs/{yyyy-MM-dd}, so they sync to the signed-in account.
- The Cycle screen shows the 20 most recent saved logs; tap a log to edit or tap the trash icon to delete it.
- "Delete all my data" lives in Settings (tap the avatar on Today) and erases every log and preference in the account.
