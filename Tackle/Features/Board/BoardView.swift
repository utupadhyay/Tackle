//
//  BoardView.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

struct BoardView: View {
    @State private var viewModel: BoardViewModel
    private let router: Router

    init(viewModel: BoardViewModel, router: Router) {
        _viewModel = State(initialValue: viewModel)
        self.router = router
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var viewModel = viewModel

        NavigationStack(path: $router.path) {
            board
                .navigationTitle("Tasks")
                // Under the title, not in the bottom bar it defaults to: the bottom edge
                // already carries the add button and the status capsule.
                .searchable(
                    text: $viewModel.searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search tasks"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                .overlay(alignment: .bottomTrailing) { newTaskButton }
                .overlay(alignment: .bottomLeading) { statusCapsule }
                .navigationDestination(for: Route.self, destination: destination)
        }
        .task { await viewModel.observe() }
        .sheet(item: $router.sheet, content: destination)
        .confirmationDialog(
            "Delete Task",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }
            )
        ) {
            Button("Delete Task", role: .destructive) { viewModel.confirmDeletion() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Move Task",
            isPresented: Binding(
                get: { viewModel.taskBeingMoved != nil },
                set: { if !$0 { viewModel.taskBeingMoved = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.taskBeingMoved
        ) { task in
            ForEach(viewModel.destinations(for: task), id: \.self) { status in
                // "Move to Done" rather than "Done", which reads as dismissing the dialog.
                Button("Move to \(status.title)") { viewModel.move(task, to: status) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Unable to save changes", isPresented: $viewModel.saveFailed) {}
    }

    // MARK: - Board

    @ViewBuilder
    private var board: some View {
        if viewModel.isEmpty {
            emptyState
        } else if !viewModel.hasResults {
            // Distinct from an empty board: there is work here, just none matching.
            ContentUnavailableView.search(text: viewModel.searchText)
                .background(Theme.canvas)
        } else {
            BoardList(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var statusCapsule: some View {
        if let text = viewModel.capsuleText {
            StatusPill(text: text, glyph: viewModel.capsuleGlyph)
                .padding(20)
                .transition(.opacity)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No tasks yet")
                    .fontDesign(.rounded)
            } icon: {
                Image(systemName: "checklist")
                    .foregroundStyle(Theme.todo)
            }
        } description: {
            Text("Create your first task to start tracking work across To Do, In Progress and Done.")
                .foregroundStyle(Theme.labelSecondary)
        }
        .background(Theme.canvas)
    }

    private var newTaskButton: some View {
        Button {
            viewModel.newTask()
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(Theme.tint)
        .padding(20)
        .accessibilityLabel("New Task")
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .editor(let task):
            TaskEditorView(viewModel: viewModel.editorViewModel(for: task))
        }
    }
}

/// The list itself, split out so it can read `editMode`. That value is published by the
/// NavigationStack, which `BoardView` owns and therefore sits above.
private struct BoardList: View {
    let viewModel: BoardViewModel

    @Environment(\.editMode) private var editMode

    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    /// How far the card holds back from the edge of the screen.
    ///
    /// The reorder grabber is placed against the screen rather than against the row's insets,
    /// so at the normal inset it lands just inside the card and crowds its edge. Editing pulls
    /// the card back far enough to leave the grabber a gutter of its own.
    private var cardTrailingInset: CGFloat { isEditing ? 48 : 16 }

    /// Row content sits one card's-width of padding inside the card it is drawn on.
    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 3, leading: 32, bottom: 3, trailing: cardTrailingInset + 16)
    }

    var body: some View {
        List {
            // Outside the ForEach, so the drag can't reach above it. Inside, the List offers
            // a slot above the heading, shoves it down as you drag past, and then has to undo
            // that when the task lands underneath it instead.
            header(for: TaskStatus.allCases[0])

            // One flat ForEach, not a Section per stage: a List confines a drag to the
            // ForEach it started in, so sections would make cross-stage drops impossible.
            ForEach(viewModel.rows) { row in
                switch row {
                case .header(let status):
                    header(for: status)
                case .task(let task):
                    taskRow(task)
                }
            }
            .onMove { viewModel.move(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .refreshable { await viewModel.refresh() }
    }

    private func header(for status: TaskStatus) -> some View {
        SectionHeader(status: status, count: viewModel.tasks(in: status).count)
            .padding(.top, status == TaskStatus.allCases[0] ? 0 : 16)
            .padding(.bottom, 4)
            .listRowBackground(Theme.canvas)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
            // Headings can't be reordered, so they shouldn't offer a grabber while editing.
            // They stay movable the rest of the time because a List offers no insertion point
            // beside a pinned row, which would put the top of every stage out of reach.
            // Dragging one is ignored when the move is resolved.
            .moveDisabled(isEditing)
            .deleteDisabled(true)
    }

    private func taskRow(_ task: TaskItem) -> some View {
        TaskRow(task: task)
            // The card is drawn as the row background rather than inside the row so the
            // swipe actions and drag preview follow its rounded edge.
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
                    .padding(.vertical, 3)
                    .padding(.leading, 16)
                    .padding(.trailing, cardTrailingInset)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
            // A filtered list hides the neighbours a drop is measured against, so a move made
            // during a search would resolve to a position that is wrong once it clears.
            .moveDisabled(viewModel.isSearching)
            .onTapGesture { viewModel.edit(task) }
            .swipeActions(edge: .trailing) {
                Button("Delete") { viewModel.pendingDeletion = task }
                    .tint(Theme.destructive)
            }
            .swipeActions(edge: .leading) {
                Button("Move") { viewModel.taskBeingMoved = task }
                    .tint(Theme.tint)
            }
    }
}

/// Stage dot, the stage name, and the count of tasks sitting in it.
private struct SectionHeader: View {
    let status: TaskStatus
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.stage(status))
                .frame(width: 8, height: 8)

            // At accessibility sizes "IN PROGRESS" is wider than the row; shrinking it beats
            // breaking the word across lines.
            Text(status.title.uppercased())
                .fontDesign(.rounded)
                .foregroundStyle(Theme.stage(status))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(count, format: .number)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}
