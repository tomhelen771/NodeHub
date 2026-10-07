//
//  LatencyTester.swift
//  NodeHub
//
//  节点延迟测试服务 — 通过本地 SOCKS5 代理访问测试 URL，测量响应时间
//

import Foundation
import Network

final class LatencyTester {

    static let shared = LatencyTester()

    private let testURL = URL(string: "http://www.gstatic.com/generate_204")!
    private let timeout: TimeInterval = 5.0

    private init() {}

    // MARK: - 单节点测试

    /// 测试单个节点延迟（毫秒），失败返回 nil
    func test(node: Node, via socksPort: UInt16 = 10808) async -> Int? {
        // 实际实现：通过本地 SOCKS5 代理发起 HTTP 请求
        // 此处为概念框架，真实实现需使用 NWConnection 或 URLSession 配合代理
        let startTime = Date()
        do {
            var request = URLRequest(url: testURL)
            request.timeoutInterval = timeout
            // 注：URLSession 原生不支持 SOCKS5 代理，需自定义协议或使用 NWConnection
            // 真实实现见 PacketTunnel 内的代理栈
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                let elapsed = Date().timeIntervalSince(startTime) * 1000
                return Int(elapsed.rounded())
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - 批量测试

    /// 批量测试节点延迟，返回 [节点ID: 延迟毫秒]
    func testBatch(nodes: [Node],
                   concurrency: Int = 10,
                   progress: @escaping (Int, Int) -> Void) async -> [UUID: Int] {
        var results: [UUID: Int] = [:]
        let total = nodes.count
        var completed = 0

        // 使用信号量控制并发
        let semaphore = DispatchSemaphore(value: concurrency)
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for node in nodes {
                group.addTask {
                    semaphore.wait()
                    defer { semaphore.signal() }
                    let latency = await self.test(node: node)
                    return (node.id, latency)
                }
            }
            for await (id, latency) in group {
                if let latency = latency {
                    results[id] = latency
                }
                completed += 1
                progress(completed, total)
            }
        }
        return results
    }

    // MARK: - TCP 握手延迟（不经过代理，直连服务器）

    /// 直接 TCP 握手测试服务器端口延迟（用于检测服务器是否在线）
    func tcpPing(host: String, port: UInt16, timeout: TimeInterval = 5.0) async -> Int? {
        let startTime = Date()
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: NWEndpoint.Port(rawValue: port)!,
                                      using: .tcp)
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(startTime) * 1000
                    connection.cancel()
                    continuation.resume(returning: Int(elapsed.rounded()))
                case .failed:
                    connection.cancel()
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            // 超时处理
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if connection.state != .cancelled {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - 延迟分类

extension Int {
    var latencyLevel: LatencyLevel {
        if self < 100 { return .excellent }
        if self < 200 { return .good }
        if self < 500 { return .fair }
        return .poor
    }
}

enum LatencyLevel {
    case excellent  // < 100ms
    case good       // 100-200ms
    case fair       // 200-500ms
    case poor       // > 500ms

    var colorHex: String {
        switch self {
        case .excellent: return "#30D158"
        case .good: return "#34C759"
        case .fair: return "#FF9F0A"
        case .poor: return "#FF453A"
        }
    }

    var text: String {
        switch self {
        case .excellent: return "极快"
        case .good: return "快"
        case .fair: return "一般"
        case .poor: return "慢"
        }
    }
}
