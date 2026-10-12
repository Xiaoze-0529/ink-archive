import Foundation
import InkArchiveCore

struct Sample: Decodable {
    let id: String
    let image: String
    let reference: String
    let quad: DocumentQuad?
}

struct SampleReport: Encodable {
    let id: String
    let sourceHash: String?
    let recognizedHash: String?
    let language: String
    let engineRevision: String?
    let elapsedMilliseconds: Int?
    let lines: [OCRLine]
    let referenceCharacters: Int
    let editDistance: Int?
    let characterErrorRate: Double?
    let error: String?
}

struct ValidationReport: Encodable {
    let createdAt: Date
    let systemVersion: String
    let samples: [SampleReport]
    let aggregateCharacterErrorRate: Double?
}

@main
struct Validate {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: InkArchiveValidate <samples.json> <report.json>\nImages are relative to samples.json. Data stays on this Mac.")
            return
        }
        let manifest = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        // Avoid silently overwriting an existing test report or the sample manifest.
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw NSError(domain: "InkArchiveValidate", code: 1, userInfo: [NSLocalizedDescriptionKey: "输出文件已存在，请指定新的报告文件名。"])
        }
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: manifest))
        let ocr = OCRService()
        let processor = DocumentProcessor()
        var reports: [SampleReport] = []
        for sample in samples {
            var sourceHash: String?
            var recognizedHash: String?
            do {
                let url = manifest.deletingLastPathComponent().appendingPathComponent(sample.image)
                let original = try Data(contentsOf: url)
                sourceHash = AssetStore.contentHash(for: original)
                let data: Data
                if let quad = sample.quad { data = try await processor.correct(data: original, quad: quad).data }
                else { data = original }
                recognizedHash = AssetStore.contentHash(for: data)
                let result = try await ocr.recognize(data: data)
                let accuracy = OCRAccuracy(reference: sample.reference, recognized: result.lines.map(\.text).joined(separator: "\n"))
                reports.append(SampleReport(id: sample.id, sourceHash: sourceHash, recognizedHash: recognizedHash, language: result.language,
                                            engineRevision: result.engineRevision, elapsedMilliseconds: result.elapsedMilliseconds,
                                            lines: result.lines, referenceCharacters: accuracy.referenceCharacters,
                                            editDistance: accuracy.editDistance, characterErrorRate: accuracy.characterErrorRate, error: nil))
            } catch {
                let characters = sample.reference.filter { !$0.isWhitespace }.count
                reports.append(SampleReport(id: sample.id, sourceHash: sourceHash, recognizedHash: recognizedHash, language: "zh-Hans",
                                            engineRevision: nil, elapsedMilliseconds: nil, lines: [], referenceCharacters: characters,
                                            editDistance: nil, characterErrorRate: nil, error: error.localizedDescription))
            }
        }
        let evaluated = reports.filter { $0.error == nil && $0.referenceCharacters > 0 }
        let characters = evaluated.reduce(0) { $0 + $1.referenceCharacters }
        let edits = evaluated.reduce(0) { $0 + ($1.editDistance ?? 0) }
        let report = ValidationReport(createdAt: .now, systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                      samples: reports, aggregateCharacterErrorRate: characters == 0 ? nil : Double(edits) / Double(characters))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: output, options: .withoutOverwriting)
        print("Report saved: \(output.path) · \(samples.count) samples · \(reports.filter { $0.error != nil }.count) errors")
    }
}
