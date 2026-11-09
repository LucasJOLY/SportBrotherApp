import Foundation
import ImageIO
import Network
import UIKit

/// Démonstrations des exos du catalogue (animation 3D et photos départ/arrivée), hébergées dans le bucket public
/// `sport-media` et gardées sur le téléphone : une fois vues ou préchargées, elles marchent sans réseau à la salle.
enum ExerciseMedia {
    private static let base: URL? = {
        guard let string = Bundle.main.infoDictionary?["SupabaseURL"] as? String,
              let url = URL(string: string), url.host() != nil else { return nil }
        return url.appending(path: "storage/v1/object/public/sport-media")
    }()

    /// Application Support plutôt que Caches : iOS ne vide pas ce dossier quand l'espace manque.
    private static let folder: URL = {
        var url = URL.applicationSupportDirectory.appending(path: "sport-media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        return cache
    }()

    private static func animationPath(_ id: String) -> String { "gif/\(id).gif" }
    private static func photoPath(_ id: String, _ index: Int) -> String { "photo/\(id)/\(index).jpg" }

    // MARK: Lecture

    /// Animation déjà en mémoire ou sur le disque, sans attendre le réseau.
    static func cachedAnimation(for id: String) -> UIImage? {
        if let image = images.object(forKey: animationPath(id) as NSString) { return image }
        guard let data = try? Data(contentsOf: local(animationPath(id))), let image = animatedImage(data) else { return nil }
        images.setObject(image, forKey: animationPath(id) as NSString)
        return image
    }

    static func animation(for id: String) async -> UIImage? {
        if let cached = cachedAnimation(for: id) { return cached }
        guard let data = await data(animationPath(id)), let image = animatedImage(data) else { return nil }
        images.setObject(image, forKey: animationPath(id) as NSString)
        return image
    }

    static func cachedPhotos(for id: String, count: Int) -> [UIImage] {
        (0..<count).compactMap { index in
            let path = photoPath(id, index)
            if let image = images.object(forKey: path as NSString) { return image }
            guard let image = UIImage(contentsOfFile: local(path).path()) else { return nil }
            images.setObject(image, forKey: path as NSString)
            return image
        }
    }

    static func photos(for id: String, count: Int) async -> [UIImage] {
        var result: [UIImage] = []
        for index in 0..<count {
            let path = photoPath(id, index)
            if let image = images.object(forKey: path as NSString) {
                result.append(image)
            } else if let data = await data(path), let image = UIImage(data: data) {
                images.setObject(image, forKey: path as NSString)
                result.append(image)
            }
        }
        return result
    }

    // MARK: Préchargement

    /// Télécharge en arrière-plan les démonstrations des exos qu'on fait vraiment (modèles, historique),
    /// seulement en Wi-Fi : la salle n'a souvent pas de réseau.
    static func prefetch(_ exercises: [ExerciseInfo]) async {
        guard base != nil, await isOnUnmeteredNetwork() else { return }
        for exercise in exercises {
            if exercise.hasAnimation { _ = await data(animationPath(exercise.id)) }
            for index in 0..<exercise.photoCount { _ = await data(photoPath(exercise.id, index)) }
        }
    }

    private static func isOnUnmeteredNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            monitor.start(queue: .global(qos: .utility))
        }
    }

    // MARK: Fichiers

    private static func local(_ path: String) -> URL {
        folder.appending(path: path.replacingOccurrences(of: "/", with: "__"))
    }

    /// Le fichier depuis le disque, sinon téléchargé puis enregistré.
    private static func data(_ path: String) async -> Data? {
        let file = local(path)
        if let data = try? Data(contentsOf: file) { return data }
        guard let base,
              let (data, response) = try? await URLSession.shared.data(from: base.appending(path: path)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// GIF décodé image par image avec ImageIO (UIImage ne lit que la première image).
    private static func animatedImage(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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
        guard frames.count > 1 else { return frames.first }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}
