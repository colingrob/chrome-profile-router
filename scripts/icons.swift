import AppKit
let extensionDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let resourceDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
func icon(_ size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 128
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.34, green: 0.31, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 128, height: 128), xRadius: 28, yRadius: 28).fill()
    NSColor.white.setStroke()
    let path = NSBezierPath(); path.lineWidth = 9; path.lineCapStyle = .round; path.lineJoinStyle = .round
    path.move(to: NSPoint(x: 44, y: 26)); path.line(to: NSPoint(x: 44, y: 101))
    path.move(to: NSPoint(x: 44, y: 51)); path.curve(to: NSPoint(x: 87, y: 94), controlPoint1: NSPoint(x: 82, y: 51), controlPoint2: NSPoint(x: 87, y: 72))
    path.move(to: NSPoint(x: 30, y: 87)); path.line(to: NSPoint(x: 44, y: 101)); path.line(to: NSPoint(x: 58, y: 87))
    path.move(to: NSPoint(x: 73, y: 82)); path.line(to: NSPoint(x: 87, y: 96)); path.line(to: NSPoint(x: 101, y: 82)); path.stroke()
    image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}
for size in [16, 48, 128] { try icon(size).write(to: extensionDirectory.appendingPathComponent("icon\(size).png")) }
let iconset = resourceDirectory.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try icon(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resourceDirectory.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: iconset)
