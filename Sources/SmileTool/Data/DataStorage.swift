// Storage/ZIP workflow adapted from CodeXMicro++ v6.0.0 AppDataManager.
import Foundation
import SQLite3
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct StorageFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct BackupManifest: Codable, Sendable {
    let format: Int
    let application: String
    let createdAt: Date
    let files: [String: String]
}

struct DataStorage: Sendable {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }
    static let keys = ["hardware.remotes.v1", "hardware.deviceOrder", "nut65.editor.layer", "audio.mix.v1", "audio.hiddenCards.v1"]
    static let databaseName = "SmileTool.sqlite"
    var database: URL { root.appendingPathComponent(Self.databaseName) }
    var assets: URL { root.appendingPathComponent("Assets", isDirectory: true) }
    var keyboardBackups: URL { root.appendingPathComponent("NUT65/Backups", isDirectory: true) }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func encode(_ settings: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
    }
    static func decode(_ data: Data) throws -> [String: Any] {
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], Set(values.keys).isSubset(of: Set(keys)) else {
            throw StorageFailure(message: "设置文件包含未知内容，已停止操作。")
        }
        for (key, value) in values {
            switch key {
            case "hardware.remotes.v1":
                guard let data = value as? Data else { throw StorageFailure(message: "硬件配置格式错误。") }
                _ = try JSONDecoder().decode(RemoteHardwareConfiguration.self, from: data)
            case "audio.mix.v1":
                guard let data = value as? Data else { throw StorageFailure(message: "音频配置格式错误。") }
                _ = try JSONDecoder().decode(AudioMixConfiguration.self, from: data)
            case "hardware.deviceOrder": guard value is String else { throw StorageFailure(message: "设备排序格式错误。") }
            case "nut65.editor.layer": guard let n = value as? Int, (0...255).contains(n) else { throw StorageFailure(message: "键盘层设置无效。") }
            case "audio.hiddenCards.v1": guard value is [String] else { throw StorageFailure(message: "音频卡片设置格式错误。") }
            default: break
            }
        }
        return values
    }
    private func withDatabase<T>(write: Bool, _ body: (OpaquePointer) throws -> T) throws -> T {
        if write { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        var db: OpaquePointer?
        let flags = write ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(database.path, &db, flags, nil) == SQLITE_OK, let opened = db else {
            if let db { sqlite3_close(db) }
            throw StorageFailure(message: "无法打开数据目录中的数据库：\(database.path)")
        }
        defer { sqlite3_close(opened) }
        sqlite3_busy_timeout(opened, 3000)
        return try body(opened)
    }
    private func sql(_ db: OpaquePointer, _ statement: String) throws {
        guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else {
            throw StorageFailure(message: "数据库操作失败：\(String(cString: sqlite3_errmsg(db)))")
        }
    }
    func write(_ data: Data) throws {
        _ = try Self.decode(data)
        try withDatabase(write: true) { db in
            try sql(db, "PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL, updated REAL NOT NULL); BEGIN IMMEDIATE;")
            do {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO settings VALUES(1,?,?)", -1, &stmt, nil) == SQLITE_OK else { throw StorageFailure(message: "数据库结构不兼容。") }
                defer { sqlite3_finalize(stmt) }
                let status = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                guard status == SQLITE_OK else { throw StorageFailure(message: "无法写入配置。") }
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageFailure(message: "事务写入失败，原数据保留。") }
                try sql(db, "COMMIT")
            } catch { try? sql(db, "ROLLBACK"); throw error }
        }
        let mirror = root.appendingPathComponent("Settings.plist")
        if FileManager.default.fileExists(atPath: mirror.path) {
            let old = try Data(contentsOf: mirror)
            if old != data { try old.write(to: root.appendingPathComponent("Settings.previous.plist"), options: .atomic) }
        }
        try data.write(to: mirror, options: .atomic)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: keyboardBackups, withIntermediateDirectories: true)
    }
    func read() throws -> Data {
        try withDatabase(write: false) { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM settings WHERE id=1", -1, &stmt, nil) == SQLITE_OK else { throw StorageFailure(message: "数据库缺少有效配置。") }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) else { throw StorageFailure(message: "数据库中未找到配置。") }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 0)))
            _ = try Self.decode(data)
            return data
        }
    }
    func check() throws -> String {
        try withDatabase(write: false) { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, nil) == SQLITE_OK else { throw StorageFailure(message: "数据库检查失败。") }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW, let result = sqlite3_column_text(stmt, 0), String(cString: result) == "ok" else { throw StorageFailure(message: "数据库一致性异常，请先备份再修复。") }
        }
        let data = try read()
        let mirror = try Data(contentsOf: root.appendingPathComponent("Settings.plist"))
        guard data == mirror else { throw StorageFailure(message: "数据库与配置镜像不同步，可使用“修复”从有效数据库重建镜像。") }
        let files = try regularFiles()
        return "SQLite 完整性正常；\(try Self.decode(data).count) 项设置有效，\(files.count) 个数据文件可读取。"
    }
    func regularFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw StorageFailure(message: "数据目录无法读取。") }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { throw StorageFailure(message: "数据目录包含符号链接，已停止操作：\(url.lastPathComponent)") }
            if info.isRegularFile == true { result.append(url.standardizedFileURL.resolvingSymlinksInPath()) }
        }
        return result.sorted { $0.path < $1.path }
    }
    func relative(_ url: URL) -> String { String(url.path.dropFirst(root.path.count + 1)) }
    static func command(_ path: String, _ arguments: [String]) throws -> Data {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let result = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw StorageFailure(message: "文件操作失败（\(URL(fileURLWithPath: path).lastPathComponent)），原数据保留。") }
        return result
    }
    func export(to archive: URL, requireValid: Bool = true) throws {
        if requireValid { _ = try check() }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("SmileTool-export-\(UUID())")
        defer { try? fm.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("SmileToolBackup")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        var hashes: [String: String] = [:]
        for url in try regularFiles() {
            let name = relative(url)
            guard name != "Manifest.json" else { continue }
            let data = try Data(contentsOf: url)
            let destination = payload.appendingPathComponent(name)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            hashes[name] = Self.digest(data)
        }
        let manifest = BackupManifest(format: 1, application: "SmileTool", createdAt: Date(), files: hashes)
        try JSONEncoder().encode(manifest).write(to: payload.appendingPathComponent("Manifest.json"), options: .atomic)
        let zip = staging.appendingPathComponent("backup.zip")
        _ = try Self.command("/usr/bin/ditto", ["-c", "-k", "--keepParent", payload.path, zip.path])
        // Verify our generated archive before publishing a usable full backup.
        if requireValid { _ = try Self.unpack(zip, into: staging.appendingPathComponent("verify")) }
        let data = try Data(contentsOf: zip)
        try data.write(to: archive, options: .atomic)
    }
    static func unpack(_ archive: URL, into staging: URL) throws -> DataStorage {
        let fm = FileManager.default
        let entriesData = try command("/usr/bin/zipinfo", ["-1", archive.path])
        let entries = String(decoding: entriesData, as: UTF8.self).split(separator: "\n").map(String.init)
        guard entries.count <= 10000, !entries.isEmpty, Set(entries.map { $0.lowercased() }).count == entries.count else { throw StorageFailure(message: "ZIP 文件数量异常或含重复路径。") }
        for entry in entries {
            guard entry.hasPrefix("SmileToolBackup/"), !entry.contains("\\"), !entry.split(separator: "/").contains(".."), !entry.contains("\0") else { throw StorageFailure(message: "ZIP 含不安全路径或不是 SmileTool 备份。") }
        }
        let listing = String(decoding: try command("/usr/bin/zipinfo", ["-l", archive.path]), as: UTF8.self)
        var total: Int64 = 0
        for row in listing.split(separator: "\n") {
            let columns = row.split(whereSeparator: { $0.isWhitespace })
            if columns.first?.count == 10, let mode = columns.first {
                guard mode.first == "-" || mode.first == "d" else { throw StorageFailure(message: "ZIP 包含链接或特殊文件。") }
                guard columns.count > 3, let size = Int64(columns[3]), size >= 0 else { throw StorageFailure(message: "无法验证 ZIP 文件大小。") }
                total += size
            }
        }
        guard total <= 2_000_000_000 else { throw StorageFailure(message: "备份展开后超过 2 GB，已停止导入。") }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        _ = try command("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        let store = DataStorage(root: staging.appendingPathComponent("SmileToolBackup"))
        let files = try store.regularFiles()
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: store.root.appendingPathComponent("Manifest.json")))
        guard manifest.format == 1, manifest.application == "SmileTool" else { throw StorageFailure(message: "不支持此备份版本。") }
        let names = Set(files.map { store.relative($0) }.filter { $0 != "Manifest.json" })
        guard names == Set(manifest.files.keys) else { throw StorageFailure(message: "备份文件清单不完整。") }
        for url in files where store.relative(url) != "Manifest.json" {
            guard Self.digest(try Data(contentsOf: url)) == manifest.files[store.relative(url)] else { throw StorageFailure(message: "备份校验失败，文件可能损坏。") }
        }
        _ = try store.check()
        return store
    }
    func duplicates() throws -> [URL] {
        // Keyboard recovery history is never included in cleanup.
        var seen = Set<String>(); var duplicates: [URL] = []
        let files = try regularFiles().filter { relative($0).hasPrefix("Assets/") }
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return first == second ? $0.path > $1.path : first > second
            }
        for url in files {
            let hash = Self.digest(try Data(contentsOf: url))
            if !seen.insert(hash).inserted { duplicates.append(url) }
        }
        return duplicates
    }
    func compressImages() throws -> Int {
        let fm = FileManager.default
        let originals = root.appendingPathComponent("ImageOriginals/\(UUID())")
        var count = 0
        for url in try regularFiles() where relative(url).hasPrefix("Assets/") {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1080, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { continue }
            let alpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
            let output = NSMutableData()
            let type = alpha ? UTType.png.identifier : UTType.heic.identifier
            guard let dest = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw StorageFailure(message: "图片编码失败，已处理图片的原件仍保留。") }
            let old = try Data(contentsOf: url)
            guard output.length < old.count else { continue }
            let saved = originals.appendingPathComponent(String(relative(url).dropFirst("Assets/".count)))
            try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try old.write(to: saved, options: .atomic)
            let ext = alpha ? "png" : "heic"
            var target = url.deletingPathExtension().appendingPathExtension(ext)
            if target != url, fm.fileExists(atPath: target.path) {
                target = url.deletingLastPathComponent().appendingPathComponent("\(UUID()).\(ext)")
            }
            try (output as Data).write(to: target, options: .atomic)
            if target != url { try fm.removeItem(at: url) } // Original is already preserved above.
            count += 1
        }
        return count
    }
}
