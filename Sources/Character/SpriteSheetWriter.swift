import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG 저장 / 프레임들을 가로 한 줄 스프라이트 시트로 이어 붙여 저장
enum SpriteSheetWriter {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func writeSheet(_ frames: [CGImage], frameWidth fw: Int, frameHeight fh: Int, to url: URL) throws {
        guard let ctx = CGContext(data: nil, width: fw * max(frames.count, 1), height: fh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (i, frame) in frames.enumerated() {
            ctx.draw(frame, in: CGRect(x: i * fw, y: 0, width: fw, height: fh))
        }
        guard let sheet = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        try writePNG(sheet, to: url)
    }
}
