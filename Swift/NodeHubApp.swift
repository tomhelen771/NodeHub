//
//  NodeHubApp.swift
//  NodeHub
//
//  App 入口 — SwiftUI App 生命周期
//

import SwiftUI

@main
struct NodeHubApp: App {

    // 全局状态
    @StateObject private var nodeListVM = NodeListViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                // 首页：节点列表
                NodeListView()
                    .tabItem {
                        Label("节点", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .environmentObject(nodeListVM)

                // 订阅管理
                SubscriptionView()
                    .tabItem {
                        Label("订阅", systemImage: "square.and.arrow.down")
                    }

                // 路由规则
                RuleListView()
                    .tabItem {
                        Label("规则", systemImage: "list.bullet.rectangle")
                    }

                // 设置
                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape")
                    }
            }
            .tint(.blue)
        }
    }
}
