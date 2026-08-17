import AppKit
import Foundation
let src = URL(fileURLWithPath: "Resources/deepseek-whale.svg")
guard let img = NSImage(contentsOf: src) else { fatalError("SVG load failed") }
print("loaded size:", img.size)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep failed") }
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
img.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128), from: NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height), operation: .copy, fraction: 1)
ctx.flushGraphics()
NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
try! png.write(to: URL(fileURLWithPath: "Resources/deepseek-whale.png"))
print("saved PNG")
