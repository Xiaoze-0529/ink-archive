import Foundation
import CoreImage
import Vision

public struct OCRLine: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let box: NormalizedRect
    public let confidence: Float

    public init(id: UUID = UUID(), text: String, box: NormalizedRect, confidence: Float) {
        self.id = id
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

public struct OCRResult: Sendable {
    public let lines: [OCRLine]
    public let language: String
    public let engineRevision: String
    public let elapsedMilliseconds: Int

    public init(lines: [OCRLine], language: String = "zh-Hans", engineRevision: String, elapsedMilliseconds: Int) {
        self.lines = lines
        self.language = language
        self.engineRevision = engineRevision
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public enum OCRState: String, Codable, Sendable { case recognized, noText, unsupported, failed }

public struct OCRRunRecord: Codable, Sendable, Equatable {
    public let state: OCRState
    public let sourceAssetID: UUID
    public let engineRevision: String?
    public let elapsedMilliseconds: Int?
    public let message: String?
    public let createdAt: Date

    public init(state: OCRState, sourceAssetID: UUID, engineRevision: String? = nil,
                elapsedMilliseconds: Int? = nil, message: String? = nil, createdAt: Date = .now) {
        self.state = state
        self.sourceAssetID = sourceAssetID
        self.engineRevision = engineRevision
        self.elapsedMilliseconds = elapsedMilliseconds
        self.message = message
        self.createdAt = createdAt
    }
}

public enum OCRServiceError: LocalizedError {
    case simplifiedChineseUnavailable
    public var errorDescription: String? { "当前系统不支持简体中文识别，请使用人工标签。" }
}

public actor OCRService {
    public init() {}

    public func recognize(data: Data) throws -> OCRResult {
        let start = Date()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard try request.supportedRecognitionLanguages().contains("zh-Hans") else {
            throw OCRServiceError.simplifiedChineseUnavailable
        }
        request.recognitionLanguages = ["zh-Hans"]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw DocumentProcessingError.invalidImage
        }
        let upright = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        try VNImageRequestHandler(ciImage: upright, orientation: .up).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let text = observation.topCandidates(1).first else { return nil }
            let rect = observation.boundingBox
            return OCRLine(text: text.string, box: NormalizedRect(
                x: Double(rect.minX), y: 1 - Double(rect.maxY),
                width: Double(rect.width), height: Double(rect.height)
            ), confidence: text.confidence)
        }.sorted {
            let leftRow = Int($0.box.y * 100), rightRow = Int($1.box.y * 100)
            if leftRow != rightRow { return leftRow < rightRow }
            return $0.box.x < $1.box.x
        }
        return OCRResult(lines: lines, engineRevision: "Vision-\(request.revision)",
                         elapsedMilliseconds: Int(Date().timeIntervalSince(start) * 1000))
    }
}

/// Validation helper for a real sample and its manually transcribed reference.
/// CER removes whitespace only; punctuation and missing/extra characters count as edits.
public struct OCRAccuracy: Sendable, Equatable {
    public let referenceCharacters: Int
    public let editDistance: Int
    public var characterErrorRate: Double? {
        referenceCharacters == 0 ? nil : Double(editDistance) / Double(referenceCharacters)
    }

    public init(reference: String, recognized: String) {
        let expected = Array(reference.filter { !$0.isWhitespace })
        let actual = Array(recognized.filter { !$0.isWhitespace })
        referenceCharacters = expected.count
        var previous = Array(0...actual.count)
        for (i, character) in expected.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: actual.count)
            for (j, observed) in actual.enumerated() {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (character == observed ? 0 : 1))
            }
            previous = row
        }
        editDistance = previous[actual.count]
    }
}
