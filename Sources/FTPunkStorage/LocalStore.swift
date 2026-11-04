import Foundation
import CoreData
import FTPunkDomain

/// Core Data's SQLite store provides atomic checkpoints without a third-party dependency.
/// The model is explicit and versioned; domain values never expose managed objects.
@MainActor public final class LocalStore: SessionRepository, ProfileRepository, UploadQueueRepository {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Preview scenarios may only seed a store that never touches disk.
    public let isInMemory: Bool
    public init(inMemory: Bool = false, url: URL? = nil) throws {
        isInMemory = inMemory
        container = NSPersistentContainer(name: "FTPunk", managedObjectModel: Self.model())
        let description = NSPersistentStoreDescription()
        if inMemory { description.type = NSInMemoryStoreType }
        else { description.url = url ?? NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("FTPunk.sqlite") }
        if !inMemory, let storeURL = description.url { try Self.migrateIfNeeded(at: storeURL) }
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.viewContext
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }
    public func save(_ session: TestSession) throws {
        do {
            try stage(session)
            // Recordings from the removed story (older builds, the web app) still credit the rider's legacy progress, idempotently.
            if !session.isDemo, session.adventureEnabled == true {
                var profile = try profiles().first { $0.id == session.riderID } ?? RiderProfile(id: session.riderID, name: session.riderName)
                var progress = profile.cycleProgress ?? CycleProgress(); progress.credit(session); profile.cycleProgress = progress
                try stageProfile(profile)
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    private func stage(_ session: TestSession) throws {
        let record = try rows("Session", matching: "id == %@", session.id as NSUUID).first ?? insert("Session")
        let oldCount = (record.value(forKey: "sampleCount") as? Int) ?? 0
        guard session.samples.count >= oldCount else { throw StoreError.sampleHistoryChanged }
        record.setValue(session.id, forKey: "id"); record.setValue(session.startedAt, forKey: "startedAt")
        var metadata = session; metadata.samples = []
        record.setValue(try encoder.encode(metadata), forKey: "payload")
        for index in oldCount..<session.samples.count {
            let row = insert("Sample")
            row.setValue(session.id, forKey: "sessionID"); row.setValue(index, forKey: "sequence")
            row.setValue(try encoder.encode(session.samples[index]), forKey: "payload")
        }
        record.setValue(session.samples.count, forKey: "sampleCount")
    }
    public func sessions() throws -> [TestSession] {
        try rows("Session", sort: [NSSortDescriptor(key: "startedAt", ascending: false)]).map { record in
            var session = try decoder.decode(TestSession.self, from: payload(record))
            session.samples = try rows("Sample", matching: "sessionID == %@", session.id as NSUUID,
                                       sort: [NSSortDescriptor(key: "sequence", ascending: true)])
                .map { try decoder.decode(RideSample.self, from: payload($0)) }
            return session
        }
    }
    public func recoverInterruptedSessions() throws {
        for var session in try sessions() where session.endedAtOffset == nil {
            if session.rampEnd == nil { session.outcome = .interrupted; session.result = nil }
            session.endReason = "Recovered after the application stopped."
            session.endedAtOffset = session.samples.last?.time ?? 0
            try save(session)
        }
        for var job in try uploadJobs() where job.status == .uploading {
            job.status = .queued; try saveUploadJob(job)
        }
    }
    public func deleteSession(id: UUID) throws {
        do {
            for row in try rows("Session", matching: "id == %@", id as NSUUID) { context.delete(row) }
            for row in try rows("Sample", matching: "sessionID == %@", id as NSUUID) { context.delete(row) }
            for row in try rows("Upload") {
                if try decoder.decode(ActivityUploadJob.self, from: payload(row)).sessionID == id { context.delete(row) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    public func loadProfile() throws -> RiderProfile {
        try profiles().first ?? RiderProfile()
    }
    public func profiles() throws -> [RiderProfile] {
        try rows("Profile").map { try decoder.decode(RiderProfile.self, from: payload($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func saveProfile(_ profile: RiderProfile) throws {
        do {
            var profile = profile
            if let saved = try profiles().first(where: { $0.id == profile.id })?.cycleProgress {
                var progress = profile.cycleProgress ?? CycleProgress()
                for (id, ms) in saved.credits { progress.credits[id] = max(progress.credits[id] ?? 0, ms) }
                profile.cycleProgress = progress
            }
            try stageProfile(profile)
            try context.save()
        } catch { context.rollback(); throw error }
    }
    private func stageProfile(_ profile: RiderProfile) throws {
            let key = profile.id.uuidString
            let existing = try rows("Profile", matching: "key == %@", key).first
            let legacy = profile.id == RiderProfile.legacyID ? try rows("Profile", matching: "key == %@", "rider").first : nil
            let record = existing ?? legacy ?? insert("Profile")
            record.setValue(key, forKey: "key"); record.setValue(try encoder.encode(profile), forKey: "payload")
    }
    /// Custom workouts share the Workout table under keys that start with this prefix (no store migration needed);
    /// `CachedWorkout` ids never do.
    private static let customPrefix = "custom:"
    private func isCustom(_ row: NSManagedObject) -> Bool { (row.value(forKey: "key") as? String)?.hasPrefix(Self.customPrefix) == true }
    public func workouts() throws -> [CachedWorkout] {
        try rows("Workout").filter { !isCustom($0) }.map { try decoder.decode(CachedWorkout.self, from: payload($0)) }.sorted { $0.savedAt > $1.savedAt }
    }
    /// The riders' own workouts, newest first.
    public func customWorkouts() throws -> [CustomWorkout] {
        try rows("Workout").filter(isCustom).map { try decoder.decode(CustomWorkout.self, from: payload($0)) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private func stageCustomWorkout(_ workout: CustomWorkout) throws {
        try workout.validate()
        let key = Self.customPrefix + workout.id.uuidString.lowercased()
        let existing = try rows("Workout", matching: "key == %@", key).first
        if let existing, try decoder.decode(CustomWorkout.self, from: payload(existing)).riderID != workout.riderID { throw ArchiveError.identityConflict }
        let row = existing ?? insert("Workout")
        row.setValue(key, forKey: "key"); row.setValue(try encoder.encode(workout), forKey: "payload")
    }
    /// At most 200 per rider.
    public func saveCustomWorkout(_ workout: CustomWorkout) throws {
        do {
            try stageCustomWorkout(workout)
            context.processPendingChanges()
            let count = try customWorkouts().filter { $0.riderID == workout.riderID }.count
            guard count <= CustomWorkout.maximumPerRider else { throw ArchiveError.invalid("Each rider can have up to \(CustomWorkout.maximumPerRider) of their own workouts.") }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    public func deleteCustomWorkout(id: UUID) throws {
        do {
            for row in try rows("Workout", matching: "key == %@", Self.customPrefix + id.uuidString.lowercased()) { context.delete(row) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    private func stageWorkout(_ workout: CachedWorkout) throws {
        try workout.validate()
        let existing = try rows("Workout", matching: "key == %@", workout.id).first
        if let existing, try decoder.decode(CachedWorkout.self, from: payload(existing)).riderID != workout.riderID { throw ArchiveError.identityConflict }
        let row = existing ?? insert("Workout")
        row.setValue(workout.id, forKey: "key"); row.setValue(try encoder.encode(workout), forKey: "payload")
    }
    public func saveWorkouts(_ workouts: [CachedWorkout]) throws {
        do {
            for workout in workouts { try stageWorkout(workout) }
            guard try rows("Workout").filter({ !isCustom($0) }).count <= 2000 else { throw ArchiveError.invalid("The library is full. Remove some workouts first.") }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    public func deleteWorkout(id: String) throws {
        do { for row in try rows("Workout", matching: "key == %@", id) { context.delete(row) }; try context.save() }
        catch { context.rollback(); throw error }
    }
    public func portableArchive() throws -> PortableArchive {
        let sessions = try sessions()
        var riders = try profiles()
        // Legacy recordings can predate the profile table. Preserve their identity.
        for session in sessions where !riders.contains(where: { $0.id == session.riderID }) {
            riders.append(RiderProfile(id: session.riderID, name: session.riderName))
        }
        if riders.isEmpty { riders = [RiderProfile()] }
        return PortableArchive(profiles: riders, sessions: sessions, workouts: try workouts(), customWorkouts: try customWorkouts())
    }
    /// Replaces only the explicitly reviewed incoming rider identities in one transaction.
    /// Upload jobs for replaced activities are cancelled; authorization never travels in archives.
    public func restore(_ archive: PortableArchive) throws {
        try archive.validate()
        let incomingRiders = Set(archive.profiles.map(\.id))
        let incomingSessions = Set(archive.activities.map { $0.session.id })
        let existing = try sessions()
        guard !existing.contains(where: { incomingSessions.contains($0.id) && !incomingRiders.contains($0.riderID) }) else {
            throw ArchiveError.identityConflict
        }
        let incomingWorkoutIDs = Set((archive.workouts ?? []).map(\.id))
        guard try !workouts().contains(where: { incomingWorkoutIDs.contains($0.id) && !incomingRiders.contains($0.riderID) }) else { throw ArchiveError.identityConflict }
        let incomingCustomIDs = Set((archive.customWorkouts ?? []).map(\.id))
        guard try !customWorkouts().contains(where: { incomingCustomIDs.contains($0.id) && !incomingRiders.contains($0.riderID) }) else { throw ArchiveError.identityConflict }
        let removedIDs = Set(existing.filter { incomingRiders.contains($0.riderID) }.map(\.id))
        do {
            for row in try rows("Session") where (row.value(forKey: "id") as? UUID).map({ removedIDs.contains($0) }) == true { context.delete(row) }
            for row in try rows("Sample") where (row.value(forKey: "sessionID") as? UUID).map({ removedIDs.contains($0) }) == true { context.delete(row) }
            for row in try rows("Upload") {
                if removedIDs.contains(try decoder.decode(ActivityUploadJob.self, from: payload(row)).sessionID) { context.delete(row) }
            }
            for row in try rows("Profile") {
                if incomingRiders.contains(try decoder.decode(RiderProfile.self, from: payload(row)).id) { context.delete(row) }
            }
            for row in try rows("Workout") {
                let rider = isCustom(row) ? try decoder.decode(CustomWorkout.self, from: payload(row)).riderID : try decoder.decode(CachedWorkout.self, from: payload(row)).riderID
                if incomingRiders.contains(rider) { context.delete(row) }
            }
            context.processPendingChanges()
            for profile in archive.profiles {
                let row = insert("Profile")
                row.setValue(profile.id.uuidString, forKey: "key"); row.setValue(try encoder.encode(profile), forKey: "payload")
            }
            for activity in archive.activities { try stage(activity.session) }
            for workout in archive.workouts ?? [] { try stageWorkout(workout) }
            for workout in archive.customWorkouts ?? [] { try stageCustomWorkout(workout) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    public func uploadJobs() throws -> [ActivityUploadJob] {
        try rows("Upload").map { try decoder.decode(ActivityUploadJob.self, from: payload($0)) }
    }
    public func saveUploadJob(_ job: ActivityUploadJob) throws {
        do {
            let row = try rows("Upload", matching: "id == %@", job.id as NSUUID).first ?? insert("Upload")
            row.setValue(job.id, forKey: "id"); row.setValue(job.accountID, forKey: "accountID")
            row.setValue(try encoder.encode(job), forKey: "payload")
            try context.save()
        } catch { context.rollback(); throw error }
    }
    public func deleteUploadJobs(accountID: String) throws {
        do {
            for row in try rows("Upload", matching: "accountID == %@", accountID) { context.delete(row) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    public func deleteUploadJob(id: UUID) throws {
        do {
            for row in try rows("Upload", matching: "id == %@", id as NSUUID) { context.delete(row) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    /// Removes every record so a preview scenario can start from a known state.
    /// Refuses to run on a persistent store.
    public func eraseAllForPreview() throws {
        guard isInMemory else { throw StoreError.persistentStoreProtected }
        do {
            for entity in ["Session", "Sample", "Profile", "Workout", "Upload"] { for row in try rows(entity) { context.delete(row) } }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    private func insert(_ entity: String) -> NSManagedObject { NSEntityDescription.insertNewObject(forEntityName: entity, into: context) }
    private func payload(_ row: NSManagedObject) throws -> Data {
        guard let data = row.value(forKey: "payload") as? Data else { throw StoreError.corruptRecord }
        return data
    }
    private func rows(_ entity: String, matching format: String? = nil, _ value: CVarArg? = nil,
                      sort: [NSSortDescriptor] = []) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        if let format, let value { request.predicate = NSPredicate(format: format, value) }
        request.sortDescriptors = sort
        return try context.fetch(request)
    }
    // The original model was constructed in code, so Core Data cannot discover
    // it in a .momd bundle. Keep it available for a bounded, explicit migration.
    private static func migrateIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        let destination = model()
        guard !destination.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }
        let source = model(includeWorkouts: false)
        guard source.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { throw StoreError.corruptRecord }
        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: source, destinationModel: destination)
        let temporary = url.deletingLastPathComponent().appendingPathComponent("workout-migration-\(UUID()).sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: destination)
        defer { try? coordinator.destroyPersistentStore(at: temporary, ofType: NSSQLiteStoreType, options: nil) }
        try NSMigrationManager(sourceModel: source, destinationModel: destination).migrateStore(from: url, sourceType: NSSQLiteStoreType, options: nil, with: mapping, toDestinationURL: temporary, destinationType: NSSQLiteStoreType, destinationOptions: nil)
        let backup = url.appendingPathExtension("pre-workouts-\(UUID()).sqlite")
        try coordinator.replacePersistentStore(at: backup, destinationOptions: nil, withPersistentStoreFrom: url, sourceOptions: nil, ofType: NSSQLiteStoreType)
        try coordinator.replacePersistentStore(at: url, destinationOptions: nil, withPersistentStoreFrom: temporary, sourceOptions: nil, ofType: NSSQLiteStoreType)
    }
    static func model(includeWorkouts: Bool = true) -> NSManagedObjectModel {
        let model = NSManagedObjectModel(); model.versionIdentifiers = [includeWorkouts ? "FTPunkV2" : "FTPunkV1"]
        func entity(_ name: String, _ fields: [(String, NSAttributeType)], unique: [String]) -> NSEntityDescription {
            let result = NSEntityDescription(); result.name = name; result.managedObjectClassName = "NSManagedObject"
            result.properties = fields.map { name, type in
                let field = NSAttributeDescription(); field.name = name; field.attributeType = type
                field.isOptional = false
                if type == .integer64AttributeType { field.defaultValue = 0 }
                return field
            }
            result.uniquenessConstraints = [unique]; return result
        }
        model.entities = [
            entity("Session", [("id", .UUIDAttributeType), ("startedAt", .dateAttributeType), ("payload", .binaryDataAttributeType), ("sampleCount", .integer64AttributeType)], unique: ["id"]),
            entity("Sample", [("sessionID", .UUIDAttributeType), ("sequence", .integer64AttributeType), ("payload", .binaryDataAttributeType)], unique: ["sessionID", "sequence"]),
            entity("Profile", [("key", .stringAttributeType), ("payload", .binaryDataAttributeType)], unique: ["key"]),
            entity("Workout", [("key", .stringAttributeType), ("payload", .binaryDataAttributeType)], unique: ["key"]),
            entity("Upload", [("id", .UUIDAttributeType), ("accountID", .stringAttributeType), ("payload", .binaryDataAttributeType)], unique: ["id"])
        ]
        if !includeWorkouts { model.entities.removeAll { $0.name == "Workout" } }
        return model
    }
}

public enum StoreError: Error, LocalizedError {
    case sampleHistoryChanged, corruptRecord, persistentStoreProtected
    public var errorDescription: String? {
        self == .persistentStoreProtected ? "Preview scenarios never modify the persistent store." : "The local store could not read or write a record."
    }
}
