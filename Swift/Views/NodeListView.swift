//
//  NodeListView.swift
//  NodeHub
//
//  首页 — 节点列表 + 连接控制
//

import SwiftUI

struct NodeListView: View {

    @StateObject private var viewModel = NodeListViewModel()
    @State private var showAddNode = false
    @State private var showImportAlert = false
    @State private var importMessage = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 节点列表
                List {
                    // 搜索栏
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("搜索节点名称、地址、协议", text: $viewModel.searchText)
                                .textInputAutocapitalization(.never)
                            if !viewModel.searchText.isEmpty {
                                Button(action: { viewModel.searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }

                    // 分组选择
                    if !viewModel.groups.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    FilterChip(title: "全部", isSelected: viewModel.selectedGroup == nil) {
                                        viewModel.selectedGroup = nil
                                    }
                                    ForEach(viewModel.groups, id: \.self) { group in
                                        FilterChip(title: group, isSelected: viewModel.selectedGroup == group) {
                                            viewModel.selectedGroup = group
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }

                    // 节点列表
                    Section {
                        if viewModel.filteredNodes.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("暂无节点")
                                    .foregroundColor(.gray)
                                Button("添加节点") {
                                    showAddNode = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(viewModel.filteredNodes) { node in
                                NodeRow(node: node, isSelected: viewModel.selectedNodeID == node.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectNode(node)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            viewModel.deleteNode(node)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        HStack {
                            Text("共 \(viewModel.filteredNodes.count) 个节点")
                            Spacer()
                            Menu {
                                ForEach(NodeSortOption.allCases, id: \.self) { option in
                                    Button(option.rawValue) {
                                        viewModel.sortOption = option
                                    }
                                }
                            } label: {
                                Label("排序", systemImage: "arrow.up.arrow.down")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // 底部连接控制栏
                bottomBar
            }
            .navigationTitle("NodeHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: { showAddNode = true }) {
                            Label("手动添加", systemImage: "plus.circle")
                        }
                        Button(action: { importFromPasteboard() }) {
                            Label("从剪贴板导入", systemImage: "clipboard")
                        }
                        Button(action: {
                            Task { await viewModel.testAllLatency() }
                        }) {
                            Label("全部测速", systemImage: "stopwatch")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SubscriptionView()) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                }
            }
            .sheet(isPresented: $showAddNode) {
                AddNodeView(viewModel: viewModel)
            }
            .alert("导入结果", isPresented: $showImportAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(importMessage)
            }
        }
    }

    // MARK: - 底部连接栏

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                // 连接状态指示
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(viewModel.statusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    if let node = viewModel.selectedNode {
                        Text(node.remark)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // 流量统计
                if viewModel.isConnected {
                    Text(viewModel.trafficText)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }
                // 连接开关
                Button(action: {
                    Task { await viewModel.toggleConnection() }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: viewModel.isConnected ? "power" : "power")
                        }
                        Text(viewModel.isConnected ? "断开" : "连接")
                            .fontWeight(.semibold)
                    }
                    .frame(width: 100, height: 44)
                    .background(viewModel.isConnected ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
                .disabled(viewModel.isConnecting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - 导入

    private func importFromPasteboard() {
        let result = viewModel.importFromPasteboard()
        switch result {
        case .success(let node):
            importMessage = "成功导入节点：\(node.remark)"
        case .failure(let error):
            importMessage = "导入失败：\(error.localizedDescription)"
        }
        showImportAlert = true
    }
}

// MARK: - 节点行

struct NodeRow: View {
    let node: Node
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 协议标签
            Text(node.protocol.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: node.protocol.colorHex))
                .cornerRadius(6)

            // 节点信息
            VStack(alignment: .leading, spacing: 3) {
                Text(node.remark)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(node.displayAddress)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .monospacedDigit()
            }

            Spacer()

            // 延迟
            Text(node.latencyText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color(hex: node.latencyColorHex))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)

            // 选中标记
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
    }
}

// MARK: - 过滤标签

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(14)
        }
    }
}

// MARK: - Color 扩展

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
