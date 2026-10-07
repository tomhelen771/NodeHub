//
//  PacketTunnelProvider.swift
//  NodeHub Tunnel Extension
//
//  PacketTunnel 扩展 — VPN 隧道核心，负责实际的代理转发
//  这是概念框架，真实实现需集成 sing-box 或 v2ray-core 的 iOS 编译版本
//

import NetworkExtension
import os.log

final class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - 属性

    private let logger = Logger(subsystem: "com.liguangming.NodeHub.tunnel", category: "PacketTunnel")
    private var proxyEngine: ProxyEngine?
    private var currentNode: Node?
    private var trafficMonitor: TrafficMonitor?
    private var isRunning = false

    // MARK: - 隧道生命周期

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("开始启动隧道")

        // 1. 从 providerConfiguration 读取节点配置
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = proto.providerConfiguration,
              let nodeData = providerConfig["node"] as? Data,
              let node = try? JSONDecoder().decode(Node.self, from: nodeData) else {
            logger.error("无法读取节点配置")
            completionHandler(PacketTunnelError.invalidConfiguration)
            return
        }
        currentNode = node
        logger.info("节点: \(node.remark, privacy: .public) \(node.address, privacy: .public):\(node.port)")

        // 2. 配置虚拟网络接口（TUN）
        let settings = createTunnelSettings(for: node)
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                self?.logger.error("设置隧道网络失败: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self?.logger.info("隧道网络设置完成")

            // 3. 启动代理引擎
            self?.startProxyEngine(node: node) { result in
                switch result {
                case .success:
                    self?.isRunning = true
                    self?.logger.info("隧道启动成功")
                    // 4. 启动流量监控
                    self?.startTrafficMonitoring()
                    // 5. 开始读取 IP 数据包
                    self?.startReadingPackets()
                    completionHandler(nil)
                case .failure(let error):
                    self?.logger.error("代理引擎启动失败: \(error.localizedDescription)")
                    completionHandler(error)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("停止隧道，原因: \(reason.rawValue)")
        isRunning = false
        proxyEngine?.stop()
        trafficMonitor?.stop()
        proxyEngine = nil
        trafficMonitor = nil
        completionHandler()
    }

    // MARK: - 处理来自 App 的消息

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        // App 与扩展通信：查询状态、切换节点、获取流量统计等
        do {
            let request = try JSONDecoder().decode(TunnelRequest.self, from: messageData)
            switch request.type {
            case .getStatus:
                let status = TunnelStatus(
                    isRunning: isRunning,
                    nodeRemark: currentNode?.remark ?? "",
                    uploadBytes: trafficMonitor?.totalUpload ?? 0,
                    downloadBytes: trafficMonitor?.totalDownload ?? 0
                )
                completionHandler?(try? JSONEncoder().encode(status))
            case .switchNode:
                if let nodeData = request.nodeData,
                   let node = try? JSONDecoder().decode(Node.self, from: nodeData) {
                    switchNode(node)
                    completionHandler?(try? JSONEncoder().encode(["result": "ok"]))
                }
            case .getLog:
                completionHandler?(Data("日志功能开发中".utf8))
            }
        } catch {
            logger.error("处理 App 消息失败: \(error.localizedDescription)")
            completionHandler?(nil)
        }
    }

    // MARK: - 隧道网络设置

    private func createTunnelSettings(for node: Node) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: node.address)

        // IPv4 设置
        let ipv4 = NEIPv4Settings(addresses: ["172.16.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0")
        ]
        settings.ipv4Settings = ipv4

        // DNS 设置
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]  // 接管所有 DNS 查询
        settings.dnsSettings = dns

        // MTU
        settings.mtu = 1500

        return settings
    }

    // MARK: - 代理引擎

    private func startProxyEngine(node: Node, completion: @escaping (Result<Void, Error>) -> Void) {
        // 真实实现：启动 sing-box 或 v2ray-core 的嵌入式版本
        // 概念框架：创建代理引擎，配置出站节点和路由规则
        let engine = ProxyEngine(node: node)
        proxyEngine = engine
        engine.start { result in
            completion(result)
        }
    }

    private func switchNode(_ node: Node) {
        logger.info("切换节点: \(node.remark, privacy: .public)")
        currentNode = node
        proxyEngine?.updateNode(node)
    }

    // MARK: - 数据包读取

    private func startReadingPackets() {
        // 从 TUN 接口读取 IP 数据包，交给代理引擎处理
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.isRunning else { return }
            for (index, packet) in packets.enumerated() {
                let proto = protocols[index] as? NSNumber
                self.proxyEngine?.handlePacket(packet, protocol: proto?.uint8Value ?? 0) { processedPacket in
                    if let processed = processedPacket {
                        self.packetFlow.writePackets([processed], withProtocols: protocols)
                    }
                }
            }
            self.startReadingPackets()  // 递归读取下一批
        }
    }

    // MARK: - 流量监控

    private func startTrafficMonitoring() {
        let monitor = TrafficMonitor { [weak self] upload, download in
            self?.logger.debug("流量: ↑\(upload) ↓\(download)")
        }
        trafficMonitor = monitor
        monitor.start()
    }
}

// MARK: - 错误类型

enum PacketTunnelError: Error, LocalizedError {
    case invalidConfiguration
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "无效的节点配置"
        case .engineStartFailed(let msg): return "代理引擎启动失败: \(msg)"
        }
    }
}

// MARK: - App 通信协议

struct TunnelRequest: Codable {
    enum RequestType: String, Codable {
        case getStatus, switchNode, getLog
    }
    var type: RequestType
    var nodeData: Data? = nil
}

struct TunnelStatus: Codable {
    var isRunning: Bool
    var nodeRemark: String
    var uploadBytes: Int64
    var downloadBytes: Int64
}

// MARK: - 代理引擎（概念框架）

/// 代理引擎协议 — 真实实现需集成 sing-box-lib 或 v2ray-core 的 iOS 框架
protocol ProxyEngineProtocol {
    func start(completion: @escaping (Result<Void, Error>) -> Void)
    func stop()
    func updateNode(_ node: Node)
    func handlePacket(_ data: Data, protocol: UInt8, completion: @escaping (Data?) -> Void)
}

final class ProxyEngine: ProxyEngineProtocol {
    private let node: Node
    private var isRunning = false

    init(node: Node) {
        self.node = node
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        // 真实实现：
        // 1. 生成 sing-box config.json（出站 = 当前节点，入站 = TUN）
        // 2. 调用 sing-box-lib 的 SBoxRun(configPath)
        // 3. 等待引擎就绪
        isRunning = true
        completion(.success(()))
    }

    func stop() {
        isRunning = false
        // 真实实现：调用 sing-box-lib 的 SBoxClose()
    }

    func updateNode(_ node: Node) {
        // 真实实现：热更新出站配置，无需重启隧道
    }

    func handlePacket(_ data: Data, protocol: UInt8, completion: @escaping (Data?) -> Void) {
        // 真实实现：将 IP 包写入 TUN fd，由 sing-box 的 tun inbound 接管
        // 概念框架：直接回传（实际由 sing-box 内核处理）
        completion(data)
    }
}

// MARK: - 流量监控（概念框架）

final class TrafficMonitor {
    private(set) var totalUpload: Int64 = 0
    private(set) var totalDownload: Int64 = 0
    private var timer: Timer?
    private let callback: (Int64, Int64) -> Void

    init(callback: @escaping (Int64, Int64) -> Void) {
        self.callback = callback
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 真实实现：从 sing-box stats API 读取流量
            self.callback(self.totalUpload, self.totalDownload)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
