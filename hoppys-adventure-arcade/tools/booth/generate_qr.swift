import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

let defaultURL = "https://coderabbit.ai/?utm_source=booth&utm_medium=qr&utm_campaign=hoppys_adventure_arcade"
let output = CommandLine.arguments.count > 1
	? CommandLine.arguments[1]
	: "hoppys-adventure-arcade/Assets/booth/booth_qr.png"
let value = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : defaultURL

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(value.utf8)
filter.correctionLevel = "H"

guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
	fatalError("Could not generate QR code")
}
let bitmap = NSBitmapImageRep(ciImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
	fatalError("Could not encode QR code as PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output) for \(value)")
