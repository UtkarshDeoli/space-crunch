import SpaceCrunchCore
import SwiftUI

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 30)

            ScanningOrb()

            VStack(spacing: 7) {
                Text("Scanning your Mac")
                    .font(AppFont.largeTitle)
                Text("Mapping every folder, file and cache.")
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 9) {
                Text("\(model.progress.files.formatted()) files · \(SizeText.string(model.progress.bytes))")
                    .font(AppFont.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if !model.progress.currentPath.isEmpty {
                    Text(SizeText.abbreviatedPath(model.progress.currentPath, home: FileManager.default.homeDirectoryForCurrentUser.path))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 430)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .glassEffect(
                            .regular,
                            in: Capsule()
                        )
                }
            }

            Button("Cancel") {
                model.cancelScan()
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, 2)

            Text("SpaceCrunch only reads file sizes. Nothing leaves your Mac.")
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningOrb: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.02)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )
                    .frame(width: 230, height: 230)

                Circle()
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 9)
                    .frame(width: 164, height: 164)

                Circle()
                    .trim(from: 0.02, to: 0.52)
                    .stroke(
                        AngularGradient(
                            colors: [Color.accentColor.opacity(0.05), Color.accentColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: 164, height: 164)
                    .rotationEffect(.degrees(time * 52))

                Circle()
                    .trim(from: 0.62, to: 0.9)
                    .stroke(
                        Color.accentColor.opacity(0.3),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: 164, height: 164)
                    .rotationEffect(.degrees(-time * 34))

                Circle()
                    .frame(width: 104, height: 104)
                    .glassEffect(
                        .regular,
                        in: Circle()
                    )

                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: 230, height: 230)
        .accessibilityLabel("Scanning")
    }
}
