//
//  ConfigStore.swift
//  NodeHub
//
//  本地配置持久化 — 使用 App Group 共享目录，主 App 与 PacketTunnel 扩展均可访问
//

import Foundation

final class ConfigStore {

    static let shared = ConfigStore()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // App Group 标识（需在 Xcode 中配置）
    private let appGroupID = "group.com.liguangming.NodeHub"

    private var storeDirectory: URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url.appendingPathComponent("Config", isDirectory: true)
        }
        // 降级：使用 App 沙盒 Documents
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Config", isDirectory: true)
    }

    enum ConfigFile: String {
        case nodes = "nodes.json"
        case subscriptions = "subscriptions.json"
        case rules = "rules.json"
        case settings = "settings.json"
    }

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectory()
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: storeDirectory.path) {
            try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }
    }

    private func fileURL(_ file: ConfigFile) -> URL {
        storeDirectory.appendingPathComponent(file.rawValue)
    }

    // MARK: - 泛型读写

    func load<T: Decodable>(_ file: ConfigFile) throws -> T {
        let url = fileURL(file)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ConfigStoreError.fileNotFound(file.rawValue)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to file: ConfigFile) throws {
        let data = try encoder.encode(value)
        try data.write(to: fileURL(file), options: .atomic)
    }

    // MARK: - 便捷方法

    func loadNodes() -> [Node] {
        (try? load(.nodes)) ?? []
    }

    func saveNodes(_ nodes: [Node]) {
        try? save(nodes, to: .nodes)
    }

    func loadSubscriptions() -> [Subscription] {
        (try? load(.subscriptions)) ?? []
    }

    func saveSubscriptions(_ subs: [Subscription]) {
        try? save(subs, to: .subscriptions)
    }

    func loadRuleSets() -> [RuleSet] {
        (try? load(.rules)) ?? []
    }

    func saveRuleSets(_ sets: [RuleSet]) {
        try? save(sets, to: .rules)
    }

    func loadSettings() -> AppSettings {
        (try? load(.settings)) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        try? save(settings, to: .settings)
    }

    // MARK: - 导出/导入

    func exportAll() -> Data? {
        let bundle = ExportBundle(
            nodes: loadNodes(),
            subscriptions: loadSubscriptions(),
            ruleSets: loadRuleSets(),
            settings: loadSettings(),
            exportedAt: Date()
        )
        return try? encoder.encode(bundle)
    }

    func importAll(from data: Data) -> Bool {
        guard let bundle = try? decoder.decode(ExportBundle.self, from: data) else {
            return false
        }
        saveNodes(bundle.nodes)
        saveSubscriptions(bundle.subscriptions)
        saveRuleSets(bundle.ruleSets)
        saveSettings(bundle.settings)
        return true
    }
}

// MARK: - 错误类型

enum ConfigStoreError: Error, LocalizedError {
    case fileNotFound(String)
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name): return "配置文件不存在: \(name)"
        }
    }
}

// MARK: - 全局设置

struct AppSettings: Codable, Equatable {
    // 通用
    var language: String = "zh_CN"
    var theme: Theme = .system
    var autoConnectOnLaunch: Bool = false
    var showTrafficInStatusBar: Bool = true

    // 网络
    var localSocksPort: Int = 10808
    var localHttpPort: Int = 10809
    var dnsServers: [String] = ["1.1.1.1", "8.8.8.8"]
    var enableIPv6: Bool = false
    var allowLAN: Bool = false

    // 连接
    var selectedNodeID: UUID? = nil
    var vpnProfileName: String = "NodeHub VPN"
    var alwaysOnVPN: Bool = false

    // 延迟测试
    var latencyTestURL: String = "http://www.gstatic.com/generate_204"
    var latencyTestTimeout: Int = 5
    var concurrentTestLimit: Int = 10
}

enum Theme: String, Codable, CaseIterable {
    case light, dark, system
    var displayName: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }
}

// MARK: - 导出包

struct ExportBundle: Codable {
    var nodes: [Node]
    var subscriptions: [Subscription]
    var ruleSets: [RuleSet]
    var settings: AppSettings
    var exportedAt: Date
    var appVersion: String = "1.0.0"
}
