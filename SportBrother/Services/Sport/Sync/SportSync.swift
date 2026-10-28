import Foundation
import Network
import Supabase
import SwiftData
import UIKit

/// Données Sport partagées : l'interface lit et écrit SwiftData (instantané, hors ligne),
/// ce moteur recopie vers Supabase et applique en direct les écritures des autres téléphones.
@Observable
final class SportSync {
    /// Écritures locales pas encore confirmées par le serveur.
    private(set) var pendingCount = 0
    private(set) var isOnline = true
    /// Vrai tant que la toute première réception n'a pas eu lieu sur ce téléphone.
    private(set) var isFirstLoad: Bool

    private let context: ModelContext
    private let client: SupabaseClient?
    private let baseURL: URL?
    private let apiKey: String
    private var channel: RealtimeChannelV2?
    private var flushTask: Task<Void, Never>?
    private var retryDelay: Duration = .seconds(2)
    private let monitor = NWPathMonitor()
    private var started = false

    private static let cursorKey = "sportSyncCursor"
    private static let pendingPhotosKey = "sportPendingPhotos"
    private static let tables: [any SportRow.Type] = [
        ProfileRow.self, BodyWeightRow.self, ExerciseRow.self, TemplateRow.self, TemplateItemRow.self,
        SessionRow.self, EntryRow.self, SetRow.self, FeedbackRow.self, CoachReviewRow.self,
    ]

    init(context: ModelContext, enabled: Bool = true) {
        self.context = context
        let info = Bundle.main.infoDictionary ?? [:]
        let url = (info["SupabaseURL"] as? String).flatMap(URL.init(string:))
        let key = (info["SupabaseKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if enabled, let url, url.host() != nil, !key.isEmpty {
            baseURL = url
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key,
                options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
            )
        } else {
            baseURL = nil
            client = nil
        }
        apiKey = key
        isFirstLoad = UserDefaults.standard.string(forKey: Self.cursorKey) == nil && client != nil
        refreshPendingCount()
    }

    var isConfigured: Bool { client != nil }

    // MARK: Démarrage

    func start() {
        guard let client, !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "sport.network"))
        Task {
            do {
                if client.auth.currentSession == nil { try await client.auth.signInAnonymously() }
                await refresh()
                await subscribe()
            } catch {
                log("connexion", error)
            }
        }
    }

    /// Retour au premier plan, retour du réseau, tirer pour rafraîchir.
    func refresh() async {
        await flush()
        await pull()
    }

    private func networkChanged(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online, wasOffline { Task { await refresh() } }
    }

    // MARK: Écriture locale

    /// Enregistre une création ou une modification, puis la met en file d'envoi.
    func save<M: SportSynced>(_ model: M) {
        model.modifiedAt = .now
        if model.modelContext == nil { context.insert(model) }
        enqueue(model.row)
        try? context.save()
        scheduleFlush()
    }

    /// Suppression douce, propagée aux autres téléphones.
    func delete<M: SportSynced>(_ model: M) {
        model.deletedAt = .now
        save(model)
    }

    private func enqueue<R: SportRow>(_ row: R) {
        guard client != nil, let payload = try? SportJSON.encoder.encode(row) else { return }
        let key = "\(R.table)/\(row.rowID)"
        if let existing = try? context.fetch(FetchDescriptor<SportOutboxItem>(predicate: #Predicate { $0.key == key })).first {
            existing.payload = payload
            existing.queuedAt = .now
        } else {
            context.insert(SportOutboxItem(table: R.table, rowID: row.rowID, payload: payload))
        }
        refreshPendingCount()
    }

    private func refreshPendingCount() {
        pendingCount = (try? context.fetchCount(FetchDescriptor<SportOutboxItem>())) ?? 0
    }

    // MARK: Envoi

    /// Regroupe les saisies rapprochées (une série validée, puis la suivante…) en un seul envoi.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    func flush() async {
        guard client != nil else { return }
        await uploadPendingPhotos()
        let items = (try? context.fetch(FetchDescriptor<SportOutboxItem>(sortBy: [SortDescriptor(\.queuedAt)]))) ?? []
        guard !items.isEmpty else { return }
        var changes: [String: [Any]] = [:]
        for item in items {
            guard let row = try? JSONSerialization.jsonObject(with: item.payload) else { continue }
            changes[item.table, default: []].append(row)
        }
        let sent = items.map { ($0, $0.queuedAt) }
        do {
            _ = try await rpc("sport_push", body: ["changes": changes])
            // Une ligne modifiée pendant l'envoi reste en file pour le prochain.
            for (item, queuedAt) in sent where item.queuedAt == queuedAt { context.delete(item) }
            try? context.save()
            refreshPendingCount()
            retryDelay = .seconds(2)
        } catch {
            log("envoi", error)
            let delay = retryDelay
            retryDelay = min(retryDelay * 2, .seconds(60))
            flushTask = Task {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await flush()
            }
        }
    }

    // MARK: Réception

    func pull() async {
        guard client != nil else { return }
        let defaults = UserDefaults.standard
        // Léger chevauchement : une transaction validée juste après le curseur n'est jamais perdue.
        let since = defaults.string(forKey: Self.cursorKey)
            .flatMap(SportJSON.parse)
            .map { $0.addingTimeInterval(-5).formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)) }
            ?? "-infinity"
        do {
            let data = try await rpc("sport_pull", body: ["since": since])
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let pending = pendingKeys()
            for type in Self.tables {
                guard let rows = object[type.table] as? [Any], !rows.isEmpty else { continue }
                try applyAll(type, json: JSONSerialization.data(withJSONObject: rows), pending: pending)
            }
            try? context.save()
            if let cursor = object["server_now"] as? String { defaults.set(cursor, forKey: Self.cursorKey) }
            isFirstLoad = false
        } catch {
            log("réception", error)
        }
    }

    private func applyAll<R: SportRow>(_ type: R.Type, json: Data, pending: Set<String>) throws {
        let rows = try SportJSON.decoder.decode([R].self, from: json)
        let existing = (try? context.fetch(FetchDescriptor<R.Model>())) ?? []
        var byID = Dictionary(existing.map { ($0.rowID, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows where !pending.contains("\(R.table)/\(row.rowID)") {
            if let model = byID[row.rowID] {
                if row.modifiedAt >= model.modifiedAt { row.apply(to: model) }
            } else {
                let model = row.makeModel()
                context.insert(model)
                byID[row.rowID] = model
            }
        }
    }

    private func applyOne<R: SportRow>(_ type: R.Type, json: Data) {
        guard let row = try? SportJSON.decoder.decode(R.self, from: json),
              !pendingKeys().contains("\(R.table)/\(row.rowID)") else { return }
        let descriptor = FetchDescriptor<R.Model>(predicate: R.Model.matching(rowID: row.rowID))
        if let model = try? context.fetch(descriptor).first {
            guard row.modifiedAt >= model.modifiedAt else { return }
            row.apply(to: model)
        } else {
            context.insert(row.makeModel())
        }
        try? context.save()
    }

    private func pendingKeys() -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<SportOutboxItem>())) ?? []).map(\.key))
    }

    // MARK: Temps réel

    private func subscribe() async {
        guard let client, channel == nil else { return }
        let channel = client.channel("sport") { $0.isPrivate = true }
        self.channel = channel
        let messages = channel.broadcastStream(event: "*")
        let statuses = channel.statusChange
        do {
            try await channel.subscribeWithError()
        } catch {
            log("temps réel", error)
        }
        Task { [weak self] in
            for await message in messages { self?.receive(message) }
        }
        // Après une coupure, rattrape ce qui a été manqué pendant la déconnexion.
        Task { [weak self] in
            var wasSubscribed = false
            for await status in statuses {
                if status == .subscribed {
                    if wasSubscribed { await self?.pull() }
                    wasSubscribed = true
                }
            }
        }
    }

    private func receive(_ message: JSONObject) {
        let payload = message["payload"]?.objectValue ?? message
        guard let table = payload["table"]?.stringValue,
              let record = payload["record"],
              let type = Self.tables.first(where: { $0.table == table }),
              let json = try? JSONEncoder().encode(record) else { return }
        applyOne(type, json: json)
    }

    // MARK: Photos des machines

    private var photoCache: URL {
        let url = URL.cachesDirectory.appending(path: "sport-photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Enregistre la photo localement tout de suite ; l'envoi suit dès que le réseau le permet.
    func storePhoto(_ jpeg: Data, for exercise: SportExercise) {
        let path = "\(exercise.id)-\(UUID().uuidString.prefix(8).lowercased()).jpg"
        try? jpeg.write(to: photoCache.appending(path: path))
        exercise.photoPath = path
        var pending = UserDefaults.standard.stringArray(forKey: Self.pendingPhotosKey) ?? []
        pending.append(path)
        UserDefaults.standard.set(pending, forKey: Self.pendingPhotosKey)
        save(exercise)
    }

    func cachedPhoto(_ path: String) -> UIImage? {
        UIImage(contentsOfFile: photoCache.appending(path: path).path())
    }

    func photo(_ path: String) async -> UIImage? {
        if let image = cachedPhoto(path) { return image }
        guard let client, let data = try? await client.storage.from("sport-photos").download(path: path) else { return nil }
        try? data.write(to: photoCache.appending(path: path))
        return UIImage(data: data)
    }

    private func uploadPendingPhotos() async {
        guard let client else { return }
        var pending = UserDefaults.standard.stringArray(forKey: Self.pendingPhotosKey) ?? []
        for path in pending {
            guard let data = try? Data(contentsOf: photoCache.appending(path: path)) else {
                pending.removeAll { $0 == path }
                continue
            }
            do {
                try await client.storage.from("sport-photos")
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                pending.removeAll { $0 == path }
            } catch {
                log("photo", error)
                break
            }
        }
        UserDefaults.standard.set(pending, forKey: Self.pendingPhotosKey)
    }

    // MARK: Réseau

    /// Appel RPC PostgREST brut : le corps JSON est construit et lu ici, sans conversion intermédiaire.
    private func rpc(_ function: String, body: [String: Any]) async throws -> Data {
        guard let client, let baseURL else { throw URLError(.badURL) }
        let token = try await client.auth.session.accessToken
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/rpc/\(function)"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SportSyncError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func log(_ step: String, _ error: Error) {
        #if DEBUG
        print("[Sport] \(step) : \(error)")
        #endif
    }
}

enum SportSyncError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): "Supabase a répondu \(status) : \(message)"
        }
    }
}
