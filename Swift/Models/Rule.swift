//
//  Rule.swift
//  NodeHub
//
//  路由规则数据模型
//

import Foundation

// MARK: - 规则类型

enum RuleType: String, Codable, CaseIterable, Identifiable {
    case domain = "DOMAIN"
    case domainSuffix = "DOMAIN-SUFFIX"
    case domainKeyword = "DOMAIN-KEYWORD"
    case domainRegex = "DOMAIN-REGEX"
    case ipCidr = "IP-CIDR"
    case ipCidr6 = "IP-CIDR6"
    case geoip = "GEOIP"
    case port = "PORT"
    case processName = "PROCESS-NAME"
    case processPath = "PROCESS-PATH"
    case network = "NETWORK"
    case sourceIpCidr = "SOURCE-IP-CIDR"
    case sourcePort = "SOURCE-PORT"
    case inboundTag = "INBOUND-TAG"
    case protocol_ = "PROTOCOL"
    case attrs = "ATTRS"
    case match = "MATCH"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .domain, .domainSuffix, .domainKeyword, .domainRegex:
            return "globe"
        case .ipCidr, .ipCidr6, .geoip, .sourceIpCidr:
            return "network"
        case .port, .sourcePort:
            return "cable.connector"
        case .processName, .processPath:
            return "app"
        case .match:
            return "asterisk.circle"
        default:
            return "line.3.horizontal.decrease.circle"
        }
    }
}

// MARK: - 规则动作

enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case proxy = "proxy"
    case direct = "direct"
    case block = "block"
    case dns = "dns"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proxy: return "代理"
        case .direct: return "直连"
        case .block: return "拦截"
        case .dns: return "DNS"
        }
    }

    var colorHex: String {
        switch self {
        case .proxy: return "#34C759"
        case .direct: return "#007AFF"
        case .block: return "#FF3B30"
        case .dns: return "#AF52DE"
        }
    }
}

// MARK: - 规则模型

struct Rule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: RuleType = .domainSuffix
    var value: String = ""
    var action: RuleAction = .proxy
    var outboundTag: String = "proxy"
    var enabled: Bool = true
    var noResolve: Bool = false       // IP-CIDR 专用：不做 DNS 解析
    var remark: String = ""

    // MARK: - 计算属性

    var displayText: String {
        if type == .match {
            return "MATCH（兜底）"
        }
        return "\(type.rawValue),\(value)"
    }

    var isEditable: Bool {
        type != .match
    }

    // MARK: - 从 sing-box 格式解析

    static func parse(fromSingBox dict: [String: Any]) -> Rule? {
        guard let typeStr = dict["type"] as? String,
              let type = RuleType(rawValue: typeStr) else { return nil }
        let value = dict["value"] as? String ?? ""
        let actionStr = dict["action"] as? String ?? "proxy"
        let action = RuleAction(rawValue: actionStr) ?? .proxy
        return Rule(type: type, value: value, action: action,
                    outboundTag: dict["outboundTag"] as? String ?? "proxy",
                    enabled: dict["enabled"] as? Bool ?? true,
                    noResolve: dict["noResolve"] as? Bool ?? false,
                    remark: dict["remark"] as? String ?? "")
    }

    func toSingBox() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type.rawValue,
            "action": action.rawValue,
            "outboundTag": outboundTag,
            "enabled": enabled
        ]
        if type != .match {
            dict["value"] = value
        }
        if noResolve {
            dict["noResolve"] = true
        }
        if !remark.isEmpty {
            dict["remark"] = remark
        }
        return dict
    }
}

// MARK: - 规则集

struct RuleSet: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var description: String = ""
    var isActive: Bool = true
    var rules: [Rule] = []

    var proxyCount: Int { rules.filter { $0.action == .proxy && $0.enabled }.count }
    var directCount: Int { rules.filter { $0.action == .direct && $0.enabled }.count }
    var blockCount: Int { rules.filter { $0.action == .block && $0.enabled }.count }
    var enabledCount: Int { rules.filter { $0.enabled }.count }

    var summaryText: String {
        "共 \(rules.count) 条 · 代理 \(proxyCount) · 直连 \(directCount) · 拦截 \(blockCount)"
    }
}
