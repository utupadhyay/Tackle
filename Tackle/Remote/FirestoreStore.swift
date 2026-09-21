//
//  FirestoreStore.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import FirebaseFirestore
import Foundation

/// The only type in the project that imports Firebase. Everything above it uses
/// `RemoteStoreProtocol`, which is what lets the sync tests run against a fake.
actor FirestoreStore: RemoteStoreProtocol {
    /// One shared board: every install reads and writes the same collection.
    private nonisolated var collection: CollectionReference {
        Firestore.firestore().collection("tasks")
    }

    /// Create, update and delete are all this one call — a whole-document upsert, with delete
    /// carried as `deleted: true`. The client-generated UUID is the document ID, so a retried
    /// push overwrites itself instead of duplicating.
    func push(_ task: TaskItem) async throws {
        try await collection.document(task.id.uuidString).setData(
            [
                "title": task.title,
                "details": task.details,
                "status": task.status.rawValue,
                "sortIndex": task.sortIndex,
                "createdAt": Timestamp(date: task.createdAt),
                "updatedAt": Timestamp(date: task.updatedAt),
                "deleted": task.isDeleted
            ],
            merge: true
        )
    }

    /// Live stream. The first value is the full collection, then one per remote change.
    /// This IS the fetch — there is no separate pull and no `lastSyncedAt`.
    nonisolated func remoteChanges() -> AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            let registration = collection.addSnapshotListener { snapshot, _ in
                guard let snapshot else {
                    // Offline or transient. Stay attached; Firestore reconnects itself.
                    return
                }
                continuation.yield(snapshot.documents.compactMap(TaskItem.init(document:)))
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }
}

private extension TaskItem {
    /// Hand-written rather than `Codable`: a malformed document returns nil and is skipped,
    /// so one bad row can't fail the whole snapshot.
    nonisolated init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard let id = UUID(uuidString: document.documentID),
              let title = data["title"] as? String,
              let statusRaw = data["status"] as? String,
              let status = TaskStatus(rawValue: statusRaw),
              let sortIndex = data["sortIndex"] as? Double,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.init(
            id: id,
            title: title,
            details: data["details"] as? String ?? "",
            status: status,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: data["deleted"] as? Bool ?? false
        )
    }
}
