//
//  SubscriptionView.swift
//  NodeHub
//
//  订阅管理页面
//

import SwiftUI

struct SubscriptionView: View {

    @State private var subscriptions: [Subscription] = []
    @State private var showAddSubscription = false
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            List {
                if subscriptions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("暂无订阅源")
                            .foregroundColor(.gray)
                        Button("添加订阅") {
                            showAddSubscription = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(subscriptions) { sub in
                        SubscriptionRow(subscription: sub)
                    }
                    .onDelete(perform: deleteSubscription)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("订阅管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if isUpdating {
                            ProgressView()
                        }
                        Button(action: { showAddSubscription = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSubscription) {
                AddSubscriptionView(onSave: { sub in
                    subscriptions.append(sub)
                })
            }
            .onAppear {
                subscriptions = ConfigStore.shared.loadSubscriptions()
            }
        }
    }

    private func deleteSubscription(at offsets: IndexSet) {
        subscriptions.remove(atOffsets: offsets)
        ConfigStore.shared.saveSubscriptions(subscriptions)
    }
}

struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subscription.name)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: .constant(subscription.enabled))
                    .labelsHidden()
            }
            Text(subscription.displayURL)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
            HStack {
                Text("\(subscription.nodeCount) 个节点")
                Text("·")
                Text(subscription.lastUpdateText)
                Text("·")
                Text(subscription.type.displayName)
            }
            .font(.caption2)
            .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Subscription) -> Void

    @State private var name = ""
    @State private var url = ""
    @State private var type: SubscriptionType = .base64
    @State private var autoUpdate = true
    @State private var updateInterval = 1440

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("订阅名称", text: $name)
                    TextField("订阅链接", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("订阅类型", selection: $type) {
                        ForEach(SubscriptionType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }
                Section("自动更新") {
                    Toggle("启用自动更新", isOn: $autoUpdate)
                    if autoUpdate {
                        Stepper("更新间隔：\(updateInterval) 分钟", value: $updateInterval, in: 60...10080, step: 60)
                    }
                }
            }
            .navigationTitle("添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var sub = Subscription(name: name, url: url, type: type)
                        sub.autoUpdate = autoUpdate
                        sub.updateIntervalMinutes = updateInterval
                        onSave(sub)
                        dismiss()
                    }
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
    }
}
