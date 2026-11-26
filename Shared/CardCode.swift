import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum CardCode {
    static let supportURL = URL(string: "https://hgsldswk-alt.github.io/waterout-support/")!
    static let waterURL = URL(string: "https://support.apple.com/en-us/108039")!
    static let liquidURL = URL(string: "https://support.apple.com/en-us/102643")!

    static func storeURL(id: String?) -> URL? {
        guard let id, !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    static func image(for url: URL, scale: Int = 8) -> CGImage? {
        guard scale > 0 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let extent = code.extent.insetBy(dx: -4, dy: -4)
        let padded = code.composited(over: CIImage(color: .white).cropped(to: extent))
        let enlarged = padded.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return CIContext().createCGImage(enlarged, from: enlarged.extent)
    }
}
