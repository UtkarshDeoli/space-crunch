import SpaceCrunchCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(
            selection: Binding(
                get: { model.section },
                set: { newValue in
                    if let newValue { model.section = newValue }
                }
            )
        ) {
            Section("Cleanup") {
                row(.overview)
                row(.cleanup)
                row(.largeFiles)
            }

            Section("Explore") {
                row(.browse)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 280)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VolumeSidebarCard()
                .padding(10)
        }
    }

    private func row(_ section: AppModel.Section) -> some View {
        HStack(spacing: 7) {
            Label(section.title, systemImage: section.symbolName)
            Spacer(minLength: 4)
            if section == .cleanup, let snapshot = model.snapshot, snapshot.reclaimableTotal > 0 {
                Text(SizeText.string(snapshot.reclaimableTotal))
                    .font(AppFont.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(section)
    }
}

struct VolumeSidebarCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Macintosh HD")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                CapacityBar(
                    segments: snapshot.categoryRows.prefix(8).map { (color: $0.category.color, value: $0.size) },
                    total: snapshot.volume.total,
                    height: 6
                )

                Text("\(SizeText.string(snapshot.volume.free)) available of \(SizeText.string(snapshot.volume.total))")
                    .font(AppFont.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(11)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }
}
