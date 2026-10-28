import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Exo tel qu'affiché : le catalogue embarqué fusionné avec les réglages partagés (favori, photo, nom…).
struct ExerciseInfo: Identifiable, Hashable {
    let id: String
    var name: String
    var group: MuscleGroup
    var isBodyweight: Bool
    var isFavorite: Bool
    var isCustom: Bool
    var isHidden: Bool
    var photoPath: String?
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
    let order: Int
}

/// Catalogue d'exos embarqué (free-exercise-db, domaine public), chargé une fois.
enum ExerciseCatalog {
    static let entries: [CatalogEntry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ExerciseCatalog"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CatalogEntry].self, from: data)) ?? []
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    private static let images = NSCache<NSString, UIImage>()
    private static let animations: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        return cache
    }()

    /// Illustration animée (ExerciseDB), décodée image par image avec ImageIO.
    static func animation(for id: String) -> UIImage? {
        if let cached = animations.object(forKey: id as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: id, withExtension: "gif", subdirectory: "ExerciseCatalog/anim"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: frame))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += delay > 0.011 ? delay : 0.1
        }
        guard frames.count > 1, let image = UIImage.animatedImage(with: frames, duration: duration) else { return nil }
        animations.setObject(image, forKey: id as NSString)
        return image
    }

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
                isFavorite: custom.isFavorite,
                isCustom: true,
                isHidden: custom.isHidden,
                photoPath: custom.photoPath,
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
            isFavorite: override?.isFavorite ?? false,
            isCustom: false,
            isHidden: override?.isHidden ?? false,
            photoPath: override?.photoPath,
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
