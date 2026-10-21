import CoreGraphics
import Foundation

/// A deterministic squarified treemap layout. Values are laid out in descending order;
/// the returned rects line up with the input order.
public enum TreemapLayout {
    public static func layout(values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        guard !values.isEmpty else { return result }

        let positiveIndices = values.indices.filter { values[$0] > 0 }
        let total = positiveIndices.reduce(0.0) { $0 + values[$1] }
        guard total > 0, rect.width > 1, rect.height > 1 else { return result }

        let area = Double(rect.width * rect.height)
        let scale = area / total
        let order = positiveIndices.sorted {
            if values[$0] == values[$1] { return $0 < $1 }
            return values[$0] > values[$1]
        }

        var remaining = rect
        var startingIndex = 0

        while startingIndex < order.count {
            let shortSide = Double(min(remaining.width, remaining.height))
            guard shortSide > 0 else { break }

            var row: [Int] = [order[startingIndex]]
            var rowSum = values[order[startingIndex]] * scale
            var rowMin = values[order[startingIndex]]
            var rowMax = rowMin
            var worst = worstRatio(sum: rowSum, min: rowMin, max: rowMax, side: shortSide)

            var cursor = startingIndex + 1
            while cursor < order.count {
                let candidate = values[order[cursor]]
                let candidateArea = candidate * scale
                let candidateSum = rowSum + candidateArea
                let candidateMin = min(rowMin, candidate)
                let candidateMax = max(rowMax, candidate)
                let candidateWorst = worstRatio(
                    sum: candidateSum,
                    min: candidateMin,
                    max: candidateMax,
                    side: shortSide
                )
                if candidateWorst > worst { break }
                row.append(order[cursor])
                rowSum = candidateSum
                rowMin = candidateMin
                rowMax = candidateMax
                worst = candidateWorst
                cursor += 1
            }

            // Lay the row along the shorter side of the remaining rectangle.
            if remaining.width <= remaining.height {
                let rowWidth = CGFloat(rowSum / Double(remaining.height))
                var y = remaining.minY
                for index in row {
                    let itemArea = values[index] * scale
                    let height = CGFloat(itemArea / rowSum) * remaining.height
                    result[index] = CGRect(x: remaining.minX, y: y, width: rowWidth, height: height)
                    y += height
                }
                remaining = CGRect(
                    x: remaining.minX + rowWidth,
                    y: remaining.minY,
                    width: max(0, remaining.width - rowWidth),
                    height: remaining.height
                )
            } else {
                let rowHeight = CGFloat(rowSum / Double(remaining.width))
                var x = remaining.minX
                for index in row {
                    let itemArea = values[index] * scale
                    let width = CGFloat(itemArea / rowSum) * remaining.width
                    result[index] = CGRect(x: x, y: remaining.minY, width: width, height: rowHeight)
                    x += width
                }
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + rowHeight,
                    width: remaining.width,
                    height: max(0, remaining.height - rowHeight)
                )
            }

            startingIndex += row.count
        }

        // Clamp to bounds and normalise any floating-point drift at the edges.
        let maxX = rect.maxX
        let maxY = rect.maxY
        for index in result.indices where result[index] != .zero {
            var tile = result[index]
            tile.origin.x = min(max(rect.minX, tile.minX), maxX)
            tile.origin.y = min(max(rect.minY, tile.minY), maxY)
            tile.size.width = max(0, min(tile.width, maxX - tile.minX))
            tile.size.height = max(0, min(tile.height, maxY - tile.minY))
            result[index] = tile
        }

        return result
    }

    private static func worstRatio(sum: Double, min: Double, max: Double, side: Double) -> Double {
        guard sum > 0, min > 0, side > 0 else { return .greatestFiniteMagnitude }
        let s2 = sum * sum
        let side2 = side * side
        return Swift.max((side2 * max) / s2, s2 / (side2 * min))
    }
}

/// Convenience wrapper for views: a laid-out tile with its source value.
public struct TreemapTile: Identifiable, Sendable {
    public let id: Int
    public let rect: CGRect
    public let value: Double

    public init(id: Int, rect: CGRect, value: Double) {
        self.id = id
        self.rect = rect
        self.value = value
    }
}
