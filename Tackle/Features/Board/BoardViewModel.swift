//
//  BoardViewModel.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Foundation

/// One line of the board: either a stage heading or a task sitting under it.
enum BoardRow: Identifiable {
    case header(TaskStatus)
    case task(TaskItem)

    var id: String {
        switch self {
        case .header(let status): "header-\(status.rawValue)"
        case .task(let task): "task-\(task.id)"
        }
    }
}

@Observable
final class BoardViewModel {
    private(set) var tasks: [TaskItem] = []
    var searchText = ""
    var pendingDeletion: TaskItem?
    var taskBeingMoved: TaskItem?
    var saveFailed = false

    private let repository: TaskRepositoryProtocol
    private let router: Router
    private let status: SyncStatus

    init(repository: TaskRepositoryProtocol, router: Router, status: SyncStatus) {
        self.repository = repository
        self.router = router
        self.status = status
    }

    var isEmpty: Bool { tasks.isEmpty }

    // MARK: - Status capsule

    private var waitingCount: Int {
        tasks.count { !$0.isSynced }
    }

    /// Nil means no capsule at all. Silence is the synced state.
    ///
    /// Queued work only reads as "Syncing…" while a push is actually in flight — anything else
    /// queued and not moving is reported as offline, which stays true whether the network is
    /// down or the server is simply unreachable.
    var capsuleText: String? {
        let waiting = waitingCount
        if waiting > 0 {
            return status.isPushing ? "Syncing…" : "Offline · \(waiting) waiting"
        }
        // The one thing the app genuinely doesn't know yet: whether the server has anything.
        guard status.isOnline, !status.hasLoadedRemote else { return nil }
        return "Checking for tasks…"
    }

    var capsuleGlyph: String {
        status.isPushing ? "arrow.trianglehead.2.clockwise" : "clock"
    }

    // MARK: - Search

    /// Whitespace alone is not a search. Trimming here means the board doesn't empty itself
    /// the moment a space is typed between two words.
    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !query.isEmpty }

    var hasResults: Bool { tasks.contains(where: matches) }

    private func matches(_ task: TaskItem) -> Bool {
        let query = query
        guard !query.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(query)
            || task.details.localizedCaseInsensitiveContains(query)
    }

    // MARK: - Rows

    func tasks(in status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status && matches($0) }
    }

    /// Every stage heading followed by its tasks, as one flat list.
    ///
    /// A drag inside a `List` is a reorder session owned by the enclosing `ForEach`, so with
    /// one `ForEach` per section a drop into a different section is never delivered. Flattening
    /// puts every row in the same session, which is what makes dragging across stages work.
    ///
    /// The first stage's heading is absent: the board pins it above the `ForEach` so nothing
    /// can be dropped above it. Everything here is draggable, and everything draggable is here.
    var rows: [BoardRow] {
        TaskStatus.allCases.flatMap { status in
            let tasks = tasks(in: status).map(BoardRow.task)
            return status == TaskStatus.allCases[0] ? tasks : [BoardRow.header(status)] + tasks
        }
    }

    /// Core Data answers immediately, so there is no loading state to model here.
    func observe() async {
        for await tasks in repository.tasks {
            self.tasks = tasks
        }
    }

    /// Pull to refresh — the only manual sync gesture, and deliberately the only one. The engine
    /// retries on connectivity and on every write, so this exists to be reached for, not needed.
    func refresh() async {
        await repository.sync()
    }

    // MARK: - Navigation

    func newTask() { router.present(.editor(nil)) }
    func edit(_ task: TaskItem) { router.present(.editor(task)) }

    func editorViewModel(for task: TaskItem?) -> TaskEditorViewModel {
        TaskEditorViewModel(task: task, repository: repository, router: router)
    }

    // MARK: - Mutations

    func confirmDeletion() {
        guard let task = pendingDeletion else { return }
        pendingDeletion = nil
        perform { try await self.repository.delete(task.id) }
    }

    func destinations(for task: TaskItem) -> [TaskStatus] {
        TaskStatus.allCases.filter { $0 != task.status }
    }

    /// Picking a section from the Move dialog has no position to go on, so it lands at the top
    /// of the target. The repository owns that rule.
    func move(_ task: TaskItem, to status: TaskStatus) {
        perform { try await self.repository.changeStatus(task.id, to: status) }
    }

    /// A row dragged anywhere on the board, whether it stays under its own heading or crosses
    /// to another. A drag names a position, so it is honoured either way — the top-landing
    /// rule is for the Move dialog and the editor, which don't have one.
    func move(from source: IndexSet, to destination: Int) {
        let rows = rows
        // The indices describe the list as it was drawn. A pull from Firestore can land
        // mid-drag and replace the rows underneath them, so they are checked, not trusted.
        guard let fromIndex = source.first, rows.indices.contains(fromIndex),
              case .task(let moved) = rows[fromIndex]
        else { return }

        let destination = min(max(destination, 0), rows.count)
        let target = stage(at: destination, in: rows)
        let section = tasks(in: target)
        let start = sectionStart(of: target, in: rows)
        let localDestination = min(max(destination - start, 0), section.count)

        guard target != moved.status else {
            return move(in: section, from: IndexSet(integer: fromIndex - start), to: localDestination)
        }

        // No off-by-one on this path: the row is arriving from another section, so it isn't
        // among the neighbours being counted.
        place(
            moved.id,
            in: target,
            above: localDestination > 0 ? section[localDestination - 1].id : nil,
            below: localDestination < section.count ? section[localDestination].id : nil
        )
    }

    /// Writes the move, and lands it locally first.
    ///
    /// `onMove` hands the list back expecting the data to have already changed, but the write
    /// is a round trip through Core Data. Without the local landing the List reverts to the
    /// old arrangement and re-animates when the stream catches up, which is the flicker.
    /// This resolves the same neighbours the repository will, so the stream's answer matches
    /// what is already on screen and nothing moves twice.
    private func place(_ id: UUID, in status: TaskStatus, above: UUID?, below: UUID?) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].status = status
            tasks[index].sortIndex = SortIndex.between(
                above: above.flatMap { neighbour in tasks.first { $0.id == neighbour }?.sortIndex },
                below: below.flatMap { neighbour in tasks.first { $0.id == neighbour }?.sortIndex }
            )
            tasks.sort(by: TaskItem.boardOrder)
        }

        perform { try await self.repository.move(id, to: status, above: above, below: below) }
    }

    /// The stage owning a flat insertion point: the nearest heading at or above it.
    private func stage(at destination: Int, in rows: [BoardRow]) -> TaskStatus {
        for row in rows[..<min(destination, rows.count)].reversed() {
            if case .header(let status) = row { return status }
        }
        return TaskStatus.allCases[0]
    }

    /// Where a stage's tasks begin. The first stage has no heading row of its own, so its
    /// tasks start at zero.
    private func sectionStart(of status: TaskStatus, in rows: [BoardRow]) -> Int {
        let header = rows.firstIndex {
            guard case .header(let candidate) = $0 else { return false }
            return candidate == status
        }
        return header.map { $0 + 1 } ?? 0
    }

    /// SwiftUI computes `destination` before the row is removed, so it is off by one
    /// when a task moves downward.
    func move(in section: [TaskItem], from source: IndexSet, to destination: Int) {
        guard let fromIndex = source.first, section.indices.contains(fromIndex) else { return }

        var reordered = section
        let moved = reordered.remove(at: fromIndex)
        let insertAt = min(max(destination > fromIndex ? destination - 1 : destination, 0), reordered.count)
        reordered.insert(moved, at: insertAt)

        let above = insertAt > 0 ? reordered[insertAt - 1].id : nil
        let below = insertAt < reordered.count - 1 ? reordered[insertAt + 1].id : nil

        place(moved.id, in: moved.status, above: above, below: below)
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { saveFailed = true }
        }
    }
}
