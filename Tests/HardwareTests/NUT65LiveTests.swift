import Foundation
import Testing
@testable import SmileTool

/// Opt-in, read-only test against a physically connected NUT65 USB interface.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SMILETOOL_NUT65_USB_READ_TEST"] == "1"))
func nut65USBReadMatchesKeyByKey() throws {
    let connection = try NUT65Connection()
    let snapshot = try connection.readSnapshot()
    try snapshot.validate()
    #expect(snapshot.layers.count >= 4)
    #expect(snapshot.layers.allSatisfy { $0.count == NUT65Protocol.keysPerLayer })

    // Compare the complete map with a separate read of the physical A position.
    let row = 2, column = 1, layer = 2
    let keyCode = try connection.readKey(layer: layer, row: row, column: column)
    #expect(keyCode == snapshot.layers[layer][row * NUT65Protocol.columns + column])
}
