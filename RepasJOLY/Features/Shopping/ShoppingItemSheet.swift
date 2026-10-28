import SwiftUI

/// Détail d'un article : pour quels repas, combien au total, ce qu'on a déjà, ce qu'il reste à acheter.
struct ShoppingItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let need: ShoppingNeed
    let isChecked: Bool
    let setHave: (Double) -> Void
    let toggle: () -> Void

    @State private var have: Double?

    private var unit: String { need.item.unit }
    private var hasQuantity: Bool { need.needed > 0 && !unit.isEmpty }
    private var toBuy: Double { max(0, need.needed - (have ?? 0)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(need.uses.enumerated()), id: \.offset) { _, use in
                        LabeledContent {
                            Text(useQuantity(use))
                                .monospacedDigit()
                        } label: {
                            Text(use.recipeTitle)
                            Text(use.mealLabel)
                        }
                    }
                    if hasQuantity {
                        LabeledContent("Total") {
                            Text(ShoppingPlanner.format(need.needed, unit: unit))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Il te faut")
                } footer: {
                    if need.unknownMeals > 0 && hasQuantity {
                        Text("Quantité non précisée pour \(need.unknownMeals) repas : prévois un peu plus.")
                    }
                }

                if hasQuantity {
                    Section {
                        LabeledContent("J'en ai déjà") {
                            HStack(spacing: 4) {
                                TextField("0", value: $have, format: .number.precision(.fractionLength(0...1)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 90)
                                Text(unitLabel).foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                        }
                        LabeledContent("À acheter") {
                            Text(toBuy > 0 ? ShoppingPlanner.format(toBuy, unit: unit) : "Rien")
                                .font(.display(.title3))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(toBuy > 0 ? .primary : .secondary)
                        }
                        .animation(.snappy, value: toBuy)
                    } footer: {
                        Text("Indique ce que tu as déjà : le reste à acheter est recalculé.")
                    }
                }

                Section {
                    Button(isChecked ? "Je n'en ai pas" : "J'en ai",
                           systemImage: isChecked ? "circle" : "checkmark.circle") {
                        toggle()
                        dismiss()
                    }
                }
            }
            .navigationTitle(need.item.name)
            .navigationSubtitle(need.item.aisle.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
            .onAppear { have = need.have > 0 ? need.have : nil }
            .onDisappear {
                if hasQuantity, (have ?? 0) != need.have { setHave(have ?? 0) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var unitLabel: String {
        switch unit {
        case "g": "g"
        case "ml": "ml"
        default: "pièce(s)"
        }
    }

    private func useQuantity(_ use: ShoppingNeed.Use) -> String {
        if use.amount > 0 && !unit.isEmpty { return ShoppingPlanner.format(use.amount, unit: unit) }
        return use.detail.isEmpty ? "selon ta main" : use.detail
    }
}
