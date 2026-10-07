//
//  NodeListViewModel.swift
//  NodeHub
//
//  节点列表 ViewModel — 管理节点数据、连接状态、延迟测试
//

import Foundation
import Combine
import NetworkExtension

@MainActor
final class NodeListViewModel: ObservableObject {

    // MARK: - 发布属性

    @Published var nodes: [Node] = []
    @Published var selectedNodeID: UUID? = nil
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var isTestingLatency: Bool = false
    @Published var searchText: String = ""
    @Published var sortOption: NodeSortOption = .latency
    @Published var selectedGroup: String? = nil
    @Published var uploadTraffic: Int64 = 0
    @Published var downloadTraffic: Int64 = 0
    @Published var connectionError: String? = nil

    // MARK: - 私有属性

    private let configStore = ConfigStore.shared
    private let latencyTester = LatencyTester.shared
    private var vpnManager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 计算属性

    var groups: [String] {
        let all = Set(nodes.map { $0.group }.filter { !$0.isEmpty })
        return Array(all).sorted()
    }

    var filteredNodes: [Node] {
        var result = nodes
        // 分组过滤
        if let group = selectedGroup {
            result = result.filter { $0.group == group }
        }
        // 搜索过滤
        if !searchText.isEmpty {
            let keyword = searchText.lowercased()
            result = result.filter {
                $0.remark.lowercased().contains(keyword) ||
                $0.address.lowercased().contains(keyword) ||
                $0.protocol.displayName.lowercased().contains(keyword)
            }
        }
        // 排序
        switch sortOption {
        case .latency:
            result.sort { ($0.latency ?? Int.max) < ($1.latency ?? Int.max) }
        case .remark:
            result.sort { $0.remark.localizedCaseInsensitiveCompare($1.remark) == .orderedAscending }
        case .traffic:
            result.sort { ($0.uploadTraffic + $0.downloadTraffic) > ($1.uploadTraffic + $1.downloadTraffic) }
        case .recent:
            result.sort { ($0.lastTestTime ?? .distantPast) > ($1.lastTestTime ?? .distantPast) }
        }
        return result
    }

    var selectedNode: Node? {
        guard let id = selectedNodeID else { return nil }
        return nodes.first { $0.id == id }
    }

    var statusText: String {
        if isConnecting { return "连接中…" }
        if isConnected { return "已连接" }
        return "未连接"
    }

    var trafficText: String {
        let up = ByteCountFormatter.string(fromByteCount: uploadTraffic, countStyle: .file)
        let down = ByteCountFormatter.string(fromByteCount: downloadTraffic, countStyle: .file)
        return "↑\(up) ↓\(down)"
    }

    // MARK: - 初始化

    init() {
        loadNodes()
        loadSettings()
        setupVPNObserver()
    }

    // MARK: - 数据加载

    func loadNodes() {
        nodes = configStore.loadNodes()
        if selectedNodeID == nil {
            selectedNodeID = configStore.loadSettings().selectedNodeID ?? nodes.first?.id
        }
    }

    func loadSettings() {
        let settings = configStore.loadSettings()
        selectedNodeID = settings.selectedNodeID
    }

    func saveNodes() {
        configStore.saveNodes(nodes)
    }

    // MARK: - 节点操作

    func addNode(_ node: Node) {
        nodes.append(node)
        saveNodes()
    }

    func updateNode(_ node: Node) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
            saveNodes()
        }
    }

    func deleteNode(_ node: Node) {
        nodes.removeAll { $0.id == node.id }
        if selectedNodeID == node.id {
            selectedNodeID = nodes.first?.id
        }
        saveNodes()
    }

    func selectNode(_ node: Node) {
        selectedNodeID = node.id
        var settings = configStore.loadSettings()
        settings.selectedNodeID = node.id
        configStore.saveSettings(settings)
    }

    /// 从剪贴板导入节点链接
    func importFromPasteboard() -> Result<Node, Error> {
        guard let link = UIPasteboard.general.string else {
            return .failure(LinkParseError.invalidFormat)
        }
        do {
            let node = try LinkParser.parse(link)
            addNode(node)
            return .success(node)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 延迟测试

    func testSingleLatency(node: Node) async {
        if let latency = await latencyTester.test(node: node) {
            if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                nodes[index].latency = latency
                nodes[index].lastTestTime = Date()
                saveNodes()
            }
        }
    }

    func testAllLatency() async {
        isTestingLatency = true
        defer { isTestingLatency = false }
        let results = await latencyTester.testBatch(nodes: nodes) { completed, total in
            Task { @MainActor in
                // 可更新进度 UI
            }
        }
        for (id, latency) in results {
            if let index = nodes.firstIndex(where: { $0.id == id }) {
                nodes[index].latency = latency
                nodes[index].lastTestTime = Date()
            }
        }
        saveNodes()
    }

    // MARK: - VPN 连接控制

    private func setupVPNObserver() {
        NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateConnectionStatus()
                }
            }
            .store(in: &cancellables)
    }

    private func updateConnectionStatus() {
        guard let manager = vpnManager else { return }
        let status = manager.connection.status
        isConnected = status == .connected
        isConnecting = status == .connecting || status == .reasserting
        if status == .disconnected {
            connectionError = nil
        }
    }

    func connect() async {
        guard let node = selectedNode else {
            connectionError = "请先选择一个节点"
            return
        }
        isConnecting = true
        connectionError = nil
        do {
            // 加载或创建 VPN 配置
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            vpnManager = managers.first ?? NETunnelProviderManager()
            guard let manager = vpnManager else { return }

            // 配置 VPN
            manager.localizedDescription = "NodeHub VPN"
            manager.isEnabled = true
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.liguangming.NodeHub.tunnel"
            proto.serverAddress = "\(node.address):\(node.port)"
            // 将节点配置传递给 PacketTunnel 扩展
            if let nodeData = try? JSONEncoder().encode(node) {
                proto.providerConfiguration = ["node": nodeData]
            }
            manager.protocolConfiguration = proto
            manager.isOnDemandEnabled = false

            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            // 启动 VPN
            try manager.connection.startVPNTunnel()
            isConnecting = false
            isConnected = true
        } catch {
            isConnecting = false
            connectionError = error.localizedDescription
        }
    }

    func disconnect() {
        vpnManager?.connection.stopVPNTunnel()
        isConnected = false
    }

    func toggleConnection() async {
        if isConnected {
            disconnect()
        } else {
            await connect()
        }
    }
}
