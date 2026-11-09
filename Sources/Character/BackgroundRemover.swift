import CoreGraphics
import CoreImage
import Foundation
import Vision

/// RGBA 8비트 픽셀 버퍼 (premultiplied). 픽셀 단위 처리용.
/// JS의 `ImageData`(canvas.getImageData)와 같은 개념.
struct RGBAImage: Equatable {
    var width: Int
    var height: Int
    var data: [UInt8]   // [r, g, b, a, r, g, b, a, ...] 좌상단부터 행 단위

    init(width: Int, height: Int, data: [UInt8]) {
        self.width = width
        self.height = height
        self.data = data
    }

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { return nil }
    }

    func makeImage() -> CGImage? {
        var copy = data
        return copy.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    @inline(__always) func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
    func alpha(_ x: Int, _ y: Int) -> UInt8 { data[offset(x, y) + 3] }
}

/// 캐릭터 그림에서 배경을 지우고 캐릭터 부분만 잘라낸다.
enum BackgroundRemover {
    enum Failure: Error, CustomStringConvertible {
        case unreadableImage
        case noForeground
        case visionFailed(String)

        var description: String {
            switch self {
            case .unreadableImage: return "이미지를 읽을 수 없음"
            case .noForeground: return "캐릭터 영역을 찾지 못함 (배경만 있는 이미지?)"
            case .visionFailed(let m): return "자동 배경 제거 실패: \(m)"
            }
        }
    }

    enum Method: Equatable { case alreadyTransparent, floodFill, vision }

    /// 배경 제거 + 캐릭터 영역으로 자르기. 사용한 방법도 함께 반환.
    static func cutout(_ image: CGImage) throws -> (image: CGImage, method: Method) {
        guard var pixels = RGBAImage(image) else { throw Failure.unreadableImage }

        let method: Method
        if hasTransparentBorder(pixels) {
            method = .alreadyTransparent
        } else if floodFillBackground(&pixels) {
            method = .floodFill
        } else {
            guard let masked = RGBAImage(try visionForeground(image)) else { throw Failure.unreadableImage }
            pixels = masked
            method = .vision
        }

        guard let bounds = alphaBounds(pixels), let full = pixels.makeImage(),
              let cropped = full.cropping(to: bounds) else { throw Failure.noForeground }
        return (cropped, method)
    }

    /// 테두리에 투명 픽셀이 있으면 이미 배경이 지워진 PNG로 본다
    static func hasTransparentBorder(_ img: RGBAImage) -> Bool {
        borderPoints(img).contains { img.alpha($0.0, $0.1) < 250 }
    }

    /// 테두리 색이 거의 한 가지(단색 배경)면 테두리에서부터 비슷한 색을 지운다(페인트 통 도구와 같음).
    /// 캐릭터의 외곽선이 벽 역할을 해서 안쪽의 흰 옷/얼굴은 지워지지 않는다.
    /// 테두리가 단색이 아니면 아무것도 안 하고 false.
    @discardableResult
    static func floodFillBackground(_ img: inout RGBAImage, tolerance: Int = 48) -> Bool {
        let border = borderPoints(img)
        guard !border.isEmpty else { return false }

        // 테두리 색의 중앙값 = 배경색
        func channel(_ c: Int) -> Int {
            let values = border.map { Int(img.data[img.offset($0.0, $0.1) + c]) }.sorted()
            return values[values.count / 2]
        }
        let bg = (channel(0), channel(1), channel(2))
        let tol2 = tolerance * tolerance
        func isBackground(_ i: Int) -> Bool {
            let dr = Int(img.data[i]) - bg.0, dg = Int(img.data[i + 1]) - bg.1, db = Int(img.data[i + 2]) - bg.2
            return dr * dr + dg * dg + db * db <= tol2
        }

        let matching = border.filter { isBackground(img.offset($0.0, $0.1)) }.count
        guard Double(matching) / Double(border.count) >= 0.9 else { return false }

        // BFS (너비 우선 탐색) — 재귀 대신 배열 스택으로 큰 이미지도 안전하게
        var visited = [Bool](repeating: false, count: img.width * img.height)
        var stack: [Int] = []
        for (x, y) in border where isBackground(img.offset(x, y)) {
            let p = y * img.width + x
            if !visited[p] { visited[p] = true; stack.append(p) }
        }
        while let p = stack.popLast() {
            let i = p * 4
            img.data[i] = 0; img.data[i + 1] = 0; img.data[i + 2] = 0; img.data[i + 3] = 0
            let x = p % img.width, y = p / img.width
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && ny >= 0 && nx < img.width && ny < img.height {
                let q = ny * img.width + nx
                if !visited[q] && isBackground(q * 4) {
                    visited[q] = true
                    stack.append(q)
                }
            }
        }
        return true
    }

    /// 불투명 픽셀(alpha > 16)을 모두 감싸는 사각형 (CGImage 좌표 = 좌상단 원점)
    static func alphaBounds(_ img: RGBAImage, threshold: UInt8 = 16) -> CGRect? {
        var minX = img.width, minY = img.height, maxX = -1, maxY = -1
        for y in 0..<img.height {
            for x in 0..<img.width where img.alpha(x, y) > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func borderPoints(_ img: RGBAImage) -> [(Int, Int)] {
        guard img.width > 0, img.height > 0 else { return [] }
        var pts: [(Int, Int)] = []
        for x in 0..<img.width { pts.append((x, 0)); pts.append((x, img.height - 1)) }
        for y in 0..<img.height { pts.append((0, y)); pts.append((img.width - 1, y)) }
        return pts
    }

    /// macOS 14+ Vision의 "피사체 들어올리기"(사진 앱의 배경 제거와 같은 기능)
    private static func visionForeground(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw Failure.noForeground
            }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                        croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { throw Failure.unreadableImage }
            return cg
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.visionFailed("\(error.localizedDescription)")
        }
    }
}
