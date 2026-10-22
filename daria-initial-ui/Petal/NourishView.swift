import SwiftUI

@MainActor
struct NourishView: View {
    @Environment(CycleStore.self) private var store
    @State private var phase: Phase?
    @State private var openMeal: Meal?
    @State private var confirmingClearGrocery = false
    @State private var clearingGrocery = false
    @State private var groceryClearError: String?
    @State private var editingPreferences = false
    @Namespace private var tabs

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

            preferencesButton

            phaseTabs

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text("Meal ideas").font(.display(22))
                    if generated != nil {
                        Text("AI")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.accentSoft, in: Capsule())
                            .accessibilityLabel("AI generated")
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
                    Text("Grocery list").font(.display(22))
                    Spacer()
                    Text("\(store.grocery.filter { !$0.done }.count) to buy").font(.caption).foregroundStyle(Palette.inkFaint)
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
        .sheet(isPresented: $editingPreferences) {
            PreferencesEditor(diets: store.diets, avoid: store.avoid, dislikes: store.dislikes).environment(store)
        }
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

    /// A filter-style chip row: the preferences button, then what's selected. Any chip opens PreferencesEditor.
    private var preferencesButton: some View {
        let picked = CycleStore.dietOptions.filter(store.diets.contains).map { ($0, PreferencesEditor.label($0)) }
            + CycleStore.allergenOptions.filter(store.avoid.contains).map { ($0, "No \($0)") }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button { editingPreferences = true } label: {
                    Label(picked.isEmpty ? "Add preferences" : "Preferences", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Palette.mist, in: Capsule())
                }
                ForEach(picked, id: \.0) { category, label in
                    Button { editingPreferences = true } label: {
                        HStack(spacing: 6) {
                            FoodCategoryIcon(category: category).frame(width: 13, height: 13).accessibilityHidden(true)
                            Text(label).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Palette.surface, in: Capsule())
                        .overlay(Capsule().stroke(Palette.line))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Food preferences: \(picked.isEmpty ? "none set" : picked.map(\.1).joined(separator: ", "))")
        .accessibilityHint("Opens the preferences editor")
        .accessibilityAddTraits(.isButton)
    }

    /// Folder-style tabs: the selected phase opens into its tip, so the two read as one piece.
    private var phaseTabs: some View {
        let isFirst = selected == Phase.allCases.first
        let isLast = selected == Phase.allCases.last
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Phase.allCases) { p in
                    Button { phase = p } label: {
                        Text(p.name + (p == store.currentPhase ? " ·" : ""))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(p == selected ? Palette.accent : Palette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 11).padding(.bottom, 9)
                            .background {
                                if p == selected {
                                    UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                                        .fill(Palette.mist)
                                        .matchedGeometryEffect(id: "tab", in: tabs)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(p == selected ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Eat for this phase")
                Text(selected.foodTip).font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Palette.mist, in: UnevenRoundedRectangle(topLeadingRadius: isFirst ? 0 : 18, bottomLeadingRadius: 18,
                                                                 bottomTrailingRadius: 18, topTrailingRadius: isLast ? 0 : 18,
                                                                 style: .continuous))
        }
        .animation(.easeOut(duration: 0.25), value: selected)
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
                            .background(Palette.secondarySurface, in: Capsule())
                            .foregroundStyle(Palette.secondaryAccent)
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
/// Diet, avoid and dislikes. Edits stay local until Save, so closing discards them.
private struct PreferencesEditor: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let original: (diets: Set<String>, avoid: Set<String>, dislikes: [String])
    @State private var diets: Set<String>
    @State private var avoid: Set<String>
    @State private var dislikes: [String]
    @State private var newDislike = ""

    init(diets: Set<String>, avoid: Set<String>, dislikes: [String]) {
        original = (diets, avoid, dislikes)
        _diets = State(initialValue: diets)
        _avoid = State(initialValue: avoid)
        _dislikes = State(initialValue: dislikes)
    }

    static func label(_ option: String) -> String { option.prefix(1).uppercased() + option.dropFirst() }

    private var changed: Bool { diets != original.diets || avoid != original.avoid || dislikes != original.dislikes }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SheetHeader(eyebrow: "Nourish") {
                dismiss()
            } title: {
                DisplayTitle(before: "Your ", accent: "preferences", size: 30)
            }
            Text("Meal ideas only show recipes that fit.")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
                .padding(.top, -14)
            section("Diet", options: CycleStore.dietOptions, selected: diets) { diets.formSymmetricDifference([$0]) }
            section("Avoid", options: CycleStore.allergenOptions, selected: avoid) { avoid.formSymmetricDifference([$0]) }
            dislikesSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, changed ? 90 : 16)
        .foregroundStyle(Palette.ink)
        .fittedSheet()
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            if changed {
                Button {
                    store.savePreferences(diets: diets, avoid: avoid, dislikes: dislikes)
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Palette.accent, in: Capsule())
                        .shadow(color: Palette.berry.opacity(0.2), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: changed)
    }

    private func section(_ title: String, options: [String], selected: Set<String>, toggle: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: title).padding(.bottom, 4)
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let on = selected.contains(option)
                if index > 0 { Divider() }
                Button { toggle(option) } label: {
                    HStack(spacing: 14) {
                        FoodCategoryIcon(category: option)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Palette.inkSoft)
                            .accessibilityHidden(true)
                        Text(Self.label(option)).font(.system(size: 16))
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(on ? Palette.accent : Palette.inkFaint.opacity(0.4))
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .sensoryFeedback(.selection, trigger: on)
            }
        }
    }

    private var dislikesSection: some View {
        let cleaned = CycleStore.cleanDislike(newDislike)
        let canAdd = !cleaned.isEmpty && !dislikes.contains(cleaned) && dislikes.count < 20
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Don't like")
            Text("Foods to leave out of meal ideas")
                .font(.system(size: 13)).foregroundStyle(Palette.inkSoft)
            HStack(spacing: 8) {
                TextField("Add a food", text: $newDislike)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { if canAdd { addDislike(cleaned) } }
                Button { addDislike(cleaned) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
                .opacity(canAdd ? 1 : 0.35)
                .disabled(!canAdd)
                .accessibilityLabel("Add food")
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(Palette.line))
            if !dislikes.isEmpty {
                FlowLayout {
                    ForEach(dislikes, id: \.self) { food in
                        Button { dislikes.removeAll { $0 == food } } label: {
                            HStack(spacing: 6) {
                                Text(Self.label(food)).font(.system(size: 14, weight: .medium))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.inkSoft)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().stroke(Palette.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(food)")
                    }
                }
            }
        }
    }

    private func addDislike(_ food: String) {
        dislikes.append(food)
        newDislike = ""
    }
}

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
