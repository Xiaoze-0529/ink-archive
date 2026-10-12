import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

public struct DocumentPreparation: Sendable {
    public let previewData: Data
    public let detectedQuad: DocumentQuad?
}

public enum DocumentProcessingError: LocalizedError {
    case invalidImage
    case invalidCorners
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: "无法解码图片。"
        case .invalidCorners: "四角不能交叉或重合，请按页面边缘重新调整。"
        case .renderFailed: "校正图生成失败，请重试或先保存原件。"
        }
    }
}

/// Vision and Core Image work run outside the main UI actor.
public actor DocumentProcessor {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func prepare(data: Data) throws -> DocumentPreparation {
        let image = try uprightImage(data)
        let preview = bounded(image, maxDimension: 1800)
        // Detection failure does not prevent manual cropping or saving the original.
        let quad = try? detect(in: preview)
        return DocumentPreparation(previewData: try encodeJPEG(preview), detectedQuad: quad)
    }

    public func correct(data: Data, quad: DocumentQuad) throws -> CorrectedDocument {
        guard quad.isValid else { throw DocumentProcessingError.invalidCorners }
        let image = try uprightImage(data)
        let extent = image.extent
        func vector(_ point: NormalizedPoint) -> CGPoint {
            CGPoint(x: point.x * extent.width, y: (1 - point.y) * extent.height)
        }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.crop = true
        filter.topLeft = vector(quad.topLeft)
        filter.topRight = vector(quad.topRight)
        filter.bottomRight = vector(quad.bottomRight)
        filter.bottomLeft = vector(quad.bottomLeft)
        guard let output = filter.outputImage, !output.extent.isEmpty,
              output.extent.width.isFinite, output.extent.height.isFinite else { throw DocumentProcessingError.renderFailed }
        let shifted = output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
        let boundedOutput = bounded(shifted, maxDimension: 6000)
        return CorrectedDocument(
            data: try encodeJPEG(boundedOutput), pixelWidth: Int(boundedOutput.extent.width.rounded()),
            pixelHeight: Int(boundedOutput.extent.height.rounded()), recipe: CorrectionRecipe(quad: quad)
        )
    }

    private func uprightImage(_ data: Data) throws -> CIImage {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              !image.extent.isEmpty, image.extent.width.isFinite, image.extent.height.isFinite else {
            throw DocumentProcessingError.invalidImage
        }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private func bounded(_ image: CIImage, maxDimension: Double) -> CIImage {
        let scale = min(1, maxDimension / max(image.extent.width, image.extent.height))
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func detect(in image: CIImage) throws -> DocumentQuad? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 6
        request.minimumConfidence = 0.5
        request.minimumSize = 0.2
        request.minimumAspectRatio = 0.15
        request.maximumAspectRatio = 1
        request.quadratureTolerance = 35
        try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
        func point(_ p: CGPoint) -> NormalizedPoint { .init(x: Double(p.x), y: 1 - Double(p.y)) }
        // Prefer the largest valid document rather than a small ticket inside the page.
        return (request.results ?? []).compactMap { observation -> DocumentQuad? in
            let quad = DocumentQuad(
                topLeft: point(observation.topLeft), topRight: point(observation.topRight),
                bottomRight: point(observation.bottomRight), bottomLeft: point(observation.bottomLeft)
            )
            return quad.isValid ? quad : nil
        }.max { $0.area < $1.area }
    }

    private func encodeJPEG(_ image: CIImage) throws -> Data {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { throw DocumentProcessingError.renderFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw DocumentProcessingError.renderFailed
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DocumentProcessingError.renderFailed }
        return data as Data
    }
}
