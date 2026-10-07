# NodeHub（节点管家）— iOS 代理配置工具

> 类似 Shadowrocket 的多协议代理客户端概念项目，包含完整 UI 设计、配置格式定义和 Swift 代码框架。

## 功能架构

```
NodeHub
├── 节点管理        添加/编辑/删除/导入节点链接，延迟测试，流量统计
├── 订阅管理        订阅源添加，自动更新，分组过滤，节点去重
├── 连接控制        一键开关，系统 VPN 集成（PacketTunnel），状态监控
├── 路由规则        可视化规则编辑器，域名/IP/GeoIP 分流，规则集导入
├── DNS 配置        自定义 DNS，DoH/DoT，分流 DNS，DNS 缓存
├── 证书管理        HTTPS 解密 CA 证书生成与安装，域名白名单
└── 设置            通用/网络/关于，本地端口配置，主题语言
```

## 支持协议

| 协议 | 传输 | 安全 |
|------|------|------|
| VLESS | raw / tcp / ws / grpc / httpupgrade | reality / tls / none |
| VMess | raw / tcp / ws / grpc / h2 | tls / none |
| Trojan | raw / tcp / ws / grpc | tls |
| Shadowsocks | raw / tcp / ws | none / tls |
| SOCKS5 | tcp | none / tls |
| HTTP | tcp | none / tls |

## 项目结构

```
NodeHub_Concept/
├── README.md                    # 本文件
├── ConfigFormat/                # 配置文件格式定义
│   ├── node_config.json         # 节点配置示例
│   ├── rules.json               # 路由规则示例
│   └── subscription.json        # 订阅配置示例
└── Swift/                       # iOS 端代码框架（SwiftUI + NetworkExtension）
    ├── Models/                  # 数据模型
    │   ├── Node.swift           # 节点模型（含各协议参数）
    │   ├── Rule.swift           # 路由规则模型
    │   └── Subscription.swift   # 订阅源模型
    ├── Services/                # 业务服务
    │   ├── LinkParser.swift     # 节点链接解析器（vless/vmess/trojan/ss）
    │   ├── SubscriptionService.swift  # 订阅更新服务
    │   ├── LatencyTester.swift  # 延迟测试服务
    │   └── ConfigStore.swift    # 本地配置持久化
    ├── ViewModels/              # ViewModel（MVVM）
    │   ├── NodeListViewModel.swift
    │   └── AddNodeViewModel.swift
    ├── Views/                   # SwiftUI 视图
    │   ├── NodeListView.swift   # 首页-节点列表
    │   ├── AddNodeView.swift    # 添加/编辑节点
    │   ├── SubscriptionView.swift
    │   ├── RuleListView.swift
    │   └── SettingsView.swift
    └── NetworkExtension/        # PacketTunnel 扩展
        └── PacketTunnelProvider.swift  # VPN 隧道核心框架
```

## 配置文件说明

所有配置以 JSON 格式存储在 App Group 共享目录中：
- `nodes.json` — 节点列表
- `subscriptions.json` — 订阅源列表
- `rules.json` — 路由规则集
- `settings.json` — 全局设置

## 与 VPS 搭建助手的配合

本 App 对应的服务端配置为 sing-box + VLESS Reality + Cloudflare WARP 双出口。
节点链接格式：
```
vless://UUID@HOST:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=SNI&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#备注名
```

## 开发环境要求

- macOS 14+ / Xcode 15+
- iOS 15.0+ 部署目标
- 付费 Apple 开发者账号（NetworkExtension 能力需要）
- Swift 5.9+ / SwiftUI
