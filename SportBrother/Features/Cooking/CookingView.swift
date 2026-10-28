import SwiftData
import SwiftUI

struct CookingView: View {
    @Environment(\.modelContext) private var context
    @Environment(CookingLauncher.self) private var launcher
    @Bindable var controller: CookingController

    @AppStorage("cookingListMode") private var listMode = false
    @State private var showIngredients = false
    @State private var confirmClose = false
    @State private var showFinish = false

    private var steps: [RecipeStep] { controller.recipe.steps }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(controller.recipe.title)
                    .font(.display(.title3))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                clock
                ActiveTimersBar(controller: controller)
                Picker("Affichage", selection: $listMode) {
                    Text("Étape par étape").tag(false)
                    Text("Liste").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                if listMode {
                    stepList
                } else {
                    ProgressView(value: Double(controller.currentStep + 1), total: Double(max(steps.count, 1)))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .animation(.snappy, value: controller.currentStep)
                        .accessibilityLabel("Étape \(controller.currentStep + 1) sur \(steps.count)")
                    stepPager
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { confirmClose = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Ingrédients", systemImage: "list.bullet") { showIngredients = true }
                }
            }
            .confirmationDialog("Arrêter la recette ?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Terminer et enregistrer") { showFinish = true }
                Button("Abandonner sans enregistrer", role: .destructive) {
                    controller.cancel(context: context)
                    launcher.controller = nil
                }
            }
            .sheet(isPresented: $showIngredients) { IngredientsSheet(recipe: controller.recipe, servings: controller.servings) }
            .sheet(isPresented: $showFinish) {
                FinishSheet(controller: controller) {
                    launcher.controller = nil
                }
            }
        }
    }

    // MARK: Chrono

    private var clock: some View {
        HStack(alignment: .center) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(Format.clock(controller.elapsed(at: timeline.date)))
                    .font(.display(.largeTitle))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(controller.elapsed(at: timeline.date)))
                    .opacity(controller.isPaused ? 0.4 : 1)
                    .accessibilityLabel("Temps écoulé")
            }
            Spacer()
            Button {
                controller.togglePause()
            } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(controller.isPaused ? "Reprendre" : "Pause")
            .sensoryFeedback(.impact(weight: .medium), trigger: controller.isPaused)
        }
        .overlay(alignment: .bottomLeading) {
            if controller.isPaused {
                Text("En pause")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: 14)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: controller.isPaused)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    // MARK: Étape par étape

    private var stepPager: some View {
        VStack(spacing: 0) {
            TabView(selection: $controller.currentStep) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    StepPage(step: step, next: steps.indices.contains(index + 1) ? steps[index + 1] : nil, controller: controller) {
                        guard index + 1 < steps.count else { return }
                        withAnimation { controller.currentStep = index + 1 }
                    }
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .sensoryFeedback(.selection, trigger: controller.currentStep)

            HStack(spacing: 12) {
                Button {
                    withAnimation { controller.currentStep -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(controller.currentStep == 0)
                .accessibilityLabel("Étape précédente")

                if controller.currentStep >= steps.count - 1 {
                    Button {
                        showFinish = true
                    } label: {
                        Label("Terminer", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button {
                        withAnimation { controller.currentStep += 1 }
                    } label: {
                        Text("Étape suivante")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: Liste

    private var stepList: some View {
        List {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                let done = controller.completedSteps.contains(step.id)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button {
                        withAnimation(.snappy) { controller.completedSteps.formSymmetricDifference([step.id]) }
                    } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: done) { _, new in new }
                    .accessibilityLabel(done ? "Étape faite" : "Marquer l'étape comme faite")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(index + 1). \(step.text)")
                            .foregroundStyle(done ? .secondary : .primary)
                        if !step.parallelHint.isEmpty {
                            ParallelHint(text: step.parallelHint)
                        }
                        if step.durationMinutes > 0 {
                            StepTimerControl(step: step, controller: controller, compact: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Button {
                    showFinish = true
                } label: {
                    Label("Terminer", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }
}

private struct StepPage: View {
    let step: RecipeStep
    let next: RecipeStep?
    let controller: CookingController
    /// Passe à l'étape suivante, pour enchaîner pendant une étape qui tourne seule.
    let advance: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !step.title.isEmpty {
                    Text(step.title)
                        .font(.display(.title3))
                }
                Text(step.text)
                    .font(.title.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !step.parallelHint.isEmpty {
                    ParallelHint(text: step.parallelHint)
                }
                if step.durationMinutes > 0 {
                    StepTimerControl(step: step, controller: controller, compact: false,
                                     advance: step.isPassive && next != nil ? advance : nil)
                }
                if let next {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ensuite").font(.subheadline.weight(.semibold))
                        Text(next.text).lineLimit(3)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
}

private struct ParallelHint: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "arrow.triangle.branch")
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("En parallèle : \(text)")
    }
}

/// Minuteur d'étape : lancer, voir le compte à rebours, arrêter.
private struct StepTimerControl: View {
    let step: RecipeStep
    let controller: CookingController
    let compact: Bool
    /// Fourni pour une étape qui tourne seule : le bouton lance le minuteur et enchaîne.
    var advance: (() -> Void)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let remaining = controller.remaining(for: step, at: timeline.date) {
                HStack {
                    Label(remaining > 0 ? Format.clock(remaining) : "Terminé",
                          systemImage: remaining > 0 ? "timer" : "bell.fill")
                        .font(compact ? .headline : .display(.title2))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(remaining > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                        .symbolEffect(.bounce, options: .repeat(3), value: remaining == 0)
                    Spacer()
                    Button("Arrêter", systemImage: "xmark") { controller.cancelTimer(for: step) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Arrêter le minuteur")
                }
                .sensoryFeedback(.warning, trigger: remaining == 0) { _, finished in finished }
            } else {
                if let advance {
                    Button {
                        controller.startTimer(for: step)
                        advance()
                    } label: {
                        Label("Lancer \(Format.minutes(step.durationMinutes)) et continuer", systemImage: "arrow.triangle.branch")
                            .font(.headline)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button {
                        controller.startTimer(for: step)
                    } label: {
                        Label("Minuteur \(Format.minutes(step.durationMinutes))", systemImage: "timer")
                            .font(compact ? .subheadline.weight(.semibold) : .headline)
                            .monospacedDigit()
                            .frame(minHeight: compact ? 28 : 40)
                            .padding(.horizontal, compact ? 4 : 10)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

private struct IngredientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let servings: Int

    var body: some View {
        NavigationStack {
            List(recipe.ingredients.map { $0.scaled(forServings: servings) }) { ingredient in
                LabeledContent(ingredient.name) {
                    Text([ingredient.grams > 0 ? "\(Int(ingredient.grams)) g" : nil,
                          ingredient.detail.isEmpty ? nil : ingredient.detail].compactMap { $0 }.joined(separator: " · "))
                        .monospacedDigit()
                }
            }
            .navigationTitle("Ingrédients")
            .navigationSubtitle(servings == 1 ? "Pour 1 personne" : "Pour \(servings) personnes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FinishSheet: View {
    @Environment(\.modelContext) private var context
    let controller: CookingController
    let onDone: () -> Void
    @State private var rating: Int?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .nonRepeating)
                Text("Bon appétit")
                    .font(.display(.title2))
                Text("Prêt en \(Format.duration(controller.elapsed(at: .now)))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(spacing: 4) {
                Text("Ta note").font(.subheadline).foregroundStyle(.secondary)
                RatingControl(rating: $rating, size: .title)
            }
            Button {
                controller.finish(rating: rating, context: context)
                onDone()
            } label: {
                Text("Enregistrer")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(24)
        .onAppear { rating = controller.recipe.rating }
        .presentationDetents([.height(380)])
        .sensoryFeedback(.success, trigger: true)
    }
}

/// Tous les minuteurs en cours, toujours visibles : plusieurs cuissons peuvent tourner en même temps.
private struct ActiveTimersBar: View {
    let controller: CookingController

    var body: some View {
        let timers = controller.activeTimers
        if !timers.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let finished = timers.filter { (controller.remaining(for: $0.step, at: timeline.date) ?? 0) <= 0 }.count
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(timers, id: \.step.id) { timer in
                            let remaining = controller.remaining(for: timer.step, at: timeline.date) ?? 0
                            Button {
                                withAnimation { controller.currentStep = timer.index }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: remaining > 0 ? "timer" : "bell.fill")
                                        .symbolEffect(.bounce, options: .repeat(3), value: remaining <= 0)
                                    Text("Étape \(timer.index + 1)")
                                        .foregroundStyle(.secondary)
                                    Text(remaining > 0 ? Format.clock(remaining) : "Prêt")
                                        .fontWeight(.semibold)
                                        .contentTransition(.numericText(countsDown: true))
                                }
                                .font(.subheadline)
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                            }
                            .buttonStyle(.glass)
                            .tint(remaining > 0 ? nil : .orange)
                            .accessibilityLabel("Étape \(timer.index + 1), \(remaining > 0 ? Format.clock(remaining) : "prêt")")
                        }
                    }
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollIndicators(.hidden)
                .sensoryFeedback(.warning, trigger: finished) { old, new in new > old }
            }
            .padding(.bottom, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
