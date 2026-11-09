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

    enum Method: Equatable { case alreadyTransparent, floodFill, gradientFill, glowFill, vision }

    /// 배경 제거 후 남은 영역이 이미지의 이 비율 이하일 때만 "캐릭터를 분리했다"고 본다
    static let isolationRatio = 0.8

    /// 배경 제거 + 캐릭터 영역으로 자르기. 사용한 방법도 함께 반환.
    static func cutout(_ image: CGImage) throws -> (image: CGImage, method: Method) {
        guard let original = RGBAImage(image) else { throw Failure.unreadableImage }

        var pixels = original
        var method: Method
        if hasTransparentBorder(original) {
            method = .alreadyTransparent
        } else if floodFillBackground(&pixels), isIsolated(pixels) {
            method = .floodFill                       // 단색 배경 (흰 배경 등)
        } else {
            pixels = original
            growBackground(&pixels)
            if isIsolated(pixels) {
                method = .gradientFill                // 부드러운 그라데이션 배경
            } else if peelToOutline(&pixels, original: original), keepMainComponents(&pixels), isIsolated(pixels) {
                method = .glowFill                    // 빛번짐/반짝이 배경 (게임 도트 이미지 등)
            } else {
                guard let masked = RGBAImage(try visionForeground(image)) else { throw Failure.unreadableImage }
                pixels = masked
                method = .vision                      // 사진 등 복잡한 배경
            }
        }
        if method != .alreadyTransparent {
            keepMainComponents(&pixels)               // 반짝이·잡티 같은 떨어진 조각 제거
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

    /// 남은(불투명) 영역이 이미지 대부분을 덮고 있으면 배경 제거에 실패한 것
    static func isIsolated(_ img: RGBAImage) -> Bool {
        guard let b = alphaBounds(img) else { return false }
        return Double(b.width * b.height) <= Double(img.width * img.height) * isolationRatio
    }

    /// 그라데이션/빛번짐 배경용 "마술봉(연속)": 테두리에서 시작해, **바로 옆 픽셀과** 색 차이가 작으면
    /// 계속 배경으로 번져 나간다. 서서히 변하는 배경은 다 지워지고, 색이 뚝 끊기는 캐릭터 외곽선에서 멈춘다.
    static func growBackground(_ img: inout RGBAImage, localTolerance: Int = 26) {
        let w = img.width, h = img.height
        guard w > 0, h > 0 else { return }
        let tol2 = localTolerance * localTolerance
        let src = img.data // 원본 색으로 비교 (지우면서 색이 바뀌지 않게)
        func close(_ p: Int, _ q: Int) -> Bool {
            let i = p * 4, j = q * 4
            let dr = Int(src[i]) - Int(src[j]), dg = Int(src[i + 1]) - Int(src[j + 1]), db = Int(src[i + 2]) - Int(src[j + 2])
            return dr * dr + dg * dg + db * db <= tol2
        }

        var bg = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for (x, y) in borderPoints(img) {
            let p = y * w + x
            if !bg[p] { bg[p] = true; stack.append(p) }
        }
        while let p = stack.popLast() {
            let x = p % w, y = p / w
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let q = ny * w + nx
                if !bg[q] && close(p, q) {
                    bg[q] = true
                    stack.append(q)
                }
            }
        }
        for p in 0..<(w * h) where bg[p] {
            let i = p * 4
            img.data[i] = 0; img.data[i + 1] = 0; img.data[i + 2] = 0; img.data[i + 3] = 0
        }
    }

    /// 빛번짐 배경 제거 2단계: 이미 지운 영역에서 시작해 "진한 외곽선"이 아닌 픽셀로 계속 번져 나간다.
    /// 도트 캐릭터는 대부분 진한 외곽선으로 둘러싸여 있어서, 밝은 빛번짐/반짝이는 지우고 외곽선 안쪽은 지킨다.
    /// (CSS로 치면 "테두리 밖은 전부 투명" 처리)
    @discardableResult
    static func peelToOutline(_ img: inout RGBAImage, original: RGBAImage, outlineLuminance: Int = 110,
                              redBias: Int = 12, gapRadius: Int = 0) -> Bool {
        let w = img.width, h = img.height, n = w * h
        let src = original.data
        // 캐릭터 쪽 "벽": 진한 외곽선 또는 붉은 계열(분홍 몸통, 리본). 빛번짐은 흰/연두/노랑이라 r ≈ g.
        let wall = (0..<n).map { p -> Bool in
            let i = p * 4
            let r = Int(src[i]), g = Int(src[i + 1]), b = Int(src[i + 2])
            return (r * 299 + g * 587 + b * 114) / 1000 < outlineLuminance || r - g > redBias
        }
        // JPEG 번짐으로 외곽선에 생긴 작은 틈을 막기 위해 벽을 gapRadius만큼 두껍게 (모폴로지 팽창)
        var thick = wall
        if gapRadius > 0 {
            for p in 0..<n where wall[p] {
                let x = p % w, y = p / w
                for dy in -gapRadius...gapRadius { for dx in -gapRadius...gapRadius {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < w, ny < h { thick[ny * w + nx] = true }
                } }
            }
        }
        var removed = (0..<n).map { img.data[$0 * 4 + 3] == 0 }
        func flood(_ blocked: [Bool]) {
            var stack = (0..<n).filter { removed[$0] }
            while let p = stack.popLast() {
                let x = p % w, y = p / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h {
                    let q = ny * w + nx
                    if !removed[q] && !blocked[q] { removed[q] = true; stack.append(q) }
                }
            }
        }
        flood(thick)
        // 두껍게 만든 만큼 바깥에 남은 빛번짐 테두리를 gapRadius 픽셀만 더 벗겨낸다
        for _ in 0..<gapRadius {
            let snapshot = removed
            for p in 0..<n where !snapshot[p] && !wall[p] {
                let x = p % w, y = p / w
                if (x > 0 && snapshot[p - 1]) || (x < w - 1 && snapshot[p + 1])
                    || (y > 0 && snapshot[p - w]) || (y < h - 1 && snapshot[p + w]) {
                    removed[p] = true
                }
            }
        }
        for p in 0..<n where removed[p] {
            let i = p * 4
            img.data[i] = 0; img.data[i + 1] = 0; img.data[i + 2] = 0; img.data[i + 3] = 0
        }
        return true
    }

    /// 서로 붙어 있는 불투명 픽셀 덩어리 중 큰 것만 남긴다.
    /// 가장 큰 덩어리의 `minFraction` 미만 크기 덩어리(반짝이, JPEG 잡티)는 지운다.
    @discardableResult
    static func keepMainComponents(_ img: inout RGBAImage, minFraction: Double = 0.15) -> Bool {
        let w = img.width, h = img.height
        var label = [Int](repeating: -1, count: w * h)
        var sizes: [Int] = []
        for start in 0..<(w * h) where label[start] < 0 && img.data[start * 4 + 3] > 16 {
            let id = sizes.count
            var count = 0
            var stack = [start]
            label[start] = id
            while let p = stack.popLast() {
                count += 1
                let x = p % w, y = p / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h {
                    let q = ny * w + nx
                    if label[q] < 0 && img.data[q * 4 + 3] > 16 {
                        label[q] = id
                        stack.append(q)
                    }
                }
            }
            sizes.append(count)
        }
        guard let largest = sizes.max() else { return false }
        let minSize = Int(Double(largest) * minFraction)
        for p in 0..<(w * h) where label[p] >= 0 && sizes[label[p]] < minSize {
            let i = p * 4
            img.data[i] = 0; img.data[i + 1] = 0; img.data[i + 2] = 0; img.data[i + 3] = 0
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
