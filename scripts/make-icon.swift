import AppKit
let directory = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(starting: NSColor(red: 0.32, green: 0.53, blue: 1, alpha: 1), ending: NSColor(red: 0.19, green: 0.29, blue: 0.85, alpha: 1))!.draw(in: path, angle: -75)
    NSColor.white.setFill()
    for x in [0.35, 0.65] {
        NSBezierPath(ovalIn: NSRect(x: s * (x - 0.035), y: s * 0.54, width: s * 0.07, height: s * 0.10)).fill()
    }
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: s * 0.31, y: s * 0.39))
    smile.curve(to: NSPoint(x: s * 0.69, y: s * 0.39), controlPoint1: NSPoint(x: s * 0.39, y: s * 0.22), controlPoint2: NSPoint(x: s * 0.61, y: s * 0.22))
    smile.lineWidth = s * 0.05; smile.lineCapStyle = .round
    NSColor.white.setStroke(); smile.stroke()
    image.unlockFocus()
    let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let name: String
    if size == 1024 { name = "icon_512x512@2x.png" }
    else { name = "icon_\(size)x\(size).png" }
    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    if [32,64,256,512].contains(size) {
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))
    }
}
