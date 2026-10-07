//
//  SettingsView.swift
//  NodeHub
//
//  设置页面
//

import SwiftUI

struct SettingsView: View {

    @State private var settings = AppSettings()
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            List {
                // 通用
                Section("通用") {
                    HStack {
                        Text("语言")
                        Spacer()
                        Text("简体中文")
                            .foregroundColor(.gray)
                    }
                    Picker("主题", selection: $settings.theme) {
                        ForEach(Theme.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    Toggle("启动时自动连接", isOn: $settings.autoConnectOnLaunch)
                    Toggle("状态栏显示流量", isOn: $settings.showTrafficInStatusBar)
                }

                // 网络
                Section("网络") {
                    HStack {
                        Text("本地 SOCKS 端口")
                        Spacer()
                        TextField("", value: $settings.localSocksPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("本地 HTTP 端口")
                        Spacer()
                        TextField("", value: $settings.localHttpPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                    }
                    NavigationLink {
                        DnsSettingsView(servers: $settings.dnsServers)
                    } label: {
                        HStack {
                            Text("DNS 服务器")
                            Spacer()
                            Text(settings.dnsServers.first ?? "未设置")
                                .foregroundColor(.gray)
                        }
                    }
                    Toggle("启用 IPv6", isOn: $settings.enableIPv6)
                    Toggle("允许局域网连接", isOn: $settings.allowLAN)
                }

                // 延迟测试
                Section("延迟测试") {
                    HStack {
                        Text("测试地址")
                        Spacer()
                        Text(settings.latencyTestURL)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Stepper("超时：\(settings.latencyTestTimeout) 秒",
                            value: $settings.latencyTestTimeout, in: 3...30)
                    Stepper("并发数：\(settings.concurrentTestLimit)",
                            value: $settings.concurrentTestLimit, in: 1...50)
                }

                // 数据管理
                Section("数据管理") {
                    Button(action: exportConfig) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("导出全部配置")
                        }
                    }
                    Button(action: { }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.blue)
                            Text("导入配置")
                        }
                    }
                    Button(role: .destructive, action: clearAllData) {
                        HStack {
                            Image(systemName: "trash")
                            Text("清除全部数据")
                        }
                    }
                }

                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0 (1)")
                            .foregroundColor(.gray)
                    }
                    Button(action: { showAbout = true }) {
                        HStack {
                            Text("开源许可")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                settings = ConfigStore.shared.loadSettings()
            }
            .onChange(of: settings) { newValue in
                ConfigStore.shared.saveSettings(newValue)
            }
            .alert("关于 NodeHub", isPresented: $showAbout) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("NodeHub（节点管家）\n多协议代理客户端\n版本 1.0.0\n\n支持 VLESS / VMess / Trojan / Shadowsocks / SOCKS5 / HTTP")
            }
        }
    }

    private func exportConfig() {
        if let data = ConfigStore.shared.exportAll() {
            // 分享文件
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NodeHub_backup.json")
            try? data.write(to: tempURL)
            // 实际实现用 UIActivityViewController
        }
    }

    private func clearAllData() {
        // 清除所有配置
    }
}

struct DnsSettingsView: View {
    @Binding var servers: [String]
    @State private var newServer = ""

    var body: some View {
        Form {
            Section("DNS 服务器列表") {
                ForEach(servers, id: \.self) { server in
                    Text(server)
                        .monospacedDigit()
                }
                .onDelete(perform: deleteServer)
            }
            Section("添加 DNS") {
                HStack {
                    TextField("如 1.1.1.1", text: $newServer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.decimalPad)
                    Button("添加") {
                        if !newServer.isEmpty {
                            servers.append(newServer)
                            newServer = ""
                        }
                    }
                    .disabled(newServer.isEmpty)
                }
            }
        }
        .navigationTitle("DNS 设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteServer(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
    }
}
