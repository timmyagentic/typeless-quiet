import SwiftUI
import TypelessQuietCore

enum MainWindowSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case accounts = "账号"
    case diagnostics = "诊断"

    var id: String { rawValue }
}

struct CurrentAccountCard: View {
    @ObservedObject var manager: AccountManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("当前 Typeless 账号", systemImage: "person.crop.circle")
                    .font(.headline)
                Spacer()
                if manager.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("刷新") { manager.refresh() }
                }
            }

            if let state = manager.currentState {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.displayName.flatMap { $0.isEmpty ? nil : $0 }
                            ?? state.email
                            ?? "未登录")
                            .font(.title3.weight(.semibold))
                        if let email = state.email {
                            Text(email).font(.callout).foregroundStyle(.secondary)
                        }
                        if let plan = state.planName, !plan.isEmpty {
                            Text(plan).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let quota = state.quota {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("剩余 \(quota.remainingCharacters.formatted()) 字")
                                .font(.headline)
                            Text("已用 \(quota.usedCharacters.formatted()) / \(quota.limitCharacters.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(quota.isFresh()
                                ? "同步于 \(quota.observedAt.formatted(date: .omitted, time: .shortened))"
                                : "快照已过期")
                                .font(.caption2)
                                .foregroundStyle(quota.isFresh() ? Color.secondary : Color.orange)
                        }
                    } else {
                        Text("额度未知")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                if let quota = state.quota, quota.limitCharacters > 0 {
                    ProgressView(
                        value: Double(quota.usedCharacters),
                        total: Double(quota.limitCharacters)
                    )
                }

                if state.email != nil && !manager.currentAccountIsManaged {
                    Button("添加当前账号") {
                        do {
                            try manager.addCurrentAccount()
                        } catch {
                            manager.reportOperationFailure("添加当前账号失败", error: error)
                            manager.performSelfCheck()
                        }
                    }
                }
            } else {
                Text("尚未读取到 Typeless 登录状态")
                    .foregroundStyle(.secondary)
                if let message = manager.message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .cardStyle()
    }
}

struct AccountListSection: View {
    @ObservedObject var manager: AccountManager
    @State private var editor: AccountEditorDraft?
    @State private var pendingDelete: AccountProfile?
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已有账号").font(.title3.weight(.semibold))
                    Text("秘密只保存在 macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editor = AccountEditorDraft()
                } label: {
                    Label("添加账号", systemImage: "plus")
                }
            }

            if manager.accounts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("尚未添加账号").font(.headline)
                    Text("添加你已经拥有的 Typeless 账号；本阶段不会注册新账号。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.accounts) { account in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(account.displayName).font(.headline)
                                    if manager.currentState?.email == account.email {
                                        Text("当前")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(account.email).font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(account.status.displayName)
                                    Text(account.hasSecret ? "Keychain 已保存" : "无秘密")
                                    if let quota = account.quota {
                                        Text(quota.isFresh()
                                            ? "剩余 \(quota.remainingCharacters.formatted())"
                                            : "额度快照已过期")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(
                                "启用",
                                isOn: Binding(
                                    get: { account.status != .paused },
                                    set: { enabled in
                                        do {
                                            try manager.setPaused(!enabled, accountID: account.id)
                                            localError = nil
                                        } catch {
                                            localError = error.localizedDescription
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            Button {
                                editor = AccountEditorDraft(account: account)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("编辑 \(account.displayName)")
                            Button(role: .destructive) {
                                pendingDelete = account
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("删除 \(account.displayName)")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }

            if let localError {
                Text(localError).font(.caption).foregroundStyle(.red)
            } else if let message = manager.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .sheet(item: $editor) { draft in
            AccountEditorView(manager: manager, draft: draft)
        }
        .alert(item: $pendingDelete) { account in
            Alert(
                title: Text("删除 \(account.displayName)？"),
                message: Text("账号元数据和对应 Keychain 秘密将从 Typeless++ 删除，不会修改 Typeless。"),
                primaryButton: .destructive(Text("删除")) {
                    do {
                        try manager.removeAccount(id: account.id)
                        localError = nil
                    } catch {
                        localError = error.localizedDescription
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct AccountDiagnosticsSection: View {
    @ObservedObject var manager: AccountManager

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("账号与额度自检").font(.title3.weight(.semibold))
                    Text("不会显示或记录密码、token、Cookie、验证码或设备 ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新检查") {
                    manager.refresh()
                }
            }

            List(manager.diagnostics) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.level.symbolName)
                        .foregroundStyle(item.level.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .padding(20)
    }
}

struct AccountEditorDraft: Identifiable {
    let id = UUID()
    let accountID: UUID?
    var displayName: String
    var email: String
    var note: String
    var status: AccountStatus
    var autoSwitchEligible: Bool
    var hasExistingSecret: Bool

    init(account: AccountProfile? = nil) {
        accountID = account?.id
        displayName = account?.displayName ?? ""
        email = account?.email ?? ""
        note = account?.note ?? ""
        status = account?.status ?? .available
        autoSwitchEligible = account?.autoSwitchEligible ?? false
        hasExistingSecret = account?.hasSecret ?? false
    }
}

private struct AccountEditorView: View {
    @ObservedObject var manager: AccountManager
    let draft: AccountEditorDraft
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var email: String
    @State private var note: String
    @State private var status: AccountStatus
    @State private var autoSwitchEligible: Bool
    @State private var secret = ""
    @State private var clearSecret = false
    @State private var errorText: String?

    init(manager: AccountManager, draft: AccountEditorDraft) {
        self.manager = manager
        self.draft = draft
        _displayName = State(initialValue: draft.displayName)
        _email = State(initialValue: draft.email)
        _note = State(initialValue: draft.note)
        _status = State(initialValue: draft.status)
        _autoSwitchEligible = State(initialValue: draft.autoSwitchEligible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.accountID == nil ? "添加已有账号" : "编辑账号")
                .font(.title2.weight(.semibold))

            Form {
                TextField("显示名称", text: $displayName)
                TextField("邮箱", text: $email)
                TextField("备注", text: $note)
                Picker("状态", selection: $status) {
                    ForEach(AccountStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                Toggle("允许未来的自动切换规则使用", isOn: $autoSwitchEligible)
                SecureField(
                    draft.hasExistingSecret ? "新密码（留空则保持现有）" : "密码（可选）",
                    text: $secret
                )
                if draft.hasExistingSecret {
                    Toggle("清除已保存的 Keychain 秘密", isOn: $clearSecret)
                }
            }
            .formStyle(.grouped)

            Text("Typeless++ 不会把密码写入账号 JSON，也不会读取或保存 Typeless token/Cookie。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func save() {
        do {
            if let accountID = draft.accountID {
                try manager.updateAccount(
                    id: accountID,
                    displayName: displayName,
                    email: email,
                    note: note,
                    status: status,
                    autoSwitchEligible: autoSwitchEligible,
                    newSecret: secret.isEmpty ? nil : secret,
                    clearSecret: clearSecret
                )
            } else {
                try manager.addAccount(
                    displayName: displayName,
                    email: email,
                    note: note,
                    secret: secret
                )
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private extension AccountStatus {
    var displayName: String {
        switch self {
        case .available: "可用"
        case .paused: "已暂停"
        case .exhausted: "额度用尽"
        case .unknown: "未知"
        }
    }
}

private extension AccountDiagnosticLevel {
    var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
