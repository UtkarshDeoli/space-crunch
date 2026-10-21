import AppKit
import SpaceCrunchCore
import SwiftUI

struct BrowseView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let node = model.browseNode {
                VStack(alignment: .leading, spacing: 16) {
                    breadcrumb(node)
                    summaryCard(node)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(
                            title: "Storage map",
                            subtitle: node.children.isEmpty
                                ? "This folder has no subfolders to map"
                                : "Click a block to open that folder"
                        )

                        StorageTreemap(
                            entries: TreemapEntry.entries(for: node, limit: 36),
                            height: 330
                        ) { child in
                            withAnimation(.snappy(duration: 0.25)) {
                                model.drill(into: child)
                            }
                        }
                    }
                    .card()

                    contentsCard(node)

                    if !node.children.isEmpty {
                        Text("Showing the largest folders first. Sizes include everything inside each folder.")
                            .font(AppFont.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                    }
                }
                .contentColumn()
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Breadcrumb

    private func breadcrumb(_ node: DirNode) -> some View {
        let chain = model.browsePath

        return HStack(spacing: 4) {
            if chain.isEmpty {
                Text("Macintosh HD")
                    .font(AppFont.callout.weight(.semibold))
            } else {
                ForEach(Array(chain.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            model.browsePath = Array(chain.prefix(index + 1))
                        }
                    } label: {
                        Text(item.displayName)
                            .font(AppFont.callout.weight(index == chain.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == chain.count - 1 ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == chain.count - 1)
                }
            }

            Spacer(minLength: 8)

            Button {
                model.revealInFinder(URL(fileURLWithPath: node.path))
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
                    .font(AppFont.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .frame(height: 20)
    }

    // MARK: - Summary

    private func summaryCard(_ node: DirNode) -> some View {
        let childCount = node.children.count

        return HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(node.displayCategory.color.opacity(0.14))
                Image(systemName: node.path == "/" ? "internaldrive.fill" : "folder.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(node.displayCategory.color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(AppFont.title)
                    .lineLimit(1)
                Text(SizeText.abbreviatedPath(node.path, home: model.snapshot?.homeURL.path ?? ""))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(SizeText.string(node.size))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(childCount.formatted()) folder\(childCount == 1 ? "" : "s") · \(node.fileCount.formatted()) files")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .card(padding: 16)
    }

    // MARK: - Contents

    private func contentsCard(_ node: DirNode) -> some View {
        let children = node.sortedChildren
        let visible = Array(children.prefix(300))
        let parentSize = max(1, node.size)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(
                    title: "Folders",
                    subtitle: children.isEmpty ? "No subfolders" : "\(children.count.formatted()) folders"
                )
                Spacer()
                if children.count > 300 {
                    Text("Largest 300 shown")
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if children.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nothing nested down here")
                            .font(AppFont.callout.weight(.medium))
                        Text("This folder contains files only.")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(visible, id: \.path) { child in
                        BrowseFolderRow(
                            child: child,
                            parentSize: parentSize,
                            tint: child.displayCategory.color
                        ) {
                            withAnimation(.snappy(duration: 0.25)) {
                                model.drill(into: child)
                            }
                        }
                    }
                }
            }
        }
        .card()
    }
}

struct BrowseFolderRow: View {
    let child: DirNode
    let parentSize: Int64
    let tint: Color
    let action: () -> Void

    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(child.displayName)
                            .font(AppFont.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(SizeText.string(child.size))
                            .font(AppFont.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(SizeText.percent(Double(child.size) / Double(parentSize)))
                            .font(AppFont.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(tint.opacity(0.11))
                            Capsule()
                                .fill(tint.opacity(0.75))
                                .frame(
                                    width: max(3, geo.size.width * CGFloat(Double(child.size) / Double(parentSize)))
                                )
                        }
                    }
                    .frame(height: 3)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.045 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in Finder") {
                NSWorkspace.shared.open(child.path.isEmpty ? URL(fileURLWithPath: "/") : URL(fileURLWithPath: child.path))
            }
            Button("Reveal in Finder") {
                model.revealInFinder(URL(fileURLWithPath: child.path))
            }
        }
    }
}
