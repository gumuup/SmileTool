import AppKit
import Combine
import Foundation
import Darwin

@MainActor
final class SmileDataManager: ObservableObject {
    static let shared = SmileDataManager()
    nonisolated static let pathKey = "smiletool.storagePath.v1"
    nonisolated static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SmileTool", isDirectory: true) }
    nonisolated static var configuredRoot: URL {
        if let path = UserDefaults.standard.string(forKey: pathKey) { return URL(fileURLWithPath: path, isDirectory: true) }
        return support.appendingPathComponent("Data", isDirectory: true)
    }
    @Published private(set) var directory: URL
    private let defaults: UserDefaults
    private let base: URL
    init(defaults: UserDefaults = .standard, base: URL = SmileDataManager.support) {
        self.defaults = defaults
        self.base = base.standardizedFileURL.resolvingSymlinksInPath()
        self.directory = defaults.string(forKey: Self.pathKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? self.base.appendingPathComponent("Data", isDirectory: true)
    }
    @Published private(set) var busy = false
    @Published private(set) var restartRequired = false
    @Published private(set) var problem: String?
    @Published private(set) var lastSaved: Date?
    @Published var result: String?
    private var observer: NSObjectProtocol?
    private var blocked = false
    private var applying = false
    var hardwareOperationInProgress = false
    private var lastData: Data?
    private var store: DataStorage { DataStorage(root: directory) }
    private var recovery: URL { base.appendingPathComponent("Recovery", isDirectory: true) }
    private var journal: URL {
        base.appendingPathComponent("Pending", isDirectory: true)
            .appendingPathComponent(DataStorage.digest(Data(directory.path.utf8)) + ".plist")
    }
    private func current() throws -> Data {
        var values: [String: Any] = [:]
        for key in DataStorage.keys { values[key] = defaults.object(forKey: key) }
        return try DataStorage.encode(values)
    }
    private func apply(_ data: Data) throws {
        let values = try DataStorage.decode(data)
        applying = true
        defer { applying = false }
        for key in DataStorage.keys {
            if let value = values[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        lastData = data
    }
    func prepareForLaunch() {
        do {
            let fm = FileManager.default
            if defaults.string(forKey: Self.pathKey) != nil, !fm.fileExists(atPath: store.database.path) {
                throw StorageFailure(message: "所选路径不可用或数据库缺失；本机设置与待写入副本已保留，未创建空库。")
            }
            if fm.fileExists(atPath: journal.path) {
                let pending = try Data(contentsOf: journal)
                _ = try DataStorage.decode(pending)
                try apply(pending)
                try store.write(pending)
                try fm.removeItem(at: journal)
            } else if fm.fileExists(atPath: store.database.path) {
                try apply(store.read())
            } else {
                // A configured external path disappearing must not create an empty replacement.
                guard defaults.string(forKey: Self.pathKey) == nil else {
                    throw StorageFailure(message: "所选数据路径不可用或数据库缺失。已保留本机设置，恢复路径后点击重试。")
                }
                let data = try current(); try store.write(data); lastData = data
                let legacy = base.appendingPathComponent("NUT65/Backups")
                if fm.fileExists(atPath: legacy.path) {
                    for file in try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
                        let target = store.keyboardBackups.appendingPathComponent(file.lastPathComponent)
                        if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: file, to: target) }
                    }
                }
            }
            lastSaved = Date()
        } catch { blocked = true; problem = error.localizedDescription }
    }
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }
    func persistIfStarted() {
        guard observer != nil else { return }
        save()
    }
    func save() {
        guard !busy, !restartRequired, !applying else { return }
        var pendingWritten = false
        do {
            let data = try current()
            guard data != lastData || problem != nil else { return }
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: journal, options: .atomic)
            let handle = try FileHandle(forWritingTo: journal)
            defer { try? handle.close() }
            try handle.synchronize()
            pendingWritten = true
            guard !blocked else { return }
            try store.write(data)
            lastData = data; lastSaved = Date(); problem = nil
            try FileManager.default.removeItem(at: journal)
        } catch {
            problem = (pendingWritten ? "主存储写入失败，已保留本机待写入副本。\n" : "保存尚未完成，无法确认本地副本已写入，请勿退出应用。\n") + error.localizedDescription
        }
    }
    func retry() {
        do { _ = try store.read(); blocked = false; save() }
        catch { problem = error.localizedDescription }
    }
    private func execute<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        guard !busy, !restartRequired, !hardwareOperationInProgress else { throw StorageFailure(message: "请等待当前操作完成，恢复后需重新启动应用。") }
        busy = true
        let mappings = RemoteMappingStore.shared
        let wasEditing = mappings.editing
        for remote in SupportedRemoteID.allCases { mappings.releaseAll(for: remote) }
        mappings.editing = true
        defer { busy = false; mappings.editing = wasEditing }
        return try await Task.detached(priority: .utility, operation: work).value
    }
    private func recoveryURL(_ prefix: String) throws -> URL {
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        return recovery.appendingPathComponent("\(prefix)-\(Int(Date().timeIntervalSince1970))-\(UUID()).zip")
    }
    func backup(to destination: URL) async throws {
        save()
        guard !blocked, problem == nil else { throw StorageFailure(message: problem ?? "请先恢复存储路径。") }
        guard !destination.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") else { throw StorageFailure(message: "备份请保存到数据目录以外，避免备份递归包含自身。") }
        let store = store
        try await execute { try store.export(to: destination) }
        result = "完整 ZIP 备份已保存：\(destination.path)"
    }
    func check() async throws {
        let store = store
        result = try await execute { try store.check() }
    }
    /// Build a full replacement beside the destination and swap only once validated.
    nonisolated static func replace(_ source: DataStorage, destination: URL) throws {
        let fm = FileManager.default
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".SmileTool-previous-\(UUID())")
        var committed = false
        defer { if !committed { try? fm.removeItem(at: staged) } }
        try fm.copyItem(at: source.root, to: staged)
        _ = try DataStorage(root: staged).check()
        if fm.fileExists(atPath: destination.path) {
            // Atomic exchange: even process termination leaves one complete live directory.
            guard renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                throw StorageFailure(message: "此磁盘无法安全切换数据目录（\(errno)），原数据未改动。")
            }
            committed = true // staged now holds the complete old directory; keep it.
        } else {
            try fm.moveItem(at: staged, to: destination)
            committed = true
        }
    }
    func changeDirectory(_ parent: URL, restore: Bool) async throws {
        let destination = parent.appendingPathComponent("SmileToolData", isDirectory: true).standardizedFileURL
        guard destination != directory, !destination.path.hasPrefix(base.path + "/"), !destination.path.hasPrefix(directory.path + "/"), !directory.path.hasPrefix(destination.path + "/") else { throw StorageFailure(message: "请选择独立的新目录；不能选当前数据目录、其父子目录或恢复目录。") }
        let source = store; let safety = try recoveryURL("before-path-change")
        if !restore { save(); guard problem == nil else { throw StorageFailure(message: problem!) } }
        let data = try await execute {
            try source.export(to: safety, requireValid: false)
            if restore {
                let chosen = DataStorage(root: destination)
                _ = try chosen.check()
                return try chosen.read()
            }
            let fm = FileManager.default
            guard !fm.fileExists(atPath: destination.path) else { throw StorageFailure(message: "目标已有 SmileToolData，请使用“从路径恢复”；为保护已有数据，不直接覆盖。") }
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try Self.replace(source, destination: destination)
            return try source.read()
        }
        if restore { restartRequired = true }
        directory = destination
        defaults.set(destination.path, forKey: Self.pathKey)
        blocked = false; problem = nil
        if restore { try apply(data); restartRequired = true }
        result = restore ? "已切换并恢复数据。请重新启动 SmileTool。" : "已迁移全部数据，后续自动优先保存到所选路径。原目录仍保留。"
    }
    func restore(from archive: URL) async throws {
        let source = store; let safety = try recoveryURL("before-import")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SmileTool-import-\(UUID())")
        let data = try await execute {
            defer { try? FileManager.default.removeItem(at: temp) }
            let restored = try DataStorage.unpack(archive, into: temp)
            let data = try restored.read()
            try source.export(to: safety, requireValid: false)
            try Self.replace(restored, destination: source.root)
            return data
        }
        try apply(data); blocked = false; problem = nil; restartRequired = true
        if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.moveItem(at: journal, to: recovery.appendingPathComponent("pending-before-import-\(UUID()).plist")) }
        result = "备份已校验并恢复。旧数据已自动备份。请重新启动 SmileTool。"
    }
    func repair() async throws {
        let source = store; let safety = try recoveryURL("before-repair")
        let current = try current()
        try await execute {
            try source.export(to: safety, requireValid: false)
            if let data = try? source.read() { try source.write(data); return }
            // Corrupt database is preserved; rebuild a separate replacement from a valid mirror.
            let mirrors = ["Settings.plist", "Settings.previous.plist"]
            var valid: Data?
            for name in mirrors {
                if let data = try? Data(contentsOf: source.root.appendingPathComponent(name)), (try? DataStorage.decode(data)) != nil { valid = data; break }
            }
            let data = valid ?? current
            _ = try DataStorage.decode(data)
            let copy = source.root.deletingLastPathComponent().appendingPathComponent(".SmileTool-repair-\(UUID())")
            defer { try? FileManager.default.removeItem(at: copy) }
            try FileManager.default.copyItem(at: source.root, to: copy)
            try FileManager.default.removeItem(at: copy.appendingPathComponent(DataStorage.databaseName))
            let repaired = DataStorage(root: copy); try repaired.write(data)
            try Self.replace(repaired, destination: source.root)
        }
        blocked = false; problem = nil; restartRequired = true
        if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.moveItem(at: journal, to: recovery.appendingPathComponent("pending-before-repair-\(UUID()).plist")) }
        result = "修复完成，原数据已备份。请重新启动，以数据库中的有效设置为准。"
    }
    func reset() async throws {
        let source = store; let safety = try recoveryURL("before-reset")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SmileTool-reset-\(UUID())")
        let empty = try DataStorage.encode([:])
        try await execute {
            defer { try? FileManager.default.removeItem(at: temp) }
            try source.export(to: safety, requireValid: false)
            let fresh = DataStorage(root: temp); try fresh.write(empty)
            try Self.replace(fresh, destination: source.root)
        }
        try apply(empty); restartRequired = true; problem = nil
        if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.moveItem(at: journal, to: recovery.appendingPathComponent("pending-before-reset-\(UUID()).plist")) }
        result = "已创建空数据库，旧数据已完整备份并保留目录副本。请重新启动。"
    }
    func cleanup(remove: Bool) async throws {
        let source = store; let safety = try recoveryURL("before-cleanup")
        let count = try await execute {
            let duplicates = try source.duplicates()
            if remove, !duplicates.isEmpty {
                try source.export(to: safety)
                let retained = source.root.appendingPathComponent("RecoveredDuplicates/\(UUID())")
                for url in duplicates {
                    let target = retained.appendingPathComponent(source.relative(url))
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: url, to: target)
                }
            }
            return duplicates.count
        }
        result = remove ? "已将 \(count) 个重复素材移入恢复区。唯一素材与键盘历史备份保留。" : "发现 \(count) 个内容完全相同的重复素材；仅检查 Assets，保留唯一数据与键盘备份。"
    }
    func compress() async throws {
        let source = store; let safety = try recoveryURL("before-compression")
        let count = try await execute {
            try source.export(to: safety)
            return try source.compressImages()
        }
        result = "已压缩 \(count) 张图片；原件保存在 ImageOriginals，完整操作前备份保存在恢复目录。"
    }
    func importImages(_ urls: [URL]) async throws {
        let destination = store.assets
        try await execute {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for url in urls {
                let name = "\(Int(Date().timeIntervalSince1970))-\(UUID()).\(url.pathExtension)"
                try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent(name))
            }
        }
        result = "已将 \(urls.count) 个图片副本加入本地素材库；原文件未改动。"
    }
    func openDirectory() { NSWorkspace.shared.open(directory) }
    func openRecovery() {
        do { try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true); NSWorkspace.shared.open(recovery) }
        catch { problem = error.localizedDescription }
    }
}
