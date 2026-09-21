//
//  ViewModelTests.swift
//  TackleTests
//
//  The logic the views defer to: what counts as saveable, and what the capsule says.
//

import Foundation
import Testing
@testable import Tackle

@Suite("Task editor")
struct TaskEditorTests {

    private func editor(for task: TaskItem? = nil) -> (TaskEditorViewModel, FakeRepository) {
        let repository = FakeRepository()
        let router = Router()
        return (TaskEditorViewModel(task: task, repository: repository, router: router), repository)
    }

    private func task(_ title: String, _ status: TaskStatus = .todo) -> TaskItem {
        TaskItem(title: title, details: "details", status: status, sortIndex: 1024)
    }

    @Test("A task needs a title")
    func titleIsRequired() {
        let (editor, _) = editor()
        #expect(!editor.canSave)

        editor.title = "something"
        #expect(editor.canSave)
    }

    @Test("A title of only whitespace doesn't count")
    func whitespaceIsNotATitle() {
        let (editor, _) = editor()

        editor.title = "   \n\t "

        #expect(!editor.canSave)
    }

    @Test("Saving without a title does nothing at all")
    func savingBlankIsANoOp() async {
        let (editor, repository) = editor()

        editor.save()

        try? await Task.sleep(for: .milliseconds(50))
        #expect(repository.created == nil)
        #expect(repository.updated == nil)
    }

    @Test("Saving a new task creates it, trimmed")
    func saveCreates() async {
        let (editor, repository) = editor()
        editor.title = "  Write the spec  "
        editor.details = "  with detail\n"
        editor.status = .inProgress

        editor.save()

        #expect(await eventually { repository.created != nil })
        #expect(repository.created == .init(title: "Write the spec", details: "with detail", status: .inProgress))
    }

    @Test("Saving an existing task updates it rather than creating another")
    func saveUpdates() async {
        let existing = task("old title")
        let (editor, repository) = editor(for: existing)
        editor.title = "new title"
        editor.status = .done

        editor.save()

        #expect(await eventually { repository.updated != nil })
        #expect(repository.updated?.id == existing.id)
        #expect(repository.updated?.title == "new title")
        #expect(repository.updated?.status == .done)
        #expect(repository.created == nil)
    }

    @Test("An editor opened on a task starts with that task's values")
    func existingTaskPopulatesTheFields() {
        let existing = task("a title", .done)
        let (editor, _) = editor(for: existing)

        #expect(editor.title == "a title")
        #expect(editor.details == "details")
        #expect(editor.status == .done)
        #expect(!editor.isNew)
    }

    @Test("An editor opened with nothing starts empty and in To Do")
    func newTaskStartsEmpty() {
        let (editor, _) = editor()

        #expect(editor.title.isEmpty)
        #expect(editor.status == .todo)
        #expect(editor.isNew)
    }
}

@Suite("Board actions")
@MainActor
struct BoardActionTests {

    private func board(
        tasks: [TaskItem],
        refuses: Bool = false
    ) async -> (BoardViewModel, FakeRepository, Router) {
        let repository = FakeRepository(seed: tasks, refuses: refuses)
        let router = Router()
        let viewModel = BoardViewModel(repository: repository, router: router, status: SyncStatus())
        await viewModel.observe()
        return (viewModel, repository, router)
    }

    private func task(_ title: String, _ status: TaskStatus = .todo) -> TaskItem {
        TaskItem(title: title, status: status, sortIndex: 1024)
    }

    @Test("An empty board is reported as empty")
    func emptiness() async {
        let (empty, _, _) = await board(tasks: [])
        #expect(empty.isEmpty)

        let (filled, _, _) = await board(tasks: [task("a")])
        #expect(!filled.isEmpty)
    }

    @Test("Tasks are offered per section")
    func tasksPerSection() async {
        let (viewModel, _, _) = await board(tasks: [task("a"), task("b", .done)])

        #expect(viewModel.tasks(in: .todo).map(\.title) == ["a"])
        #expect(viewModel.tasks(in: .done).map(\.title) == ["b"])
        #expect(viewModel.tasks(in: .inProgress).isEmpty)
    }

    @Test("Confirming a deletion deletes it and closes the dialog")
    func confirmDeletion() async {
        let item = task("a")
        let (viewModel, repository, _) = await board(tasks: [item])
        viewModel.pendingDeletion = item

        viewModel.confirmDeletion()

        #expect(viewModel.pendingDeletion == nil)
        #expect(await eventually { repository.deleted == item.id })
    }

    @Test("Confirming with nothing pending does nothing")
    func confirmWithoutAPendingDeletion() async {
        let (viewModel, repository, _) = await board(tasks: [task("a")])

        viewModel.confirmDeletion()

        try? await Task.sleep(for: .milliseconds(50))
        #expect(repository.deleted == nil)
    }

    /// The Move dialog should never offer the section the task is already in.
    @Test("Move destinations exclude the task's own section")
    func destinations() async {
        let (viewModel, _, _) = await board(tasks: [])

        #expect(viewModel.destinations(for: task("a", .todo)) == [.inProgress, .done])
        #expect(viewModel.destinations(for: task("a", .done)) == [.todo, .inProgress])
    }

    @Test("A failed write surfaces as an alert rather than being swallowed")
    func failureIsReported() async {
        let item = task("a")
        let (viewModel, _, _) = await board(tasks: [item], refuses: true)

        viewModel.move(item, to: .done)

        #expect(await eventually { viewModel.saveFailed })
    }

    @Test("Opening an editor presents it")
    func editingPresentsTheEditor() async {
        let item = task("a")
        let (viewModel, _, router) = await board(tasks: [item])

        viewModel.edit(item)
        #expect(router.sheet == .editor(item))

        viewModel.newTask()
        #expect(router.sheet == .editor(nil))
    }
}

/// The capsule is the only place the app talks about sync, and silence is the synced state.
@Suite("Status capsule")
@MainActor
struct StatusCapsuleTests {

    private func board(
        tasks: [TaskItem],
        online: Bool = true,
        pushing: Bool = false,
        loadedRemote: Bool = true
    ) async -> BoardViewModel {
        let status = SyncStatus()
        status.isOnline = online
        status.isPushing = pushing
        status.hasLoadedRemote = loadedRemote

        let viewModel = BoardViewModel(
            repository: FakeRepository(seed: tasks),
            router: Router(),
            status: status
        )
        await viewModel.observe()
        return viewModel
    }

    private func task(synced: Bool) -> TaskItem {
        TaskItem(title: "a", status: .todo, sortIndex: 1024, isSynced: synced)
    }

    @Test("Nothing to say means no capsule")
    func silenceWhenSynced() async {
        let viewModel = await board(tasks: [task(synced: true)])

        #expect(viewModel.capsuleText == nil)
    }

    @Test("Queued work with nothing in flight reads as offline")
    func offlineCount() async {
        let viewModel = await board(tasks: [task(synced: false), task(synced: false)])

        #expect(viewModel.capsuleText == "Offline · 2 waiting")
    }

    /// "Offline" is the honest default: a push that isn't moving is indistinguishable from no
    /// network, whether the cause is airplane mode or an unreachable server.
    @Test("Queued work that is actually moving reads as syncing")
    func syncingWhilePushing() async {
        let viewModel = await board(tasks: [task(synced: false)], pushing: true)

        #expect(viewModel.capsuleText == "Syncing…")
    }

    @Test("Before the first snapshot arrives, the capsule says so")
    func checkingOnFirstLaunch() async {
        let viewModel = await board(tasks: [task(synced: true)], loadedRemote: false)

        #expect(viewModel.capsuleText == "Checking for tasks…")
    }

    @Test("Offline and unheard-from is not reported as checking")
    func offlineDoesNotClaimToBeChecking() async {
        let viewModel = await board(tasks: [task(synced: true)], online: false, loadedRemote: false)

        #expect(viewModel.capsuleText == nil)
    }

    @Test("Queued work outranks having heard nothing yet")
    func queuedWorkWins() async {
        let viewModel = await board(tasks: [task(synced: false)], loadedRemote: false)

        #expect(viewModel.capsuleText == "Offline · 1 waiting")
    }

    @Test("The glyph follows whether a push is moving")
    func glyph() async {
        let idle = await board(tasks: [task(synced: false)])
        #expect(idle.capsuleGlyph == "clock")

        let pushing = await board(tasks: [task(synced: false)], pushing: true)
        #expect(pushing.capsuleGlyph == "arrow.trianglehead.2.clockwise")
    }
}
