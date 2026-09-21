//
//  ManagedObjects.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import CoreData

// Written by hand rather than generated: the target defaults to MainActor isolation, and these
// rows are only ever touched on the writer context's queue.

@objc(CDTask)
nonisolated final class CDTask: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDTask> {
        NSFetchRequest<CDTask>(entityName: "CDTask")
    }

    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var details: String?
    @NSManaged var statusRaw: String?
    @NSManaged var sortIndex: Double
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    /// `deletedFlag`, never `isDeleted` — that name shadows `NSManagedObject.isDeleted`.
    @NSManaged var deletedFlag: Bool
}

@objc(CDPendingPush)
nonisolated final class CDPendingPush: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDPendingPush> {
        NSFetchRequest<CDPendingPush>(entityName: "CDPendingPush")
    }

    @NSManaged var id: UUID?
    @NSManaged var taskId: UUID?
    @NSManaged var queuedAt: Date?
    @NSManaged var pushedUpdatedAt: Date?
}
