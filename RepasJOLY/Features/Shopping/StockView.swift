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
                    TextField("Ajouter : poulet, courgettes, œufs…", text: $field)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    Text("Ces aliments sont retirés des courses, privilégiés au planning de la semaine et proposés en premier quand tu crées une recette.")
                }
                if !items.isEmpty {
                    Section("Au frigo") {
                        ForEach(items) { item in
                            Text(item.name)
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

    /// « 2 escalopes, courgettes » ajoute deux éléments.
    private func add() {
        let names = field.split(separator: ",")
            .map { ShoppingListBuilder.displayName(String($0)) }
            .filter { !$0.isEmpty }
        let existing = StockMatcher.keys(items.map(\.name))
        withAnimation(.snappy) {
            for name in names where !existing.contains(ShoppingListBuilder.normalizedKey(name)) {
                context.insert(StockItem(name: name))
            }
        }
        field = ""
        focused = true
    }
}
