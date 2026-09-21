//
//  CoreDataStack.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import CoreData

/// Owns the persistent container and the single writer context every write goes through.
nonisolated final class CoreDataStack: Sendable {
    let container: NSPersistentContainer
    let writer: NSManagedObjectContext

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Tackle")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data failed to load: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true

        writer = container.newBackgroundContext()
        writer.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
