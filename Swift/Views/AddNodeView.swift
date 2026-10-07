//
//  AddNodeView.swift
//  NodeHub
//
//  添加/编辑节点页面
//

import SwiftUI

struct AddNodeView: View {

    @ObservedObject var viewModel: NodeListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var linkText = ""
    @State private var remark = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("节点链接") {
                    TextEditor(text: $linkText)
                        .frame(minHeight: 80)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("备注（可选）") {
                    TextField("节点名称", text: $remark)
                }

                Section {
                    Button {
                        importFromClipboard()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("从剪贴板粘贴")
                        }
                    }
                }
            }
            .navigationTitle("添加节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveNode()
                    }
                    .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("导入失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func importFromClipboard() {
        let result = viewModel.importFromPasteboard()
        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func saveNode() {
        let link = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var node = try LinkParser.parse(link)
            if !remark.isEmpty {
                node.remark = remark
            }
            viewModel.addNode(node)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
