//
//  TaskEditorView.swift
//  Tackle
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import SwiftUI

struct TaskEditorView: View {
    @State private var viewModel: TaskEditorViewModel

    init(viewModel: TaskEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section("TITLE") {
                    TextField("What needs doing?", text: $viewModel.title)
                }
                Section("DESCRIPTION") {
                    TextField("Add detail (optional)", text: $viewModel.details, axis: .vertical)
                        .lineLimit(3...)
                }
                Section("STATUS") {
                    StatusSelector(selection: $viewModel.status)
                }
            }
            .navigationTitle(viewModel.isNew ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { viewModel.save() }
                        .disabled(!viewModel.canSave)
                }
            }
            .alert("Unable to save changes", isPresented: $viewModel.saveFailed) {}
        }
    }
}

/// A segmented control whose selected segment takes its stage colour, so choosing a status
/// previews where the task will land.
private struct StatusSelector: View {
    @Binding var selection: TaskStatus

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                let isSelected = status == selection

                Button {
                    selection = status
                } label: {
                    Text(status.title)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(isSelected ? Color.white : Theme.label)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Theme.stage(status) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}
