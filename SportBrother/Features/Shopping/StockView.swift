import SwiftData
import SwiftUI

/// Ce qu'il y a déjà à la maison.
struct StockView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StockItem.addedAt, order: .reverse) private var items: [StockItem]
    @State private var field = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("500 g poulet, 6 œufs, courgettes…", text: $field)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    Text("Avec une quantité (« 500 g poulet »), les courses calculent ce qu'il reste à acheter. Sans quantité, l'aliment est considéré comme déjà là. Le frigo est aussi privilégié au planning et à la création de recettes.")
                }
                if !items.isEmpty {
                    Section("Au frigo") {
                        ForEach(items) { item in
                            Text(item.label)
                                .monospacedDigit()
                        }
                        .onDelete { offsets in
                            withAnimation { offsets.map { items[$0] }.forEach(context.delete) }
                        }
                    }
                }
            }
            .navigationTitle("Frigo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("Plus", systemImage: "ellipsis") {
                            Button("Tout retirer", systemImage: "trash", role: .destructive) {
                                withAnimation { items.forEach(context.delete) }
                            }
                        }
                    }
                }
            }
            .onAppear { focused = items.isEmpty }
        }
        .presentationDetents([.medium, .large])
    }

    /// « 500 g poulet, courgettes » ajoute deux éléments ; un aliment déjà présent est mis à jour.
    private func add() {
        let entries = field.split(separator: ",")
            .map { StockEntry.parse(String($0)) }
            .filter { !$0.name.isEmpty }
        withAnimation(.snappy) {
            for entry in entries {
                let key = ShoppingListBuilder.normalizedKey(entry.name)
                if let existing = items.first(where: { ShoppingListBuilder.normalizedKey($0.name) == key }) {
                    existing.amount = entry.amount
                    existing.unit = entry.unit
                } else {
                    context.insert(StockItem(name: entry.name, amount: entry.amount, unit: entry.unit))
                }
            }
        }
        field = ""
        focused = true
    }
}
