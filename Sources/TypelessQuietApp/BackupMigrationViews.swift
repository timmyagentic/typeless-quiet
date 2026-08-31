import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct PendingBackupImport: Identifiable {
    let id = UUID()
    let fileURL: URL
    let preview: BackupImportPreview
}

struct BackupMigrationSection: View {
    @ObservedObject var manager: AccountManager
    @ObservedObject var controller: BackupController
    @State private var localError: String?
    @State private var pendingImport: PendingBackupImport?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                securityCard
                actionsCard
                reauthenticationCard

                if let message = localError ?? controller.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(localError == nil ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background((localError == nil ? Color.blue : Color.red).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(20)
        }
        .alert(item: $pendingImport) { pending in
            Alert(
                title: Text("合并这份备份？"),
                message: Text(importConfirmation(pending.preview)),
                primaryButton: .default(Text("合并并保持守护关闭")) {
                    do {
                        _ = try controller.importFile(pending.fileURL)
                        localError = nil
                    } catch {
                        localError = error.localizedDescription
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("可移植备份 v1", systemImage: "externaldrive.badge.checkmark")
                .font(.headline)
            securityLine("不导出 Keychain 秘密、密码、token、Cookie")
            securityLine("不导出额度、运行时审计或当前登录态")
            securityLine("不复制 Typeless 设备身份或私有缓存")
            securityLine("新设备必须重新通过 Typeless 官方登录")
            Text("账号邮箱、显示名称、备注、创建时间和守护规则会进入 0600 JSON；导出后仍应像个人资料一样保管。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备份与迁移").font(.headline)
            HStack {
                Button {
                    exportBackup()
                } label: {
                    Label("导出备份…", systemImage: "square.and.arrow.up")
                }
                Button {
                    selectBackupToImport()
                } label: {
                    Label("导入并合并…", systemImage: "square.and.arrow.down")
                }
            }
            Text("导入不会删除本机账号；同邮箱保留本机 UUID、Keychain 和已验证额度。新账号无秘密、无额度，守护始终先关闭。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var reauthenticationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("新设备重新登录", systemImage: "person.badge.key")
                    .font(.headline)
                Spacer()
                Text("\(controller.accountsRequiringOfficialLogin.count) 个待验证")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(controller.accountsRequiringOfficialLogin.isEmpty ? .green : .orange)
            }
            if controller.accountsRequiringOfficialLogin.isEmpty {
                Text("当前没有待重新登录的导入账号。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.accountsRequiringOfficialLogin) { account in
                    HStack {
                        Text(account.displayName)
                        Spacer()
                        Text(account.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("打开 Typeless 官方登录") {
                        if !controller.openOfficialLogin() {
                            localError = "未能打开 Typeless 官方登录页"
                        }
                    }
                    Button("刷新验证状态") {
                        controller.refreshReauthenticationStatus()
                    }
                }
            }
        }
        .cardStyle()
    }

    private func securityLine(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "TypelessPlusPlus-Backup.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try controller.export(to: url)
                localError = nil
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func selectBackupToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let preview = try controller.previewImport(data)
                pendingImport = PendingBackupImport(fileURL: url, preview: preview)
                localError = nil
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func importConfirmation(_ preview: BackupImportPreview) -> String {
        "共 \(preview.accountCount) 个账号：新增 \(preview.addedCount)，更新 \(preview.updatedCount)，" +
            "UUID 重映射 \(preview.remappedIDCount)。\(preview.reauthenticationCount) 个新账号需要官方登录。" +
            "低额度守护将保持关闭，运行时与冷却不会导入。"
    }
}
