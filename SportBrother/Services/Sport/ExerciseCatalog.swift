import Foundation
import SwiftUI
import UIKit

/// Exo tel qu'affiché : le catalogue embarqué fusionné avec les réglages partagés (favori, photo, nom…).
struct ExerciseInfo: Identifiable, Hashable {
    let id: String
    var name: String
    var group: MuscleGroup
    var isBodyweight: Bool
    /// Charge par bras, un côté puis l'autre (curl concentré, rowing un bras…).
    var isUnilateral: Bool
    var isFavorite: Bool
    var isCustom: Bool
    var isHidden: Bool
    var photoPath: String?
    /// Démonstrations du catalogue disponibles dans `sport-media` (voir `ExerciseMedia`).
    var hasAnimation: Bool
    var photoCount: Int
    var hasDemo: Bool { hasAnimation || photoCount > 0 }
    var restSeconds: Int
    var repRangeHigh: Int
    /// Ordre « classique d'abord » au sein du groupe.
    var order: Int

    static let defaultRest = 90
    static let defaultRepRangeHigh = 12
}

nonisolated struct CatalogEntry: Codable, Sendable {
    let id: String
    let name: String
    let group: MuscleGroup
    let equipment: String?
    let isBodyweight: Bool
    let isUnilateral: Bool?
    let hasAnimation: Bool?
    let photoCount: Int?
    let order: Int
}

/// Catalogue d'exos embarqué (free-exercise-db, domaine public) et ses vignettes, chargé une fois.
enum ExerciseCatalog {
    static let entries: [CatalogEntry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ExerciseCatalog"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CatalogEntry].self, from: data)) ?? []
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    private static let images = NSCache<NSString, UIImage>()
    static func image(for id: String) -> UIImage? {
        if let cached = images.object(forKey: id as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "ExerciseCatalog/images"),
              let image = UIImage(contentsOfFile: url.path()) else { return nil }
        images.setObject(image, forKey: id as NSString)
        return image
    }

    /// Catalogue + exos perso, avec les réglages partagés appliqués. Les exos supprimés disparaissent.
    static func merged(_ overrides: [SportExercise]) -> [ExerciseInfo] {
        let live = overrides.filter { $0.deletedAt == nil }
        let settings = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = entries.map { entry in
            info(entry: entry, override: settings[entry.id])
        }
        for custom in live where byID[custom.id] == nil {
            result.append(ExerciseInfo(
                id: custom.id,
                name: custom.name ?? "Exo",
                group: custom.groupRaw.flatMap(MuscleGroup.init(rawValue:)) ?? .dos,
                isBodyweight: custom.isBodyweight ?? false,
                isUnilateral: custom.isUnilateral ?? false,
                isFavorite: custom.isFavorite,
                isCustom: true,
                isHidden: custom.isHidden,
                photoPath: custom.photoPath,
                hasAnimation: false,
                photoCount: 0,
                restSeconds: custom.restSeconds ?? ExerciseInfo.defaultRest,
                repRangeHigh: custom.repRangeHigh ?? ExerciseInfo.defaultRepRangeHigh,
                order: -1
            ))
        }
        return result
    }

    private static func info(entry: CatalogEntry, override: SportExercise?) -> ExerciseInfo {
        ExerciseInfo(
            id: entry.id,
            name: override?.name ?? entry.name,
            group: entry.group,
            isBodyweight: override?.isBodyweight ?? entry.isBodyweight,
            isUnilateral: override?.isUnilateral ?? entry.isUnilateral ?? false,
            isFavorite: override?.isFavorite ?? false,
            isCustom: false,
            isHidden: override?.isHidden ?? false,
            photoPath: override?.photoPath,
            hasAnimation: entry.hasAnimation ?? false,
            photoCount: entry.photoCount ?? 0,
            restSeconds: override?.restSeconds ?? ExerciseInfo.defaultRest,
            repRangeHigh: override?.repRangeHigh ?? ExerciseInfo.defaultRepRangeHigh,
            order: entry.order
        )
    }

    static func isCatalog(_ id: String) -> Bool { byID[id] != nil }
}

extension Array where Element == ExerciseInfo {
    /// Accès direct par identifiant (exo_ref des séances et modèles).
    var byID: [String: ExerciseInfo] { Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
}

/// Vignette d'exo : photo de la machine si elle existe, sinon l'image du catalogue, sinon le symbole du groupe.
struct ExerciseThumbnail: View {
    let exercise: ExerciseInfo
    var size: CGFloat = 52
    @Environment(SportSync.self) private var sync
    @State private var photo: UIImage?

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
            } else if let image = ExerciseCatalog.image(for: exercise.id) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
            } else {
                Image(systemName: exercise.group.symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(exercise.group.color)
                    .frame(width: size, height: size)
                    .background(exercise.group.color.opacity(0.12), in: .rect(cornerRadius: size * 0.24, style: .continuous))
            }
        }
        .accessibilityHidden(true)
        .task(id: exercise.photoPath) {
            guard let path = exercise.photoPath else { photo = nil; return }
            photo = sync.cachedPhoto(path)
            if photo == nil { photo = await sync.photo(path) }
        }
    }
}
