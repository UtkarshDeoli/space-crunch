import Charts
import SpaceCrunchCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 18) {
                    header(snapshot)
                    hero(snapshot)
                    capacityCard(snapshot)

                    // Side by side when there's room for the donut and its legend;
                    // otherwise stack so neither card gets squeezed.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            categoryCard(snapshot)
                                .frame(maxWidth: .infinity)
                            topSpacesCard(snapshot)
                                .frame(width: 330)
                        }

                        VStack(spacing: 16) {
                            categoryCard(snapshot)
                            topSpacesCard(snapshot)
                        }
                    }

                    cleanupPreview(snapshot)
                    storageMapCard(snapshot)

                    if snapshot.permissionIssueCount > 0 {
                        permissionCard(snapshot)
                    }

                    footer(snapshot)
                }
                .contentColumn()
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
            } else {
                EmptyStateView(
                    symbolName: "internaldrive",
                    title: "See what's taking up space",
                    message: "SpaceCrunch maps your storage, finds the junk, and lets you remove it safely.",
                    actionTitle: "Scan My Mac"
                ) {
                    model.startScan()
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Header

    private func header(_ snapshot: ScanSnapshot) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your Mac at a glance")
                    .font(AppFont.title)
                Text("Last scanned \(snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened)) · \(snapshot.fileCount.formatted()) files")
                    .font(AppFont.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if snapshot.cleanupGroups.isEmpty {
                Label("Everything looks tidy", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(
                        Glass.regular.tint(Color.green.opacity(0.25)),
                        in: Capsule()
                    )
            }
        }
    }

    // MARK: - Hero

    private func hero(_ snapshot: ScanSnapshot) -> some View {
        let itemCount = snapshot.cleanupGroups.reduce(0) { $0 + $1.itemCount }

        return HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("RECLAIMABLE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                }
                .foregroundStyle(.secondary)

                Text(SizeText.string(snapshot.reclaimableTotal))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("of clutter can be cleaned up")
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        model.section = .cleanup
                    } label: {
                        Label("Review & Clean", systemImage: "trash")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Text("\(itemCount.formatted()) items in \(snapshot.cleanupGroups.count) groups")
                        .font(AppFont.callout)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                heroStat(
                    title: "Safe to remove",
                    value: SizeText.string(snapshot.reclaimableSafe),
                    symbol: "checkmark.shield.fill",
                    tint: Color(red: 0.11, green: 0.62, blue: 0.34)
                )
                heroStat(
                    title: "Review first",
                    value: SizeText.string(snapshot.reclaimableReview),
                    symbol: "exclamationmark.shield.fill",
                    tint: Color(red: 0.91, green: 0.53, blue: 0.12)
                )
            }
            .padding(.leading, 20)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.6))
                    .frame(width: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(minHeight: 172)
        .glassEffect(
            Glass.regular.tint(Color.accentColor.opacity(0.16)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func heroStat(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Capacity

    private func capacityCard(_ snapshot: ScanSnapshot) -> some View {
        let used = snapshot.volume.used
        let scanned = snapshot.totalScanned
        let residual = max(0, used - min(used, scanned))
        var segments = snapshot.categoryRows.prefix(9).map { (color: $0.category.color, value: $0.size) }
        if residual > 0 {
            segments.append((color: Color(nsColor: .tertiaryLabelColor).opacity(0.5), value: residual))
        }

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "Storage", subtitle: "Macintosh HD")
                Spacer()
                Text("\(SizeText.string(snapshot.volume.free)) available of \(SizeText.string(snapshot.volume.total))")
                    .font(AppFont.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            CapacityBar(segments: segments, total: snapshot.volume.total, height: 13)

            HStack(spacing: 16) {
                legendDot(color: .accentColor, title: "Scanned", value: SizeText.string(scanned))
                legendDot(
                    color: Color(nsColor: .tertiaryLabelColor).opacity(0.5),
                    title: "System & other",
                    value: SizeText.string(residual)
                )
                legendDot(
                    color: Color(nsColor: .quaternaryLabelColor).opacity(0.35),
                    title: "Free",
                    value: SizeText.string(snapshot.volume.free)
                )
                Spacer()
            }
        }
        .card()
    }

    private func legendDot(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Categories

    private func categoryCard(_ snapshot: ScanSnapshot) -> some View {
        let slices = snapshot.categoryRows.map { CategorySlice(category: $0.category, size: $0.size) }
        let total = slices.reduce(Int64(0)) { $0 + $1.size }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "What's using space", subtitle: "Grouped by file type and location")
                Spacer()
                Text(SizeText.string(total))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if slices.isEmpty {
                Text("Nothing scanned yet.")
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                HStack(alignment: .center, spacing: 24) {
                    CategoryDonut(slices: slices, total: total)
                        .frame(width: 188, height: 188)

                    VStack(spacing: 7) {
                        ForEach(slices.prefix(9)) { slice in
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(slice.category.color)
                                    .frame(width: 8, height: 8)
                                Text(slice.category.title)
                                    .font(AppFont.callout)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(SizeText.string(slice.size))
                                    .font(AppFont.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(SizeText.percent(total > 0 ? Double(slice.size) / Double(total) : 0))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    // MARK: - Biggest folders

    private func topSpacesCard(_ snapshot: ScanSnapshot) -> some View {
        let children = Array((snapshot.homeRoot?.sortedChildren ?? []).prefix(7))
        let largest = max(1, children.map(\.size).max() ?? 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "Biggest folders", subtitle: "In your home folder")
                Spacer()
                Button("Explore") {
                    if let root = snapshot.homeRoot {
                        model.focusBrowse(root)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }

            if children.isEmpty {
                Text("No folders found.")
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 2) {
                    ForEach(children, id: \.path) { child in
                        Button {
                            model.focusBrowse(child)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(child.displayCategory.color)
                                    .frame(width: 17)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(child.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(SizeText.string(child.size))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(child.displayCategory.color.opacity(0.14))
                                            Capsule()
                                                .fill(child.displayCategory.color.opacity(0.8))
                                                .frame(
                                                    width: max(3, geo.size.width * CGFloat(Double(child.size) / Double(largest)))
                                                )
                                        }
                                    }
                                    .frame(height: 3)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .modifier(HoverHighlight())
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Cleanup preview

    private func cleanupPreview(_ snapshot: ScanSnapshot) -> some View {
        let groups = Array(snapshot.cleanupGroups.prefix(4))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(
                    title: "Recommended cleanup",
                    subtitle: groups.isEmpty ? "Nothing needs attention" : "\(snapshot.reclaimableTotal > 0 ? SizeText.string(snapshot.reclaimableTotal) : "0 bytes") across \(snapshot.cleanupGroups.count) groups"
                )
                Spacer()
                Button("Review All") {
                    model.section = .cleanup
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }

            if groups.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You're all tidied up")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("No caches, logs or build artifacts worth removing.")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(groups) { group in
                        Button {
                            model.section = .cleanup
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill((group.items.first?.category.color ?? .accentColor).opacity(0.16))
                                    Image(systemName: group.symbolName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(group.items.first?.category.color ?? .accentColor)
                                }
                                .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(group.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                    Text(group.subtitle)
                                        .font(AppFont.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)
                                SafetyBadge(safety: group.safety)
                                Text(SizeText.string(group.size))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 64, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .modifier(HoverHighlight())
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Storage map

    private func storageMapCard(_ snapshot: ScanSnapshot) -> some View {
        // A whole-disk scan has the real volume tree, so map that. A home-only scan
        // (the fixture mode) wraps the home in a synthetic two-child root, which
        // would make a map of nothing but "Home" and "Applications".
        let isHomeOnlyScan = snapshot.browseRoot.children["Home"] != nil
        let mapped = isHomeOnlyScan ? (snapshot.homeRoot ?? snapshot.browseRoot) : snapshot.browseRoot

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "Storage map", subtitle: "Click a block to explore that folder")
                Spacer()
                Button("Browse") {
                    model.browsePath = []
                    model.section = .browse
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }

            StorageTreemap(
                entries: TreemapEntry.entries(for: mapped, limit: 24),
                height: 230
            ) { node in
                model.focusBrowse(node)
            }
        }
        .card()
    }

    // MARK: - Permissions & footer

    private func permissionCard(_ snapshot: ScanSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .glassEffect(
                    Glass.regular.tint(Color.orange.opacity(0.3)),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Some folders couldn't be read")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(snapshot.permissionIssueCount.formatted()) locations were skipped. Some are protected by macOS itself; Full Disk Access opens the rest.")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                model.openFullDiskAccessSettings()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .card(padding: 14)
    }

    private func footer(_ snapshot: ScanSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text("Scanned \(snapshot.fileCount.formatted()) files in \(durationText(snapshot.duration))")
                .monospacedDigit()
            Spacer()
            Text("Sizes reflect allocated disk space")
        }
        .font(AppFont.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - Supporting views

struct CategorySlice: Identifiable {
    let category: SpaceCategory
    let size: Int64
    var id: SpaceCategory { category }
}

struct CategoryDonut: View {
    let slices: [CategorySlice]
    let total: Int64

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Size", slice.size),
                innerRadius: .ratio(0.72),
                angularInset: 2
            )
            .cornerRadius(3)
            .foregroundStyle(slice.category.color)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 1) {
                Text(SizeText.string(total))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text("scanned")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel("Category breakdown")
    }
}
