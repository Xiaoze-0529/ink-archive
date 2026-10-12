import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import InkArchiveCore

/// Generated fixtures exercise the real Apple APIs, not real-handwriting accuracy.
final class ImageProcessingTests: XCTestCase {
    func testAutomaticDocumentEdgesUseTopLeftCoordinates() async throws {
        let context = try canvas(width: 1000, height: 800)
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 150, width: 800, height: 500))
        let processor = DocumentProcessor()
        let prepared = try await processor.prepare(data: encode(context))
        let quad = try XCTUnwrap(prepared.detectedQuad)
        XCTAssertTrue(quad.isValid)
        XCTAssertEqual(quad.topLeft.x, 0.1, accuracy: 0.04)
        XCTAssertEqual(quad.topLeft.y, 0.1875, accuracy: 0.04)
        XCTAssertEqual(quad.bottomRight.x, 0.9, accuracy: 0.04)
        XCTAssertEqual(quad.bottomRight.y, 0.8125, accuracy: 0.04)
    }

    func testCorrectionHonorsEXIFOrientationAndProducesReadableJPEG() async throws {
        let context = try canvas(width: 320, height: 200)
        let data = try encode(context, orientation: 6)
        let processor = DocumentProcessor()
        let result = try await processor.correct(data: data, quad: .fullImage)
        XCTAssertLessThanOrEqual(abs(result.pixelWidth - 200), 2)
        XCTAssertLessThanOrEqual(abs(result.pixelHeight - 320), 2)
        XCTAssertNotNil(CGImageSourceCreateWithData(result.data as CFData, nil))
        XCTAssertEqual(result.recipe.quad, .fullImage)
    }

    func testChineseVisionOCRReturnsTextAndValidNormalizedBoxes() async throws {
        let context = try canvas(width: 1200, height: 400)
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 64, nil)
        let attributed = NSAttributedString(string: "今天记录生活", attributes: [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 100, y: 180)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        let service = OCRService()
        let result: OCRResult
        do { result = try await service.recognize(data: encode(context)) }
        catch OCRServiceError.simplifiedChineseUnavailable { throw XCTSkip("系统不提供 zh-Hans；人工标签测试单独覆盖。") }
        XCTAssertEqual(result.language, "zh-Hans")
        XCTAssertTrue(result.lines.map(\.text).joined().contains("记录生活"))
        for line in result.lines {
            XCTAssertTrue((0...1).contains(line.box.x))
            XCTAssertTrue((0...1).contains(line.box.y))
            XCTAssertLessThanOrEqual(line.box.x + line.box.width, 1.001)
            XCTAssertLessThanOrEqual(line.box.y + line.box.height, 1.001)
            XCTAssertGreaterThan(line.box.width, 0)
            XCTAssertGreaterThan(line.box.height, 0)
        }
    }

    private func canvas(width: Int, height: Int) throws -> CGContext {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private func encode(_ context: CGContext, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1.0
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
