//
//  Subscription.swift
//  NodeHub
//
//  订阅源数据模型
//

import Foundation

// MARK: - 订阅类型

enum SubscriptionType: String, Codable, CaseIterable {
    case base64 = "base64"           // base64 编码的节点链接列表（最常见）
    case singBox = "sing-box"        // sing-box 配置格式
    case v2ray = "v2ray"             // v2rayN 配置格式
    case clash = "clash"             // Clash 配置格式

    var displayName: String {
        switch self {
        case .base64: return "Base64 链接列表"
        case .singBox: return "sing-box 配置"
        case .v2ray: return "v2ray 配置"
        case .clash: return "Clash 配置"
        }
    }
}

enum UpdateStatus: String, Codable {
    case idle = "idle"
    case updating = "updating"
    case success = "success"
    case failed = "failed"
}

// MARK: - 过滤器

struct SubscriptionFilter: Codable, Equatable {
    var includeKeywords: [String] = []
    var excludeKeywords: [String] = []
    var includeProtocols: [String] = []   // 空 = 全部
    var excludeProtocols: [String] = []
}

// MARK: - 订阅源模型

struct Subscription: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var url: String = ""
    var type: SubscriptionType = .base64
    var enabled: Bool = true
    var autoUpdate: Bool = true
    var updateIntervalMinutes: Int = 1440
    var lastUpdated: Date? = nil
    var lastUpdateStatus: UpdateStatus = .idle
    var lastUpdateError: String? = nil
    var nodeCount: Int = 0
    var groupPrefix: String = ""
    var filter: SubscriptionFilter = SubscriptionFilter()
    var userAgent: String = "NodeHub/1.0"
    var headers: [String: String] = [:]
    var createdAt: Date = Date()

    // MARK: - 计算属性

    var displayURL: String {
        guard let components = URLComponents(string: url) else { return url }
        let host = components.host ?? ""
        let path = components.path
        return "\(host)\(path.prefix(30))..."
    }

    var lastUpdateText: String {
        guard let date = lastUpdated else { return "从未更新" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var statusColorHex: String {
        switch lastUpdateStatus {
        case .success: return "#34C759"
        case .failed: return "#FF3B30"
        case .updating: return "#FF9500"
        case .idle: return "#8E8E93"
        }
    }

    var nextUpdateTime: Date? {
        guard autoUpdate, let last = lastUpdated else { return nil }
        return last.addingTimeInterval(TimeInterval(updateIntervalMinutes * 60))
    }

    // MARK: - 节点过滤

    func shouldInclude(nodeRemark: String, nodeProtocol: String) -> Bool {
        let remark = nodeRemark.lowercased()
        // 包含关键词（空 = 不限制）
        if !filter.includeKeywords.isEmpty {
            let matched = filter.includeKeywords.contains { remark.contains($0.lowercased()) }
            if !matched { return false }
        }
        // 排除关键词
        if filter.excludeKeywords.contains(where: { remark.contains($0.lowercased()) }) {
            return false
        }
        // 协议包含
        if !filter.includeProtocols.isEmpty {
            if !filter.includeProtocols.contains(nodeProtocol.lowercased()) {
                return false
            }
        }
        // 协议排除
        if filter.excludeProtocols.contains(nodeProtocol.lowercased()) {
            return false
        }
        return true
    }
}

// MARK: - 订阅全局设置

struct SubscriptionGlobalSettings: Codable, Equatable {
    var defaultUpdateIntervalMinutes: Int = 1440
    var concurrentUpdateLimit: Int = 3
    var updateTimeoutSeconds: Int = 30
    var deduplicateNodes: Bool = true
    var dedupeBy: [String] = ["address", "port", "uuid"]
    var autoSortByLatencyAfterUpdate: Bool = true
}
