import SwiftUI

extension Font {
    /// Voix d'affichage : SF Pro Expanded gras, pour les titres de recette et le chrono.
    static func display(_ style: Font.TextStyle) -> Font {
        .system(style, weight: .bold).width(.expanded)
    }
}

enum Format {
    static func minutes(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest)"
    }

    /// « 12:04 » ou « 1:02:03 ».
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    static func duration(_ interval: TimeInterval) -> String {
        minutes(max(1, Int((interval / 60).rounded())))
    }
}

/// Vignette de recette : la photo si elle existe, sinon le symbole de sa catégorie dans sa teinte.
struct RecipeThumbnail: View {
    let recipe: Recipe
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let data = recipe.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
            } else {
                Image(systemName: recipe.category.symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(recipe.category.color)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Puce sélectionnable, pour les filtres et les choix rapides.
struct ChipToggle: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Disposition en lignes qui passent à la ligne, pour des puces de longueur variable.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > maxWidth {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Note de 1 à 5, réglable au toucher.
struct RatingControl: View {
    @Binding var rating: Int?
    var size: Font = .title3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = rating == value ? nil : value
                } label: {
                    Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                        .font(size)
                        .foregroundStyle(value <= (rating ?? 0) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .frame(minWidth: 36, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .symbolEffect(.bounce, value: rating == value)
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement()
        .accessibilityLabel("Note")
        .accessibilityValue(rating.map { "\($0) sur 5" } ?? "Aucune")
        .accessibilityAdjustableAction { direction in
            let current = rating ?? 0
            rating = direction == .increment ? min(5, current + 1) : (current <= 1 ? nil : current - 1)
        }
    }
}
