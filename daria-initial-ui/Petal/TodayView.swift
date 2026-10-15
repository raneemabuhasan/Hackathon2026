import SwiftUI

struct TodayView: View {
    @Environment(CycleStore.self) private var store
    @State private var managingPeriods = false

    var body: some View {
        Page {
            Eyebrow(text: store.today.formatted(date: .complete, time: .omitted))
            DisplayTitle(before: "Your daily ", accent: "check-in")
            CycleRing().frame(height: 240).card()
            Button(store.starts.isEmpty ? "Period started? Record a date" : "Record / edit period dates") {
                managingPeriods = true
            }.buttonStyle(.borderedProminent)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Next period estimate")
                if let prediction = store.prediction {
                    Text("\(store.fmt(prediction.windowStart)) – \(store.fmt(prediction.windowEnd))")
                        .font(.title2)
                    Text("Based on \(prediction.completedLengths.count) recorded start-to-start intervals. Observed lengths: \(prediction.completedLengths.min() ?? 0)–\(prediction.completedLengths.max() ?? 0) days.")
                    Text("A planning estimate, not a confirmed date or a fertility/contraception tool. Missing start dates can distort this estimate.").font(.caption)
                    if prediction.windowEnd < store.today {
                        Text("No new period start is logged yet. Predicted dates are estimates and may shift. Update your log whenever your period starts.")
                    }
                } else {
                    Text("Record at least three period start dates to estimate the next window. You can log symptoms now.")
                }
            }.card()
            Button("Log symptoms, mood or flow") { store.showLog = true }
                .buttonStyle(.borderedProminent)
            Text("Cycle compares your recorded symptoms. Nourish contains a meal catalog. AI assistance is awaiting integration.")
                .font(.caption).foregroundStyle(Palette.inkSoft)
        }
        .sheet(isPresented: $managingPeriods) { PeriodHistoryView().environment(store) }
    }
}

struct CycleRing: View {
    @Environment(CycleStore.self) private var store
    var body: some View {
        ZStack {
            Circle().stroke(Palette.blush, lineWidth: 14).padding(16)
            if let prediction = store.prediction, store.cycleDay > 0 {
                Circle().trim(from: 0, to: min(1, Double(store.cycleDay) / Double(prediction.typicalLength)))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(16)
            }
            VStack(spacing: 6) {
                if store.cycleDay > 0 {
                    Text("Cycle day").font(.caption)
                    Text("\(store.cycleDay)").font(.system(size: 58, design: .serif))
                    if let prediction = store.prediction {
                        Text("Typical recorded length: \(prediction.typicalLength) days").font(.caption)
                    } else { Text("More history needed for an estimate").font(.caption) }
                } else {
                    Text("Start your history").font(.title2)
                    Text("Record your first period start date").font(.caption)
                }
            }
        }.accessibilityElement(children: .combine)
    }
}
