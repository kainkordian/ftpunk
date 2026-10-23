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
    public init(inMemory: Bool = false, url: URL? = nil) throws {
        container = NSPersistentContainer(name: "FTPunk", managedObjectModel: Self.model())
        let description = NSPersistentStoreDescription()
        if inMemory { description.type = NSInMemoryStoreType }
        else { description.url = url ?? NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("FTPunk.sqlite") }
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
            try context.save()
        } catch { context.rollback(); throw error }
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
        guard let record = try rows("Profile").first else { return RiderProfile() }
        return try decoder.decode(RiderProfile.self, from: payload(record))
    }
    public func saveProfile(_ profile: RiderProfile) throws {
        do {
            let record = try rows("Profile").first ?? insert("Profile")
            record.setValue("rider", forKey: "key"); record.setValue(try encoder.encode(profile), forKey: "payload")
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
    private static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel(); model.versionIdentifiers = ["FTPunkV1"]
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
            entity("Upload", [("id", .UUIDAttributeType), ("accountID", .stringAttributeType), ("payload", .binaryDataAttributeType)], unique: ["id"])
        ]
        return model
    }
}

public enum StoreError: Error { case sampleHistoryChanged, corruptRecord }
