//
//  RuleListView.swift
//  NodeHub
//
//  路由规则页面
//

import SwiftUI

struct RuleListView: View {

    @State private var ruleSets: [RuleSet] = []
    @State private var selectedFilter: RuleAction? = nil
    @State private var showAddRule = false

    private var filteredRules: [Rule] {
        guard let set = ruleSets.first(where: { $0.isActive }) else { return [] }
        guard let filter = selectedFilter else { return set.rules }
        return set.rules.filter { $0.action == filter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分段筛选
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "全部", isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }
                        FilterChip(title: "代理", isSelected: selectedFilter == .proxy) {
                            selectedFilter = .proxy
                        }
                        FilterChip(title: "直连", isSelected: selectedFilter == .direct) {
                            selectedFilter = .direct
                        }
                        FilterChip(title: "拦截", isSelected: selectedFilter == .block) {
                            selectedFilter = .block
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                List {
                    if filteredRules.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("暂无规则")
                                .foregroundColor(.gray)
                            Button("添加规则") { showAddRule = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredRules) { rule in
                            RuleRow(rule: rule)
                        }
                        .onDelete(perform: deleteRule)
                        .onMove(perform: moveRule)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("路由规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddRule = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddRule) {
                AddRuleView { rule in
                    if var set = ruleSets.first(where: { $0.isActive }) {
                        set.rules.append(rule)
                        if let index = ruleSets.firstIndex(where: { $0.isActive }) {
                            ruleSets[index] = set
                        }
                        ConfigStore.shared.saveRuleSets(ruleSets)
                    }
                }
            }
            .onAppear {
                ruleSets = ConfigStore.shared.loadRuleSets()
                if ruleSets.isEmpty {
                    ruleSets = [RuleSet(name: "默认规则集", description: "国内直连/国外代理", isActive: true, rules: defaultRules())]
                    ConfigStore.shared.saveRuleSets(ruleSets)
                }
            }
        }
    }

    private func deleteRule(at offsets: IndexSet) {
        guard var set = ruleSets.first(where: { $0.isActive }) else { return }
        let rules = filteredRules
        for index in offsets {
            if let originalIndex = set.rules.firstIndex(where: { $0.id == rules[index].id }) {
                set.rules.remove(at: originalIndex)
            }
        }
        if let index = ruleSets.firstIndex(where: { $0.isActive }) {
            ruleSets[index] = set
        }
        ConfigStore.shared.saveRuleSets(ruleSets)
    }

    private func moveRule(from source: IndexSet, to destination: Int) {
        guard var set = ruleSets.first(where: { $0.isActive }) else { return }
        set.rules.move(fromOffsets: source, toOffset: destination)
        if let index = ruleSets.firstIndex(where: { $0.isActive }) {
            ruleSets[index] = set
        }
        ConfigStore.shared.saveRuleSets(ruleSets)
    }

    private func defaultRules() -> [Rule] {
        [
            Rule(type: .domainSuffix, value: "google.com", action: .proxy, remark: "Google 走代理"),
            Rule(type: .domainKeyword, value: "youtube", action: .proxy, remark: "YouTube 走代理"),
            Rule(type: .domainSuffix, value: "github.com", action: .proxy, remark: "GitHub 走代理"),
            Rule(type: .domainSuffix, value: "baidu.com", action: .direct, remark: "百度直连"),
            Rule(type: .geoip, value: "CN", action: .direct, remark: "中国 IP 直连"),
            Rule(type: .ipCidr, value: "10.0.0.0/8", action: .direct, noResolve: true, remark: "内网直连"),
            Rule(type: .ipCidr, value: "192.168.0.0/16", action: .direct, noResolve: true, remark: "内网直连"),
            Rule(type: .match, value: "", action: .proxy, remark: "兜底：全部走代理")
        ]
    }
}

struct RuleRow: View {
    let rule: Rule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.type.iconName)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayText)
                    .font(.subheadline)
                    .lineLimit(1)
                if !rule.remark.isEmpty {
                    Text(rule.remark)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Text(rule.action.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: rule.action.colorHex))
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

struct AddRuleView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Rule) -> Void

    @State private var type: RuleType = .domainSuffix
    @State private var value = ""
    @State private var action: RuleAction = .proxy
    @State private var remark = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("规则类型") {
                    Picker("类型", selection: $type) {
                        ForEach(RuleType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                }
                Section("匹配值") {
                    if type == .match {
                        Text("MATCH 为兜底规则，无需填写匹配值")
                            .foregroundColor(.gray)
                    } else {
                        TextField("输入匹配值", text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section("动作") {
                    Picker("动作", selection: $action) {
                        ForEach(RuleAction.allCases, id: \.self) { a in
                            Text(a.displayName).tag(a)
                        }
                    }
                }
                Section("备注") {
                    TextField("可选备注", text: $remark)
                }
            }
            .navigationTitle("添加规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(Rule(type: type, value: value, action: action, remark: remark))
                        dismiss()
                    }
                    .disabled(type != .match && value.isEmpty)
                }
            }
        }
    }
}
