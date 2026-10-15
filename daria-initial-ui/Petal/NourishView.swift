import SwiftUI

struct NourishView: View {
    @Environment(CycleStore.self) private var store
    @State private var phase: Phase?

    private var selected: Phase { phase ?? store.currentPhase }

    var body: some View {
        @Bindable var store = store
        let all = CycleStore.meals[selected] ?? []
        let meals = store.meals(for: selected)

        Page {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Nourish")
                DisplayTitle(before: "Food ideas for ", accent: title)
            }

            HStack(spacing: 2) {
                ForEach(Phase.allCases) { p in
                    Button { phase = p } label: {
                        Text(p.name + (p == store.currentPhase ? " ·" : ""))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(p == selected ? Color.white : Palette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(p == selected ? Palette.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Palette.surface, in: Capsule())
            .shadow(color: Palette.berry.opacity(0.07), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.2), value: selected)

            Text("Browse the meal catalog. Phase-based personalization is awaiting team integration; this selection does not identify your current biological phase.").font(.system(size: 13.5)).foregroundStyle(Palette.inkSoft)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Your preferences", trailing: "filters meals")
                FlowLayout {
                    ForEach(CycleStore.dietOptions, id: \.self) { d in
                        Chip(label: d, selected: store.diets.contains(d), small: true) { toggle(&store.diets, d) }
                    }
                }
                Eyebrow(text: "Avoid")
                FlowLayout {
                    ForEach(CycleStore.allergenOptions, id: \.self) { a in
                        Chip(label: a, selected: store.avoid.contains(a), small: true) { toggle(&store.avoid, a) }
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Meal ideas", trailing: "\(meals.count) of \(all.count) match")
                if meals.isEmpty {
                    Text("Nothing matches these filters yet. Try removing one.")
                        .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(meals) { meal in mealRow(meal) }
            }
            .card()

            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Grocery list", trailing: "\(store.grocery.filter { !$0.done }.count) to buy")
                if store.grocery.isEmpty {
                    Text("Add items from meal ideas.").font(.system(size: 13)).foregroundStyle(Palette.inkSoft).padding(.top, 6)
                }
                ForEach($store.grocery) { $item in
                    Button { item.done.toggle() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? Palette.accent : Palette.inkFaint)
                            Text(item.name).strikethrough(item.done).opacity(item.done ? 0.5 : 1)
                            Spacer()
                        }
                        .font(.system(size: 14))
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Palette.line)
                }
            }
            .card()

            Text("General nutrition ideas, not treatment. No food is promised to relieve pain or balance hormones.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
        }
    }

    private var title: String { "your choice" }

    private func toggle(_ set: inout Set<String>, _ value: String) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func mealRow(_ meal: Meal) -> some View {
        let added = store.isOnList(meal)
        return HStack(alignment: .center, spacing: 14) {
            Text(String(meal.name.prefix(1)))
                .font(.display(28))
                .foregroundStyle(Palette.wine)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: selected.artColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(meal.name).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 6)
                    Button(added ? "Added" : "+ List") { store.toggleList(meal) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(added ? Palette.accentSoft : Palette.surface, in: Capsule())
                        .overlay(Capsule().stroke(added ? Color.clear : Palette.line))
                        .buttonStyle(.plain)
                }
                Text(meal.why).font(.system(size: 12.5)).foregroundStyle(Palette.inkSoft)
                FlowLayout(spacing: 4) {
                    ForEach(meal.diets, id: \.self) { d in
                        Text(d).font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Palette.surface2, in: Capsule())
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
    }
}
