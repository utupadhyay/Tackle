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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                .overlay(alignment: .bottomTrailing) { newTaskButton }
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
            "Move",
            isPresented: Binding(
                get: { viewModel.taskBeingMoved != nil },
                set: { if !$0 { viewModel.taskBeingMoved = nil } }
            ),
            presenting: viewModel.taskBeingMoved
        ) { task in
            ForEach(viewModel.destinations(for: task), id: \.self) { status in
                Button(status.title) { viewModel.move(task, to: status) }
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
        } else {
            List {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    section(for: status)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
        }
    }

    private func section(for status: TaskStatus) -> some View {
        let tasks = viewModel.tasks(in: status)

        return Section {
            ForEach(tasks) { task in
                TaskRow(task: task)
                    .listRowBackground(Theme.card)
                    .onTapGesture { viewModel.edit(task) }
                    .swipeActions(edge: .trailing) {
                        Button("Delete") { viewModel.pendingDeletion = task }
                            .tint(Theme.destructive)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Move") { viewModel.taskBeingMoved = task }
                            .tint(Theme.tint)
                    }
                    .contextMenu {
                        Button("Move") { viewModel.taskBeingMoved = task }
                        Button("Delete", role: .destructive) { viewModel.pendingDeletion = task }
                    }
            }
            .onMove { viewModel.move(in: tasks, from: $0, to: $1) }
        } header: {
            StatusPill(status: status, count: tasks.count)
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
