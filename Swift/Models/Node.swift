//
//  Node.swift
//  NodeHub
//
//  代理节点数据模型 — 支持 VLESS / VMess / Trojan / Shadowsocks / SOCKS5 / HTTP
//

import Foundation

// MARK: - 协议类型

enum ProxyProtocol: String, Codable, CaseIterable, Identifiable {
    case vless, vmess, trojan, shadowsocks, socks5, http
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .vless: return "VLESS"
        case .vmess: return "VMess"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        case .socks5: return "SOCKS5"
        case .http: return "HTTP"
        }
    }
    var colorHex: String {
        switch self {
        case .vless: return "#007AFF"
        case .vmess: return "#34C759"
        case .trojan: return "#FF9500"
        case .shadowsocks: return "#AF52DE"
        case .socks5: return "#8E8E93"
        case .http: return "#5856D6"
        }
    }
}

// MARK: - 传输协议

enum TransportType: String, Codable, CaseIterable {
    case raw, tcp, ws, grpc, h2, httpupgrade
    var displayName: String {
        switch self {
        case .raw: return "raw"
        case .tcp: return "tcp"
        case .ws: return "WebSocket"
        case .grpc: return "gRPC"
        case .h2: return "HTTP/2"
        case .httpupgrade: return "HTTPUpgrade"
        }
    }
}

struct TransportConfig: Codable, Equatable {
    var type: TransportType = .raw
    var host: String = ""
    var path: String = ""
    var serviceName: String = ""   // gRPC serviceName
    var mode: String = ""           // gRPC mode: gun / multi
    var maxEarlyData: Int = 0
    var earlyDataHeaderName: String = ""
}

// MARK: - 安全层

enum SecurityType: String, Codable, CaseIterable {
    case reality, tls, none
    var displayName: String {
        switch self {
        case .reality: return "Reality"
        case .tls: return "TLS"
        case .none: return "无"
        }
    }
}

struct SecurityConfig: Codable, Equatable {
    var type: SecurityType = .none
    // TLS 通用
    var sni: String = ""
    var fingerprint: String = "chrome"
    var alpn: [String] = []
    var allowInsecure: Bool = false
    // Reality 专用
    var publicKey: String = ""
    var shortId: String = ""
    var spiderX: String = ""
}

// MARK: - 节点模型

struct Node: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var remark: String = ""
    var `protocol`: ProxyProtocol = .vless
    var address: String = ""
    var port: Int = 443

    // 各协议专用字段
    var uuid: String = ""              // VLESS / VMess
    var flow: String = ""              // VLESS flow: xtls-rprx-vision
    var encryption: String = "none"    // VLESS encryption
    var alterId: Int = 0               // VMess alterId
    var cipher: String = "auto"        // VMess / Shadowsocks cipher
    var password: String = ""           // Trojan / SOCKS5 / HTTP / Shadowsocks 密码
    var method: String = ""             // Shadowsocks 加密方法

    var transport: TransportConfig = TransportConfig()
    var security: SecurityConfig = SecurityConfig()

    // 元数据
    var group: String = ""
    var tags: [String] = []
    var latency: Int? = nil
    var lastTestTime: Date? = nil
    var uploadTraffic: Int64 = 0
    var downloadTraffic: Int64 = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - 计算属性

    var displayAddress: String {
        "\(address):\(port)"
    }

    var latencyText: String {
        guard let latency = latency else { return "—" }
        return "\(latency)ms"
    }

    var latencyColorHex: String {
        guard let latency = latency else { return "#8E8E93" }
        if latency < 200 { return "#34C759" }
        if latency < 500 { return "#FF9500" }
        return "#FF3B30"
    }

    var trafficText: String {
        let up = ByteCountFormatter.string(fromByteCount: uploadTraffic, countStyle: .file)
        let down = ByteCountFormatter.string(fromByteCount: downloadTraffic, countStyle: .file)
        return "↑\(up) ↓\(down)"
    }

    /// 生成 vless:// 分享链接
    var shareLink: String {
        switch `protocol` {
        case .vless:
            var params: [String] = []
            params.append("encryption=\(encryption)")
            if !flow.isEmpty { params.append("flow=\(flow)") }
            params.append("security=\(security.type.rawValue)")
            if !security.sni.isEmpty { params.append("sni=\(security.sni)") }
            if !security.fingerprint.isEmpty { params.append("fp=\(security.fingerprint)") }
            if security.type == .reality {
                params.append("pbk=\(security.publicKey)")
                params.append("sid=\(security.shortId)")
            }
            params.append("type=\(transport.type.rawValue)")
            if !transport.host.isEmpty { params.append("host=\(transport.host)") }
            if !transport.path.isEmpty { params.append("path=\(transport.path)") }
            if !transport.serviceName.isEmpty { params.append("serviceName=\(transport.serviceName)") }
            let encodedRemark = remark.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? remark
            return "vless://\(uuid)@\(address):\(port)?\(params.joined(separator: "&"))#\(encodedRemark)"
        default:
            return "" // 其他协议链接生成略
        }
    }

    // MARK: - Equatable

    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 节点排序

enum NodeSortOption: String, CaseIterable {
    case latency = "延迟"
    case remark = "名称"
    case traffic = "流量"
    case recent = "最近使用"
}
