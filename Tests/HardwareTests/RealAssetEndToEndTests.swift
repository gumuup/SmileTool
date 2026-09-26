import Foundation
import ImageIO
import Testing
@testable import SmileTool

private enum RealAssets {
    static let names = [
        "chromecast-voice-remote.png",
        "dji-mic-mini-2.png",
        "mx-master-3s.png",
        "nut65-keyboard.png",
        "x6-remote.png"
    ]

    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HardwareTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository
            .appendingPathComponent("Sources/SmileTool/Resources")
    }

    static func image(at url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "Cannot open \(url.lastPathComponent)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "Cannot decode \(url.lastPathComponent)")
    }
}

@Test func realDeviceImagesSurviveCompleteBackupAndRestore() throws {
    let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("SmileTool-real-assets-\(UUID())")
    try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sandbox) }

    let live = DataStorage(root: sandbox.appendingPathComponent("live"))
    var configuration = RemoteHardwareConfiguration()
    for remote in SupportedRemoteID.allCases {
        let button = try #require(RemoteProfiles.buttons(for: remote).first)
        configuration.mappings["\(remote.rawValue).\(button.id)"] = .init(action: .shortcut(name: "实测-\(remote.title)"))
    }
    let settings = try DataStorage.encode([
        "hardware.remotes.v1": JSONEncoder().encode(configuration),
        "hardware.deviceOrder": "nut65,mxMaster3s,djiMicMini2,x6,chromecast",
        "nut65.editor.layer": 2
    ])
    try live.write(settings)

    var originalHashes: [String: String] = [:]
    for name in RealAssets.names {
        let source = RealAssets.directory.appendingPathComponent(name)
        let original = try Data(contentsOf: source)
        let image = try RealAssets.image(at: source)
        #expect(image.width > 0 && image.height > 0)
        originalHashes[name] = DataStorage.digest(original)
        try original.write(to: live.assets.appendingPathComponent(name))
    }
    #expect(try live.check().contains("正常"))

    let archive = sandbox.appendingPathComponent("complete.zip")
    try live.export(to: archive)
    #expect((try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0)
    let unpacked = try DataStorage.unpack(archive, into: sandbox.appendingPathComponent("unpacked"))
    let restoredSettings = try unpacked.read()
    let decoded = try DataStorage.decode(restoredSettings)
    let restoredConfiguration = try JSONDecoder().decode(RemoteHardwareConfiguration.self, from: #require(decoded["hardware.remotes.v1"] as? Data))
    #expect(restoredConfiguration.mappings.count == SupportedRemoteID.allCases.count)
    #expect(decoded["nut65.editor.layer"] as? Int == 2)

    let oldSettings = try DataStorage.encode(["nut65.editor.layer": 1])
    let destination = DataStorage(root: sandbox.appendingPathComponent("destination"))
    try destination.write(oldSettings)
    try SmileDataManager.replace(unpacked, destination: destination.root)
    #expect(try destination.read() == settings)
    for name in RealAssets.names {
        let restored = destination.assets.appendingPathComponent(name)
        #expect(DataStorage.digest(try Data(contentsOf: restored)) == originalHashes[name])
        let image = try RealAssets.image(at: restored)
        #expect(image.width > 0 && image.height > 0)
        #expect(DataStorage.digest(try Data(contentsOf: RealAssets.directory.appendingPathComponent(name))) == originalHashes[name])
    }
    let preserved = try FileManager.default.contentsOfDirectory(at: sandbox, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".SmileTool-previous-") }
    #expect(preserved.count == 1)
    #expect(try DataStorage(root: #require(preserved.first)).read() == oldSettings)
}
