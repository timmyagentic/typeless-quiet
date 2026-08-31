import Foundation

public struct PortableBackupSecurity: Codable, Equatable, Sendable {
    public var secretsIncluded: Bool
    public var deviceIdentityIncluded: Bool
    public var requiresOfficialReauthentication: Bool

    public init(
        secretsIncluded: Bool = false,
        deviceIdentityIncluded: Bool = false,
        requiresOfficialReauthentication: Bool = true
    ) {
        self.secretsIncluded = secretsIncluded
        self.deviceIdentityIncluded = deviceIdentityIncluded
        self.requiresOfficialReauthentication = requiresOfficialReauthentication
    }
}

public struct PortableAccount: Codable, Equatable, Identifiable, Sendable {
    public var sourceID: UUID
    public var displayName: String
    public var email: String
    public var note: String
    public var createdAt: Date

    public var id: UUID { sourceID }

    public init(
        sourceID: UUID,
        displayName: String,
        email: String,
        note: String,
        createdAt: Date
    ) {
        self.sourceID = sourceID
        self.displayName = displayName
        self.email = email
        self.note = note
        self.createdAt = createdAt
    }
}

public struct PortableQuotaGuard: Codable, Equatable, Sendable {
    public var wasEnabled: Bool
    public var thresholdCharacters: Int
    public var accountPool: [UUID]
    public var cooldownMinutes: Int

    public init(
        wasEnabled: Bool,
        thresholdCharacters: Int,
        accountPool: [UUID],
        cooldownMinutes: Int
    ) {
        self.wasEnabled = wasEnabled
        self.thresholdCharacters = thresholdCharacters
        self.accountPool = accountPool
        self.cooldownMinutes = cooldownMinutes
    }
}

public struct PortableBackup: Codable, Equatable, Sendable {
    public static let currentFormat = "typeless-plusplus-backup"
    public static let currentSchemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var security: PortableBackupSecurity
    public var accounts: [PortableAccount]
    public var quotaGuard: PortableQuotaGuard

    public init(
        format: String = PortableBackup.currentFormat,
        schemaVersion: Int = PortableBackup.currentSchemaVersion,
        exportedAt: Date,
        appVersion: String,
        security: PortableBackupSecurity = PortableBackupSecurity(),
        accounts: [PortableAccount],
        quotaGuard: PortableQuotaGuard
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.security = security
        self.accounts = accounts
        self.quotaGuard = quotaGuard
    }
}

public enum PortableBackupError: String, Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge
    case invalidFormat
    case unsupportedSchema
    case unsafeSecurityManifest
    case tooManyAccounts
    case duplicateEmail
    case duplicateAccountID
    case invalidAccount
    case invalidPoolReference
    case invalidValue
    case forbiddenField
    case cannotGenerateAccountID

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: "备份文件超过 5 MiB"
        case .invalidFormat: "不是 Typeless++ 备份文件"
        case .unsupportedSchema: "备份版本不受支持"
        case .unsafeSecurityManifest: "备份声称包含秘密或设备身份"
        case .tooManyAccounts: "备份账号数量超过上限"
        case .duplicateEmail: "备份包含重复邮箱"
        case .duplicateAccountID: "备份包含重复账号 UUID"
        case .invalidAccount: "备份包含无效账号字段"
        case .invalidPoolReference: "守护账号池引用了不存在或重复的账号"
        case .invalidValue: "备份包含越界配置"
        case .forbiddenField: "备份包含本格式禁止的本地状态字段"
        case .cannotGenerateAccountID: "无法为冲突账号生成本机 UUID"
        }
    }
}

public enum PortableBackupCodec {
    public static let maximumByteCount = 5 * 1_024 * 1_024
    public static let maximumAccountCount = 1_000

    public static func makeBackup(
        directory: AccountDirectory,
        quotaGuard: QuotaGuardConfiguration,
        appVersion: String,
        exportedAt: Date = Date()
    ) throws -> PortableBackup {
        let accounts = directory.accounts.map {
            PortableAccount(
                sourceID: $0.id,
                displayName: $0.displayName,
                email: $0.email,
                note: $0.note,
                createdAt: $0.createdAt
            )
        }
        let knownIDs = Set(accounts.map(\.sourceID))
        var seenPoolIDs = Set<UUID>()
        let sanitizedPool = quotaGuard.accountPool.filter {
            knownIDs.contains($0) && seenPoolIDs.insert($0).inserted
        }
        let backup = PortableBackup(
            exportedAt: exportedAt,
            appVersion: appVersion,
            accounts: accounts,
            quotaGuard: PortableQuotaGuard(
                wasEnabled: quotaGuard.isEnabled,
                thresholdCharacters: QuotaGuardConfiguration.normalizeThreshold(
                    quotaGuard.thresholdCharacters
                ),
                accountPool: sanitizedPool,
                cooldownMinutes: QuotaGuardConfiguration.normalizeCooldownMinutes(
                    quotaGuard.cooldownMinutes
                )
            )
        )
        try validate(backup)
        return backup
    }

    public static func encode(_ backup: PortableBackup) throws -> Data {
        try validate(backup)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        guard data.count <= maximumByteCount else {
            throw PortableBackupError.fileTooLarge
        }
        return data
    }

    public static func decode(_ data: Data) throws -> PortableBackup {
        guard data.count <= maximumByteCount else {
            throw PortableBackupError.fileTooLarge
        }
        if try containsForbiddenFields(data) {
            throw PortableBackupError.forbiddenField
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PortableBackup.self, from: data)
        try validate(backup)
        return backup
    }

    public static func validate(_ backup: PortableBackup) throws {
        guard backup.format == PortableBackup.currentFormat else {
            throw PortableBackupError.invalidFormat
        }
        guard backup.schemaVersion == PortableBackup.currentSchemaVersion else {
            throw PortableBackupError.unsupportedSchema
        }
        guard !backup.security.secretsIncluded,
              !backup.security.deviceIdentityIncluded,
              backup.security.requiresOfficialReauthentication
        else {
            throw PortableBackupError.unsafeSecurityManifest
        }
        guard backup.accounts.count <= maximumAccountCount else {
            throw PortableBackupError.tooManyAccounts
        }
        guard !backup.appVersion.isEmpty, backup.appVersion.count <= 100 else {
            throw PortableBackupError.invalidValue
        }

        var emails = Set<String>()
        var ids = Set<UUID>()
        for account in backup.accounts {
            guard let email = AccountProfile.normalizedEmail(account.email),
                  account.email.caseInsensitiveCompare(email) == .orderedSame,
                  !account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  account.displayName.count <= 256,
                  account.email.count <= 320,
                  account.note.count <= 4_096
            else {
                throw PortableBackupError.invalidAccount
            }
            guard emails.insert(email).inserted else {
                throw PortableBackupError.duplicateEmail
            }
            guard ids.insert(account.sourceID).inserted else {
                throw PortableBackupError.duplicateAccountID
            }
        }

        let pool = backup.quotaGuard.accountPool
        guard Set(pool).count == pool.count,
              pool.allSatisfy(ids.contains)
        else {
            throw PortableBackupError.invalidPoolReference
        }
        guard (0 ... 50_000).contains(backup.quotaGuard.thresholdCharacters),
              (1 ... 1_440).contains(backup.quotaGuard.cooldownMinutes)
        else {
            throw PortableBackupError.invalidValue
        }
    }

    private static func containsForbiddenFields(_ data: Data) throws -> Bool {
        let object = try JSONSerialization.jsonObject(with: data)
        let forbidden = Set([
            "hassecret",
            "quota",
            "quotasnapshot",
            "runtime",
            "guardruntime",
            "audit",
            "switchaudit",
            "password",
            "secret",
            "secrets",
            "credentials",
            "authorization",
            "token",
            "accesstoken",
            "access_token",
            "refreshtoken",
            "refresh_token",
            "cookie",
            "deviceidentifier",
            "deviceidentity",
            "devicecache",
            "device.cache",
            "device_id",
        ])
        func inspect(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if forbidden.contains(key.lowercased()) || inspect(child) {
                        return true
                    }
                }
            } else if let array = value as? [Any] {
                return array.contains(where: inspect)
            }
            return false
        }
        return inspect(object)
    }
}

public struct BackupMigrationPlan: Equatable, Sendable {
    public let directory: AccountDirectory
    public let quotaGuard: QuotaGuardDocument
    public let addedCount: Int
    public let updatedCount: Int
    public let remappedIDCount: Int
    public let requiresOfficialReauthentication: [UUID]
}

public enum BackupMigrationPlanner {
    public static func plan(
        backup: PortableBackup,
        existing: AccountDirectory,
        now: Date = Date(),
        generateID: () -> UUID = UUID.init
    ) throws -> BackupMigrationPlan {
        try PortableBackupCodec.validate(backup)
        var directory = existing
        var usedIDs = Set(existing.accounts.map(\.id))
        var sourceToLocal: [UUID: UUID] = [:]
        var addedCount = 0
        var updatedCount = 0
        var remappedIDCount = 0
        var reauthenticationIDs: [UUID] = []

        for portable in backup.accounts {
            let normalizedEmail = AccountProfile.normalizedEmail(portable.email)!
            if let local = directory.account(matchingEmail: normalizedEmail) {
                let updated = try AccountProfile(
                    id: local.id,
                    displayName: portable.displayName,
                    email: normalizedEmail,
                    note: portable.note,
                    status: local.status,
                    autoSwitchEligible: local.autoSwitchEligible,
                    quota: local.quota,
                    hasSecret: local.hasSecret,
                    createdAt: local.createdAt,
                    updatedAt: now
                )
                try directory.update(updated)
                sourceToLocal[portable.sourceID] = local.id
                updatedCount += 1
                continue
            }

            var localID = portable.sourceID
            if usedIDs.contains(localID) {
                var replacement: UUID?
                for _ in 0 ..< 100 {
                    let candidate = generateID()
                    if !usedIDs.contains(candidate) {
                        replacement = candidate
                        break
                    }
                }
                guard let replacement else {
                    throw PortableBackupError.cannotGenerateAccountID
                }
                localID = replacement
                remappedIDCount += 1
            }
            let imported = try AccountProfile(
                id: localID,
                displayName: portable.displayName,
                email: normalizedEmail,
                note: portable.note,
                status: .unknown,
                autoSwitchEligible: false,
                quota: nil,
                hasSecret: false,
                createdAt: portable.createdAt,
                updatedAt: now
            )
            try directory.add(imported)
            usedIDs.insert(localID)
            sourceToLocal[portable.sourceID] = localID
            reauthenticationIDs.append(localID)
            addedCount += 1
        }

        let mappedPool = backup.quotaGuard.accountPool.compactMap { sourceToLocal[$0] }
        let guardConfiguration = QuotaGuardConfiguration(
            isEnabled: false,
            thresholdCharacters: backup.quotaGuard.thresholdCharacters,
            accountPool: mappedPool,
            cooldownMinutes: backup.quotaGuard.cooldownMinutes
        )
        return BackupMigrationPlan(
            directory: directory,
            quotaGuard: QuotaGuardDocument(
                configuration: guardConfiguration,
                runtime: QuotaGuardRuntime()
            ),
            addedCount: addedCount,
            updatedCount: updatedCount,
            remappedIDCount: remappedIDCount,
            requiresOfficialReauthentication: reauthenticationIDs
        )
    }
}
