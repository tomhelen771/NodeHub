//
//  LinkParser.swift
//  NodeHub
//
//  节点分享链接解析器 — 支持 vless:// vmess:// trojan:// ss:// ssr://
//

import Foundation

enum LinkParseError: Error, LocalizedError {
    case invalidFormat
    case unsupportedProtocol(String)
    case missingHost
    case missingUUID
    case invalidBase64
    case vmessJSONError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "链接格式无效"
        case .unsupportedProtocol(let p): return "不支持的协议: \(p)"
        case .missingHost: return "缺少服务器地址"
        case .missingUUID: return "缺少 UUID"
        case .invalidBase64: return "Base64 解码失败"
        case .vmessJSONError(let msg): return "VMess JSON 解析失败: \(msg)"
        }
    }
}

struct LinkParser {

    // MARK: - 入口：自动识别协议并解析

    static func parse(_ link: String) throws -> Node {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = URL(string: trimmed)?.scheme?.lowercased() else {
            throw LinkParseError.invalidFormat
        }
        switch scheme {
        case "vless":
            return try parseVLESS(trimmed)
        case "vmess":
            return try parseVMess(trimmed)
        case "trojan":
            return try parseTrojan(trimmed)
        case "ss":
            return try parseShadowsocks(trimmed)
        default:
            throw LinkParseError.unsupportedProtocol(scheme)
        }
    }

    // MARK: - VLESS

    static func parseVLESS(_ link: String) throws -> Node {
        // vless://uuid@host:port?params#remark
        guard let url = URLComponents(string: link) else {
            throw LinkParseError.invalidFormat
        }
        guard let host = url.host, !host.isEmpty else {
            throw LinkParseError.missingHost
        }
        let uuid = url.user ?? ""
        guard !uuid.isEmpty else {
            throw LinkParseError.missingUUID
        }

        var node = Node()
        node.protocol = .vless
        node.uuid = uuid
        node.address = host
        node.port = url.port ?? 443
        node.remark = url.fragment?.removingPercentEncoding ?? ""

        let params = url.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0.value ?? "") })

        node.encryption = dict["encryption"] ?? "none"
        node.flow = dict["flow"] ?? ""

        // 安全层
        let secType = dict["security"] ?? "none"
        node.security.type = SecurityType(rawValue: secType) ?? .none
        node.security.sni = dict["sni"] ?? ""
        node.security.fingerprint = dict["fp"] ?? "chrome"
        if node.security.type == .reality {
            node.security.publicKey = dict["pbk"] ?? ""
            node.security.shortId = dict["sid"] ?? ""
            node.security.spiderX = dict["spx"] ?? ""
        }
        if let alpn = dict["alpn"] {
            node.security.alpn = alpn.components(separatedBy: ",")
        }

        // 传输层
        let transType = dict["type"] ?? "raw"
        node.transport.type = TransportType(rawValue: transType) ?? .raw
        node.transport.host = dict["host"] ?? ""
        node.transport.path = dict["path"] ?? ""
        node.transport.serviceName = dict["serviceName"] ?? ""
        node.transport.mode = dict["mode"] ?? ""

        return node
    }

    // MARK: - VMess (base64 JSON)

    static func parseVMess(_ link: String) throws -> Node {
        // vmess://base64(json)
        guard let range = link.range(of: "vmess://") else {
            throw LinkParseError.invalidFormat
        }
        let b64 = String(link[range.upperBound...])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: b64) else {
            throw LinkParseError.invalidBase64
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinkParseError.vmessJSONError("无法解析为 JSON 对象")
        }

        var node = Node()
        node.protocol = .vmess
        node.uuid = json["id"] as? String ?? ""
        node.address = json["add"] as? String ?? ""
        node.port = Int(json["port"] as? String ?? "") ?? (json["port"] as? Int) ?? 443
        node.remark = json["ps"] as? String ?? ""
        node.alterId = Int(json["aid"] as? String ?? "") ?? (json["aid"] as? Int) ?? 0
        node.cipher = json["scy"] as? String ?? "auto"

        // 传输
        let net = json["net"] as? String ?? "tcp"
        node.transport.type = TransportType(rawValue: net) ?? .tcp
        node.transport.host = json["host"] as? String ?? ""
        node.transport.path = json["path"] as? String ?? ""

        // 安全
        let tls = json["tls"] as? String ?? ""
        node.security.type = tls == "tls" ? .tls : .none
        node.security.sni = json["sni"] as? String ?? ""
        node.security.fingerprint = json["fp"] as? String ?? "chrome"
        if let alpn = json["alpn"] as? String {
            node.security.alpn = alpn.components(separatedBy: ",")
        }

        return node
    }

    // MARK: - Trojan

    static func parseTrojan(_ link: String) throws -> Node {
        // trojan://password@host:port?params#remark
        guard let url = URLComponents(string: link) else {
            throw LinkParseError.invalidFormat
        }
        guard let host = url.host, !host.isEmpty else {
            throw LinkParseError.missingHost
        }

        var node = Node()
        node.protocol = .trojan
        node.password = url.user?.removingPercentEncoding ?? ""
        node.address = host
        node.port = url.port ?? 443
        node.remark = url.fragment?.removingPercentEncoding ?? ""

        let params = url.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0.value ?? "") })

        node.security.type = .tls
        node.security.sni = dict["sni"] ?? ""
        node.security.fingerprint = dict["fp"] ?? "chrome"
        if let alpn = dict["alpn"] {
            node.security.alpn = alpn.components(separatedBy: ",")
        }
        node.security.allowInsecure = dict["allowInsecure"] == "1"

        let transType = dict["type"] ?? "raw"
        node.transport.type = TransportType(rawValue: transType) ?? .raw
        node.transport.serviceName = dict["serviceName"] ?? ""
        node.transport.mode = dict["mode"] ?? ""

        return node
    }

    // MARK: - Shadowsocks

    static func parseShadowsocks(_ link: String) throws -> Node {
        // ss://method:password@host:port#remark  或  ss://base64(method:password)@host:port#remark
        guard let url = URLComponents(string: link) else {
            throw LinkParseError.invalidFormat
        }
        guard let host = url.host, !host.isEmpty else {
            throw LinkParseError.missingHost
        }

        var node = Node()
        node.protocol = .shadowsocks
        node.address = host
        node.port = url.port ?? 8388
        node.remark = url.fragment?.removingPercentEncoding ?? ""

        if let userInfo = url.user {
            // 可能是 base64 编码的 method:password
            if let decoded = Data(base64Encoded: userInfo.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userInfo),
               let str = String(data: decoded, encoding: .utf8),
               let range = str.range(of: ":") {
                node.method = String(str[..<range.lowerBound])
                node.password = String(str[range.upperBound...])
            } else if let range = userInfo.range(of: ":") {
                node.method = String(userInfo[..<range.lowerBound])
                node.password = String(userInfo[range.upperBound...]).removingPercentEncoding ?? ""
            }
        }

        return node
    }

    // MARK: - 批量解析（订阅）

    static func parseBatch(_ base64Content: String) throws -> [Node] {
        let padded = base64Content
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .padding(toLength: ((base64Content.count + 3) / 4) * 4,
                       withPad: "=", startingAt: 0)
        guard let data = Data(base64Encoded: padded) else {
            throw LinkParseError.invalidBase64
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw LinkParseError.invalidBase64
        }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var nodes: [Node] = []
        for line in lines {
            if let node = try? parse(line) {
                nodes.append(node)
            }
        }
        return nodes
    }
}
