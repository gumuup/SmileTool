// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SmileTool", platforms: [.macOS(.v14)], products: [.executable(name: "SmileTool", targets: ["SmileTool"])], targets: [
    .executableTarget(name: "SmileTool", exclude: ["Resources"]),
    .testTarget(name: "HardwareTests", dependencies: ["SmileTool"])
])
