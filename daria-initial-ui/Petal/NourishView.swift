import SwiftUI

@MainActor
struct NourishView: View {
    @Environment(CycleStore.self) private var store
    @State private var phase: Phase?
    @State private var openMeal: Meal?
    @State private var confirmingClearGrocery = false
    @State private var clearingGrocery = false
    @State private var groceryClearError: String?

    private var selected: Phase { phase ?? store.currentPhase }

    var body: some View {
        let key = store.mealKey(selected)
        let generated = store.aiMeals[key]
        let loading = store.mealsLoading.contains(key)
        let meals = store.shownMeals(for: selected)

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

            Text(selected.blurb).font(.system(size: 13.5)).foregroundStyle(Palette.inkSoft)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Your preferences", trailing: "filters meals")
                FlowLayout {
                    ForEach(CycleStore.dietOptions, id: \.self) { d in
                        Chip(label: d, selected: store.diets.contains(d), small: true, icon: AnyView(FoodCategoryIcon(category: d))) { store.toggleDiet(d) }
                    }
                }
                Eyebrow(text: "Avoid")
                FlowLayout {
                    ForEach(CycleStore.allergenOptions, id: \.self) { a in
                        Chip(label: a, selected: store.avoid.contains(a), small: true, icon: AnyView(FoodCategoryIcon(category: a))) { store.toggleAvoid(a) }
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Meal ideas").font(.system(size: 15, weight: .semibold))
                    if generated != nil {
                        Text("AI").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.accentSoft, in: Capsule())
                    }
                    Spacer()
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { Task { await store.loadMeals(for: selected, refresh: true) } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .accessibilityLabel("New meal ideas")
                    }
                }
                if loading && generated == nil {
                    Text("Cooking up recipes for you…")
                        .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    if generated == nil && store.mealsFailed.contains(key) {
                        Text("Couldn't fetch new recipes right now, so here are some favourites.")
                            .font(.caption).foregroundStyle(Palette.inkFaint)
                    }
                    if meals.isEmpty {
                        Text("Nothing matches these filters yet. Try removing one.")
                            .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    // Extra space between meals so each one's tags don't run into the next title.
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(meals) { meal in mealRow(meal) }
                    }
                }
            }
            .card()
            .animation(.easeOut(duration: 0.2), value: loading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    SectionHeader(title: "Grocery list", trailing: "\(store.grocery.filter { !$0.done }.count) to buy")
                    if clearingGrocery {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Clear list") { confirmingClearGrocery = true }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .buttonStyle(.plain)
                            .disabled(store.grocery.isEmpty)
                            .opacity(store.grocery.isEmpty ? 0.4 : 1)
                            .accessibilityLabel("Clear grocery list")
                    }
                }
                if store.grocery.isEmpty {
                    Text("Add items from meal ideas.").font(.system(size: 13)).foregroundStyle(Palette.inkSoft).padding(.top, 6)
                }
                ForEach(store.grocery) { item in
                    Button { store.toggleGrocery(item) } label: {
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

            Text("General nutrition ideas, not treatment. No food is promised to relieve pain or balance hormones. AI recipes can get allergens wrong, so check labels.")
                .font(.caption).foregroundStyle(Palette.inkFaint)
        }
        .confirmationDialog("Clear your grocery list?", isPresented: $confirmingClearGrocery, titleVisibility: .visible) {
            Button("Clear all items", role: .destructive) {
                clearingGrocery = true
                Task {
                    defer { clearingGrocery = false }
                    do { try await store.clearGroceryList() }
                    catch { groceryClearError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all grocery items, including checked items.")
        }
        .alert("Couldn't clear the entire grocery list", isPresented: Binding(
            get: { groceryClearError != nil }, set: { if !$0 { groceryClearError = nil } }
        )) {
            Button("OK", role: .cancel) { groceryClearError = nil }
        } message: {
            Text(groceryClearError ?? "Please try again.")
        }
        .task(id: key) { await store.loadMeals(for: selected) }
        .sheet(item: $openMeal) { meal in
            RecipeSheet(meal: meal, phase: selected)
                .environment(store)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Palette.bg)
        }
    }

    private var title: String {
        if selected == store.currentPhase { return "right now" }
        return selected == .menstrual ? "your period" : "the \(selected.name.lowercased()) phase"
    }

    private func mealRow(_ meal: Meal) -> some View {
        let added = store.isOnList(meal)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Button { openMeal = meal } label: {
                        Text(meal.name).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
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
                if let minutes = meal.minutes {
                    Button { openMeal = meal } label: {
                        Label("\(minutes) min · view recipe", systemImage: "clock")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
                FlowLayout(spacing: 4) {
                    ForEach(meal.diets, id: \.self) { d in
                        FoodCategoryIcon(category: d)
                            .frame(width: 14, height: 14)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Palette.surface2, in: Capsule())
                            .foregroundStyle(Palette.accent)
                            .accessibilityLabel(d)
                            .help(d)
                    }
                }
            }
        }
    }
}

/// Full recipe for one meal idea.
@MainActor
struct RecipeSheet: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    let phase: Phase

    var body: some View {
        let added = store.isOnList(meal)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Eyebrow(text: "Recipe · \(phase.name)")
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Palette.surface, in: Circle())
                            .overlay(Circle().stroke(Palette.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(meal.name).font(.display(30)).fixedSize(horizontal: false, vertical: true)
                    Text(meal.why).font(.system(size: 14)).foregroundStyle(Palette.inkSoft)
                    HStack(spacing: 14) {
                        if let minutes = meal.minutes { Label("\(minutes) min", systemImage: "clock") }
                        if let servings = meal.servings { Label("Serves \(servings)", systemImage: "person.2") }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Ingredients")
                    ForEach(Array((meal.ingredients.isEmpty ? meal.items : meal.ingredients).enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Palette.pink).frame(width: 6, height: 6).padding(.top, 7)
                            Text(item).font(.system(size: 14))
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Method")
                    if meal.steps.isEmpty {
                        Text("Tap ↻ on Nourish for AI recipes with full steps.")
                            .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                    }
                    ForEach(Array(meal.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Palette.accent, in: Circle())
                            Text(step).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()

                Button { store.toggleList(meal) } label: {
                    Text(added ? "Remove from grocery list" : "Add ingredients to grocery list")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(added ? Palette.accent : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(added ? Palette.accentSoft : Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Text(meal.steps.isEmpty
                     ? "General nutrition ideas, not treatment."
                     : "AI-generated recipe. Check labels for allergens. General nutrition ideas, not treatment.")
                    .font(.caption).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
    }
}

/// Shared artwork for the filter pills and meal badges; category strings stay unchanged.
private struct FoodCategoryIcon: View {
    let category: String

    var body: some View {
        ZStack {
            switch category {
            case "vegetarian": Image(systemName: "carrot.fill").resizable().scaledToFit()
            case "vegan": Image(systemName: "leaf.fill").resizable().scaledToFit()
            case "fish": Image(systemName: "fish.fill").resizable().scaledToFit()
            case "gluten", "gluten-free":
                FoodGlyph(kind: .wheat).stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            case "dairy", "dairy-free":
                FoodGlyph(kind: .milk).stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            case "nuts":
                FoodGlyph(kind: .nut).stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            case "soy":
                FoodGlyph(kind: .soy).stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            case "eggs":
                FoodGlyph(kind: .egg).stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            case "sesame":
                FoodGlyph(kind: .seeds).fill()
            default: Image(systemName: "fork.knife").resizable().scaledToFit()
            }
            if category == "gluten-free" || category == "dairy-free" {
                Path { path in
                    path.move(to: CGPoint(x: 1, y: 13))
                    path.addLine(to: CGPoint(x: 13, y: 1))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// Simple line drawings in a normalized 14-point square.
private struct FoodGlyph: Shape {
    enum Kind { case wheat, milk, nut, soy, egg, seeds }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .wheat:
            path.move(to: CGPoint(x: 7, y: 13))
            path.addLine(to: CGPoint(x: 7, y: 1))
            for y in [3.0, 6.0, 9.0] {
                path.move(to: CGPoint(x: 7, y: y + 2))
                path.addQuadCurve(to: CGPoint(x: 3, y: y - 1), control: CGPoint(x: 2, y: y + 2))
                path.addQuadCurve(to: CGPoint(x: 7, y: y + 2), control: CGPoint(x: 7, y: y - 1))
                path.addQuadCurve(to: CGPoint(x: 11, y: y - 1), control: CGPoint(x: 12, y: y + 2))
                path.addQuadCurve(to: CGPoint(x: 7, y: y + 2), control: CGPoint(x: 7, y: y - 1))
            }
        case .milk:
            path.move(to: CGPoint(x: 4, y: 1))
            path.addLines([CGPoint(x: 9, y: 1), CGPoint(x: 11, y: 4), CGPoint(x: 11, y: 13),
                           CGPoint(x: 3, y: 13), CGPoint(x: 3, y: 4), CGPoint(x: 4, y: 1)])
            path.closeSubpath()
            path.move(to: CGPoint(x: 3, y: 4)); path.addLine(to: CGPoint(x: 11, y: 4))
            path.move(to: CGPoint(x: 6, y: 7)); path.addLine(to: CGPoint(x: 8, y: 7))
        case .nut:
            path.addRoundedRect(in: CGRect(x: 3, y: 2, width: 8, height: 11), cornerSize: CGSize(width: 4, height: 5))
            path.move(to: CGPoint(x: 7, y: 3))
            path.addQuadCurve(to: CGPoint(x: 7, y: 12), control: CGPoint(x: 4, y: 7))
        case .soy:
            path.move(to: CGPoint(x: 2, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 0, y: 3), control2: CGPoint(x: 8, y: 0))
            path.addCurve(to: CGPoint(x: 2, y: 12), control1: CGPoint(x: 15, y: 10), control2: CGPoint(x: 7, y: 15))
            for point in [CGPoint(x: 5, y: 9), CGPoint(x: 7, y: 7), CGPoint(x: 9, y: 5)] {
                path.addEllipse(in: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
            }
        case .egg:
            path.move(to: CGPoint(x: 7, y: 1))
            path.addCurve(to: CGPoint(x: 7, y: 13), control1: CGPoint(x: 12, y: 1), control2: CGPoint(x: 15, y: 13))
            path.addCurve(to: CGPoint(x: 7, y: 1), control1: CGPoint(x: -1, y: 13), control2: CGPoint(x: 2, y: 1))
        case .seeds:
            for point in [CGPoint(x: 4, y: 3), CGPoint(x: 10, y: 5), CGPoint(x: 5, y: 9), CGPoint(x: 10, y: 11)] {
                path.addEllipse(in: CGRect(x: point.x - 1, y: point.y - 2, width: 2, height: 4))
            }
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 14, y: rect.height / 14)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
