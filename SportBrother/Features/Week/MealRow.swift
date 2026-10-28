import SwiftData
import SwiftUI

struct MealRow: View {
    @Environment(\.modelContext) private var context
    let slot: MealSlot
    let week: WeekPlan
    let recipes: [Recipe]
    let pickRecipe: (MealSlot) -> Void

    private var planner: WeekPlanner { WeekPlanner(context: context) }

    var body: some View {
        HStack(spacing: 12) {
            StatusButton(slot: slot)
            content
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            Button(slot.status == .done ? "Annuler" : "Fait", systemImage: slot.status == .done ? "arrow.uturn.backward" : "checkmark") {
                set(slot.status == .done ? .planned : .done)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("Dehors", systemImage: "fork.knife") { set(.eatenOut) }.tint(.indigo)
            Button("Sauter", systemImage: "minus.circle") { set(.skipped) }.tint(.gray)
        }
        .contextMenu { menu }
        .draggable(slot.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)),
                  let other = week.slots.first(where: { $0.id == id }) else { return false }
            withAnimation(.snappy) { planner.swap(other, slot) }
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        let label = VStack(alignment: .leading, spacing: 3) {
            Text(slot.recipe?.title ?? "Aucune recette")
                .font(.body.weight(.medium))
                .strikethrough(slot.status == .done, color: .secondary)
                .foregroundStyle(slot.status == .planned ? .primary : .secondary)
                .lineLimit(2)
                .contentTransition(.opacity)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let recipe = slot.recipe {
            NavigationLink(value: recipe) {
                HStack {
                    label
                    if slot.isLocked {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
                            .accessibilityLabel("Verrouillé")
                    }
                }
            }
        } else {
            label
        }
    }

    private var caption: String {
        var parts = [slot.meal.label]
        if let source = sourceSlot {
            parts.append("reste de \(WeekCalendar.dayName(source.day).lowercased()) \(source.meal.label.lowercased())")
        } else if slot.diners == 1 {
            if let target = week.slots.first(where: { $0.leftoverSourceID == slot.id }) {
                parts.append("pour 2, reste \(WeekCalendar.dayName(target.day).lowercased()) \(target.meal.label.lowercased())")
            } else {
                parts.append("seul, pour 2")
            }
        } else {
            parts.append("à deux")
        }
        if slot.status != .planned && slot.status != .done {
            parts.append(slot.status.label.lowercased())
        } else if let minutes = slot.recipe?.estimatedMinutes, slot.needsCooking {
            parts.append(Format.minutes(minutes))
        }
        return parts.joined(separator: " · ")
    }

    private var sourceSlot: MealSlot? {
        slot.leftoverSourceID.flatMap { id in week.slots.first { $0.id == id } }
    }

    @ViewBuilder
    private var menu: some View {
        if slot.needsCooking {
            Button("Autre recette", systemImage: "shuffle") {
                withAnimation(.snappy) { planner.reroll(slot, recipes: recipes) }
            }
            Button("Choisir une recette…", systemImage: "list.bullet") { pickRecipe(slot) }
            Button(slot.isLocked ? "Déverrouiller" : "Verrouiller", systemImage: slot.isLocked ? "lock.open" : "lock") {
                slot.isLocked.toggle()
            }
            let others = week.orderedSlots.filter { $0.needsCooking && $0.id != slot.id && $0.recipe != nil }
            if !others.isEmpty {
                Menu("Échanger avec…", systemImage: "arrow.left.arrow.right") {
                    ForEach(others) { other in
                        Button("\(WeekCalendar.dayName(other.day)) \(other.meal.label.lowercased()) · \(other.recipe?.title ?? "")") {
                            withAnimation(.snappy) { planner.swap(slot, other) }
                        }
                    }
                }
            }
            leftoverMenu
        }
        Divider()
        Button("Fait", systemImage: "checkmark") { set(.done) }
        Button("Sauter", systemImage: "minus.circle") { set(.skipped) }
        Button("Mangé dehors", systemImage: "fork.knife") { set(.eatenOut) }
        if slot.status != .planned {
            Button("Remettre prévu", systemImage: "arrow.uturn.backward") { set(.planned) }
        }
    }

    @ViewBuilder
    private var leftoverMenu: some View {
        let info = planner.leftoverInfo(in: week)
        if let me = info.first(where: { $0.order == slot.order }), LeftoverRules.producesLeftover(me) {
            let current = week.slots.first { $0.leftoverSourceID == slot.id }
            let candidates = LeftoverRules.candidates(for: me, in: info)
                .compactMap { order in week.slots.first { $0.order == order } }
            Menu("Reste vers…", systemImage: "takeoutbag.and.cup.and.straw") {
                Picker("Reste vers", selection: Binding(
                    get: { current?.id },
                    set: { id in
                        let target = week.slots.first { $0.id == id }
                        withAnimation(.snappy) { planner.setLeftover(from: slot, to: target) }
                    }
                )) {
                    Text("Aucun").tag(UUID?.none)
                    ForEach([current].compactMap { $0 } + candidates) { target in
                        Text("\(WeekCalendar.dayName(target.day)) \(target.meal.label.lowercased())").tag(Optional(target.id))
                    }
                }
            }
        }
    }

    private func set(_ status: SlotStatus) {
        withAnimation(.snappy) { planner.setStatus(status, for: slot) }
    }
}

/// Rond à cocher façon Rappels : un toucher marque le repas comme fait.
private struct StatusButton: View {
    @Environment(\.modelContext) private var context
    let slot: MealSlot

    var body: some View {
        Button {
            withAnimation(.snappy) {
                WeekPlanner(context: context).setStatus(slot.status == .planned ? .done : .planned, for: slot)
            }
        } label: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(slot.status == .done ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: slot.status == .done) { _, isDone in isDone }
        .accessibilityLabel(slot.status.label)
        .accessibilityHint("Marquer comme fait")
    }

    private var symbol: String {
        switch slot.status {
        case .planned: "circle"
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .eatenOut: "fork.knife.circle"
        }
    }
}
