import Foundation

/// All persisted image coordinates use an upright image, top-left origin, and 0...1 units.
public struct DocumentQuad: Codable, Sendable, Equatable {
    public var topLeft: NormalizedPoint
    public var topRight: NormalizedPoint
    public var bottomRight: NormalizedPoint
    public var bottomLeft: NormalizedPoint

    public init(topLeft: NormalizedPoint, topRight: NormalizedPoint, bottomRight: NormalizedPoint, bottomLeft: NormalizedPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public static let fullImage = DocumentQuad(
        topLeft: .init(x: 0, y: 0), topRight: .init(x: 1, y: 0),
        bottomRight: .init(x: 1, y: 1), bottomLeft: .init(x: 0, y: 1)
    )

    public var points: [NormalizedPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    public var area: Double {
        let points = points
        return abs((0..<4).reduce(0.0) { sum, i in
            let next = points[(i + 1) % 4]
            return sum + points[i].x * next.y - next.x * points[i].y
        }) / 2
    }

    public var isValid: Bool {
        let points = points
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              area >= 0.02 else { return false }
        // Strict clockwise winding in top-left coordinates rejects crossed, reversed and collinear corners.
        return (0..<4).allSatisfy { i in
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            return cross > 0.00001 && hypot(b.x - a.x, b.y - a.y) >= 0.02
        }
    }

    public mutating func setCorner(_ index: Int, to point: NormalizedPoint) {
        switch index {
        case 0: topLeft = point
        case 1: topRight = point
        case 2: bottomRight = point
        case 3: bottomLeft = point
        default: break
        }
    }
}

public struct CorrectionRecipe: Codable, Sendable, Equatable {
    public let quad: DocumentQuad
    public let processor: String
    public let createdAt: Date

    public init(quad: DocumentQuad, createdAt: Date = .now) {
        self.quad = quad
        self.processor = "CIPerspectiveCorrection-v1"
        self.createdAt = createdAt
    }
}

public struct CorrectedDocument: Sendable {
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let recipe: CorrectionRecipe

    public init(data: Data, pixelWidth: Int, pixelHeight: Int, recipe: CorrectionRecipe) {
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.recipe = recipe
    }
}
