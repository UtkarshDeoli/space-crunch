import SpaceCrunchCore
import SwiftUI

struct TreemapEntry: Identifiable {
    let id: String
    let name: String
    let size: Int64
    let category: SpaceCategory
    let node: DirNode?

    init(node: DirNode) {
        self.id = node.path
        self.name = node.displayName
        self.size = node.size
        self.category = node.displayCategory
        self.node = node
    }

    init(id: String, name: String, size: Int64, category: SpaceCategory, node: DirNode? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.category = category
        self.node = node
    }

    static func entries(for node: DirNode, limit: Int = 28) -> [TreemapEntry] {
        let children = node.sortedChildren.filter { $0.size > 0 }
        guard !children.isEmpty else { return [] }

        let visible = children.prefix(limit)
        var entries = visible.map(TreemapEntry.init(node:))
        let overflow = children.dropFirst(limit)
        if !overflow.isEmpty {
            let size = overflow.reduce(Int64(0)) { $0 + $1.size }
            // Colour the leftovers by whatever fills most of them, so the tile doesn't
            // stand out as a generic grey block in an otherwise categorical map.
            var totals = [Int64](repeating: 0, count: SpaceCategory.inSlotOrder.count)
            for child in overflow {
                for slot in totals.indices {
                    totals[slot] += child.subtreeTotals[slot]
                }
            }
            let category = SpaceCategory.dominant(in: totals) ?? .other
            entries.append(
                TreemapEntry(
                    id: "aggregate:\(node.path)",
                    name: "Other",
                    size: size,
                    category: category
                )
            )
        }
        return entries
    }
}

struct StorageTreemap: View {
    let entries: [TreemapEntry]
    var height: CGFloat = 220
    var onSelect: ((DirNode) -> Void)?

    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { geo in
            let values = entries.map { Double($0.size) }
            let rects = TreemapLayout.layout(
                values: values,
                in: CGRect(origin: .zero, size: geo.size)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.12))

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let rect = rects[index].insetBy(dx: 1.5, dy: 1.5)
                    if rect.width > 2, rect.height > 2 {
                        tile(entry: entry, rect: rect, index: index)
                    }
                }

                if entries.isEmpty {
                    Text("No folders to map")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func tile(entry: TreemapEntry, rect: CGRect, index: Int) -> some View {
        let isHovered = hoveredID == entry.id
        let canOpen = entry.node != nil

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(baseColor(for: entry, index: index))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isHovered ? Color.white.opacity(0.75) : Color.white.opacity(0.1),
                        lineWidth: isHovered ? 1.5 : 0.5
                    )
            )
            .overlay(alignment: .topLeading) {
                if rect.width > 58, rect.height > 24 {
                    tileLabel(entry: entry, rect: rect, showsSize: rect.height > 38)
                }
            }
            .overlay {
                // A tile too narrow for a horizontal label still gets one, turned
                // on its side so it runs up the tile. Without this, a row of
                // small folders comes out as a strip of anonymous colour.
                if rect.width >= 38, rect.width <= 58, rect.height >= 80 {
                    tileLabel(entry: entry, rect: rect, showsSize: true)
                        .frame(width: rect.height, height: rect.width, alignment: .topLeading)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredID = entry.id
                } else if hoveredID == entry.id {
                    hoveredID = nil
                }
            }
            .onTapGesture {
                if let node = entry.node { onSelect?(node) }
            }
            .help(
                entry.node == nil
                    ? "\(entry.name) · \(SizeText.string(entry.size))"
                    : "\(entry.name) · \(SizeText.string(entry.size)) — click to explore"
            )
            .opacity(isHovered ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .accessibilityLabel("\(entry.name), \(SizeText.string(entry.size))")
            .accessibilityHint(canOpen ? "Opens this folder" : "")
    }

    /// The fill for a tile. Neighbouring tiles of the same category get slightly
    /// different shades so you can still tell them apart.
    private func baseColor(for entry: TreemapEntry, index: Int) -> Color {
        let base = entry.category.color
        let variations: [Double] = [0.92, 1.0, 0.85, 0.96, 0.88]
        return base.mix(with: .white, by: (1 - variations[index % variations.count]) * 0.35)
    }

    /// The name-and-size badge that sits on a tile.
    private func tileLabel(entry: TreemapEntry, rect: CGRect, showsSize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.name)
                .font(.system(size: rect.width > 110 ? 11 : 10, weight: .semibold))
                .lineLimit(1)
            if showsSize {
                Text(SizeText.string(entry.size))
                    .font(.system(size: 9.5, weight: .medium))
                    .opacity(0.82)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // A frosted badge. It refracts the tile underneath, so the
        // chip picks up the category's hue on its own instead of
        // stamping an opaque box on the data.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .padding(5)
        .allowsHitTesting(false)
    }
}
