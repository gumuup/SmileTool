import Foundation
import Testing
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import SmileTool

private func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SmileTool-test-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func localDatabaseAndCompleteArchiveRoundTrip() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DataStorage(root: root.appendingPathComponent("data"))
    var hardware = RemoteHardwareConfiguration()
    hardware.mappings["x6.voice"] = .init(action: .shortcut(name: "语音输入"))
    let preferences = try DataStorage.encode(["hardware.remotes.v1": JSONEncoder().encode(hardware), "hardware.deviceOrder": "x6,nut65", "nut65.editor.layer": 3])
    try store.write(preferences)
    try Data("keyboard recovery".utf8).write(to: store.keyboardBackups.appendingPathComponent("original.json"))
    try Data("asset".utf8).write(to: store.assets.appendingPathComponent("example.dat"))
    #expect(try store.read() == preferences)
    #expect(try store.check().contains("正常"))
    let zip = root.appendingPathComponent("backup.zip")
    try store.export(to: zip)
    let restored = try DataStorage.unpack(zip, into: root.appendingPathComponent("unpacked"))
    #expect(try restored.read() == preferences)
    #expect(try Data(contentsOf: restored.keyboardBackups.appendingPathComponent("original.json")) == Data("keyboard recovery".utf8))
    #expect(try Data(contentsOf: restored.assets.appendingPathComponent("example.dat")) == Data("asset".utf8))
}

@Test func invalidSettingsNeverReplaceValidDatabase() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DataStorage(root: root)
    let good = try DataStorage.encode(["nut65.editor.layer": 2])
    try store.write(good)
    #expect(throws: (any Error).self) { try store.write(DataStorage.encode(["hardware.remotes.v1": Data("invalid".utf8)])) }
    #expect(try store.read() == good)
    try store.write(DataStorage.encode(["nut65.editor.layer": 3]))
    #expect(try Data(contentsOf: root.appendingPathComponent("Settings.previous.plist")) == good)
}

@Test func damagedBackupRejectedWithoutTouchingActiveData() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DataStorage(root: root.appendingPathComponent("data"))
    let good = try DataStorage.encode(["nut65.editor.layer": 2]); try store.write(good)
    let zip = root.appendingPathComponent("good.zip"); try store.export(to: zip)
    let payload = try DataStorage.unpack(zip, into: root.appendingPathComponent("unpacked"))
    try Data("tampered".utf8).write(to: payload.root.appendingPathComponent("Settings.plist"))
    let broken = root.appendingPathComponent("broken.zip")
    _ = try DataStorage.command("/usr/bin/ditto", ["-c", "-k", "--keepParent", payload.root.path, broken.path])
    #expect(throws: (any Error).self) { try DataStorage.unpack(broken, into: root.appendingPathComponent("bad")) }
    #expect(try store.read() == good)
}

@Test func archiveLinksAndForeignArchivesRejected() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let payload = root.appendingPathComponent("SmileToolBackup")
    try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: payload.appendingPathComponent("link").path, withDestinationPath: "/tmp")
    let zip = root.appendingPathComponent("link.zip")
    _ = try DataStorage.command("/usr/bin/ditto", ["-c", "-k", "--keepParent", payload.path, zip.path])
    #expect(throws: (any Error).self) { try DataStorage.unpack(zip, into: root.appendingPathComponent("out")) }
}

@Test func duplicateInspectionExcludesKeyboardRecoveryHistory() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DataStorage(root: root); try store.write(DataStorage.encode([:]))
    let data = Data("identical".utf8)
    for name in ["old.png", "new.png"] {
        try data.write(to: store.assets.appendingPathComponent(name))
        try data.write(to: store.keyboardBackups.appendingPathComponent(name))
    }
    let duplicates = try store.duplicates()
    #expect(duplicates.count == 1)
    #expect(duplicates.allSatisfy { $0.deletingLastPathComponent().path == store.assets.path })
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.keyboardBackups.path).count == 2)
}

@Test func imageCompressionPreservesOriginalAndUsesCorrectExtension() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DataStorage(root: root); try store.write(DataStorage.encode([:]))
    let context = try #require(CGContext(data: nil, width: 2200, height: 1400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2200, height: 1400))
    let image = try #require(context.makeImage())
    let original = store.assets.appendingPathComponent("photo.tiff")
    let destination = try #require(CGImageDestinationCreateWithURL(original as CFURL, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
    let bytes = try Data(contentsOf: original)
    #expect(try store.compressImages() == 1)
    let output = store.assets.appendingPathComponent("photo.heic")
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let compressed = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(compressed.width, compressed.height) <= 1080)
    let saved = try store.regularFiles().filter { store.relative($0).hasPrefix("ImageOriginals/") }
    #expect(saved.count == 1)
    #expect(try Data(contentsOf: saved[0]) == bytes)
}

@Test func directoryReplacementPreservesCompletePreviousData() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let old = DataStorage(root: root.appendingPathComponent("live"))
    let new = DataStorage(root: root.appendingPathComponent("new"))
    let previous = try DataStorage.encode(["nut65.editor.layer": 2])
    let next = try DataStorage.encode(["nut65.editor.layer": 3])
    try old.write(previous); try new.write(next)
    try SmileDataManager.replace(new, destination: old.root)
    #expect(try old.read() == next)
    let preserved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".SmileTool-previous-") }
    #expect(preserved.count == 1)
    #expect(try DataStorage(root: preserved[0]).read() == previous)
}

@MainActor @Test func preferencesRecoverOnLaunchAndSavingDoesNotDependOnWindow() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let suite = "SmileTool.storage.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(2, forKey: "nut65.editor.layer")
    let first = SmileDataManager(defaults: defaults, base: root)
    first.prepareForLaunch()
    defaults.set(3, forKey: "nut65.editor.layer"); first.save()
    #expect(first.problem == nil)
    defaults.set(0, forKey: "nut65.editor.layer") // Simulate an out-of-date preference cache.
    let reopened = SmileDataManager(defaults: defaults, base: root)
    reopened.prepareForLaunch()
    #expect(reopened.problem == nil)
    #expect(defaults.integer(forKey: "nut65.editor.layer") == 3)
}

@MainActor @Test func unavailableConfiguredStoreNeverCreatesBlankDatabase() throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let suite = "SmileTool.offline.tests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
    let missing = root.appendingPathComponent("disconnected/SmileToolData")
    defaults.set(missing.path, forKey: SmileDataManager.pathKey)
    defaults.set(3, forKey: "nut65.editor.layer")
    let manager = SmileDataManager(defaults: defaults, base: root.appendingPathComponent("support"))
    manager.prepareForLaunch(); manager.save()
    #expect(manager.problem != nil)
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    #expect(defaults.integer(forKey: "nut65.editor.layer") == 3)
    let pending = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("support/Pending"), includingPropertiesForKeys: nil)
    #expect(pending.count == 1)
    let reopened = SmileDataManager(defaults: defaults, base: root.appendingPathComponent("support"))
    reopened.prepareForLaunch()
    #expect(reopened.problem != nil)
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}
