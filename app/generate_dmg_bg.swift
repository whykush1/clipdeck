import Cocoa
import CoreGraphics
import CoreText

let width: CGFloat = 600
let height: CGFloat = 400
let rect = CGRect(x: 0, y: 0, width: width, height: height)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not create context")
}

// 1. Fill background with a very soft warm white/light color (#F5F5F7)
context.setFillColor(red: 245/255.0, green: 245/255.0, blue: 247/255.0, alpha: 1.0)
context.fill(rect)

// 2. Draw gradient text
let text = "Drag ClipDeck to Applications"
let font = NSFont.systemFont(ofSize: 28, weight: .bold)

// We want to draw the text as a mask, then fill the gradient over the mask
let textAttributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let attributedText = NSAttributedString(string: text, attributes: textAttributes)
let textSize = attributedText.size()
let textRect = CGRect(x: (width - textSize.width) / 2, y: height - 120, width: textSize.width, height: textSize.height)

context.saveGState()

// Create an image mask from the text
let textContext = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let graphicsContext = NSGraphicsContext(cgContext: textContext, flipped: false)
NSGraphicsContext.current = graphicsContext
attributedText.draw(at: textRect.origin)
guard let textImage = textContext.makeImage() else { fatalError() }

// Clip to text mask
context.clip(to: rect, mask: textImage)

// Draw gradient
let colors = [
    NSColor(calibratedRed: 223/255.0, green: 61/255.0, blue: 64/255.0, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 248/255.0, green: 148/255.0, blue: 61/255.0, alpha: 1.0).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
let startPoint = CGPoint(x: textRect.minX, y: 0)
let endPoint = CGPoint(x: textRect.maxX, y: 0)
context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])

context.restoreGState()

// 3. Draw an arrow
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 230, y: 180))
arrowPath.line(to: NSPoint(x: 350, y: 180))
arrowPath.lineWidth = 4
arrowPath.lineCapStyle = .round
NSColor(calibratedWhite: 0.3, alpha: 1.0).setStroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 330, y: 200))
arrowHead.line(to: NSPoint(x: 350, y: 180))
arrowHead.line(to: NSPoint(x: 330, y: 160))
arrowHead.lineWidth = 4
arrowHead.lineCapStyle = .round

let arrowContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = arrowContext
arrowPath.stroke()
arrowHead.stroke()

// Save to file
guard let cgImage = context.makeImage() else { fatalError() }
let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
guard let tiffData = nsImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else { fatalError() }

let url = URL(fileURLWithPath: "background.png")
try! pngData.write(to: url)
print("Saved to background.png")
