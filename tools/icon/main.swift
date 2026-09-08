import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draws the 1024×1024 app icon: a barbell on a deep blue ground. No text — it has to read
// at 40 pt on a home screen.
//
// v1.4 (D49): drawn **without an alpha channel**. App Store Connect rejects a 1024-pixel icon
// that carries one, even when every pixel is opaque, and `premultipliedLast` wrote one. The
// ground covers the whole square, so nothing is lost; `tools/check_release.py` reads the PNG's
// colour type to make sure it stays this way.
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("no context")
}

func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, 1])!
}

// Background: a vertical gradient, darker at the bottom so the bar stands off it.
let gradient = CGGradient(colorsSpace: space,
                          colors: [color(0.13, 0.44, 0.96), color(0.05, 0.20, 0.55)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: 0, y: 0), options: [])

let white = color(1, 1, 1)
context.setFillColor(white)

let centreY = Double(size) / 2
func bar(x: Double, width: Double, height: Double, radius: Double) {
    let rect = CGRect(x: x, y: centreY - height / 2, width: width, height: height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
    context.fillPath()
}

// The bar, then the inner and outer plates on each side.
bar(x: 232, width: 560, height: 56, radius: 28)
for x in [232.0, 712.0] { bar(x: x, width: 80, height: 300, radius: 26) }
for x in [140.0, 824.0] { bar(x: x, width: 60, height: 200, radius: 22) }
// The collars, which give the shape its barbell reading at small sizes.
for x in [96.0, 868.0] { bar(x: x, width: 60, height: 108, radius: 24) }

guard let image = context.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(url.path)")
