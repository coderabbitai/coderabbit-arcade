import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

let defaultURL = "https://coderabbit.link/ato26-ad?qr=1"
let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectDirectory = scriptDirectory.deletingLastPathComponent().deletingLastPathComponent()
let defaultOutput = projectDirectory.appendingPathComponent("Assets/booth/booth_qr.png").path
let logoPath = projectDirectory.appendingPathComponent("Assets/booth/booth_qr_logo.png").path
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOutput
let value = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : defaultURL

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(value.utf8)
filter.correctionLevel = "H"

guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
	fatalError("Could not generate QR code")
}
let qr = NSBitmapImageRep(ciImage: image)
guard let logo = NSImage(contentsOfFile: logoPath),
		let logoTiff = logo.tiffRepresentation,
		let logoBitmap = NSBitmapImageRep(data: logoTiff) else {
	fatalError("Could not load QR or CodeRabbit logo image")
}

let size = NSSize(width: qr.pixelsWide, height: qr.pixelsHigh)
let composite = NSImage(size: size)
composite.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()
qr.draw(in: NSRect(origin: .zero, size: size))
let logoSize = size.width * 0.223
let logoRect = NSRect(x: (size.width - logoSize) / 2, y: (size.height - logoSize) / 2,
		width: logoSize, height: logoSize)
logoBitmap.draw(in: logoRect)
composite.unlockFocus()

guard let tiff = composite.tiffRepresentation,
		let bitmap = NSBitmapImageRep(data: tiff),
		let png = bitmap.representation(using: .png, properties: [:]) else {
	fatalError("Could not encode QR code as PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output) for \(value)")
