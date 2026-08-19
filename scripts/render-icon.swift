import AppKit
import Foundation
let arguments = CommandLine.arguments
let sourcePath = arguments.count > 1 ? arguments[1] : "Resources/deepseek-whale.svg"
let outputPath = arguments.count > 2 ? arguments[2] : "Resources/deepseek-whale.png"
let pixelSize = arguments.count > 3 ? Int(arguments[3]) ?? 128 : 128
let src = URL(fileURLWithPath: sourcePath)
guard let img = NSImage(contentsOf: src) else { fatalError("SVG load failed") }
print("loaded size:", img.size)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep failed") }
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
img.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height), operation: .copy, fraction: 1)
ctx.flushGraphics()
NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("saved PNG")
