# valen/cycle symptom logging

**Files changed:** `CycleStore.swift`, `LogSheet.swift`, `CycleView.swift`.

### Changes
- DayLog gains Codable and a stable UUID for saving/reloading.
- Saved day logs are stored as local JSON in Application Support and survive restarting the app.
- The logger can select a date up to today and loads existing data for that date.
- The Cycle screen shows the 20 most recent saved logs; tap a log to edit or tap the trash icon to delete it.
- Deleting all data clears saved logs and the currently active in-app selections; **demo cycle dates remain hard-coded**. This is NOT a production-complete privacy deletion implementation.
