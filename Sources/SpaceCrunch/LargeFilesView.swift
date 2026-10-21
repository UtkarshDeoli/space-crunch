import AppKit
import SpaceCrunchCore
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model

    @State private var sortOrder: [KeyPathComparator<LargeFile>] = [
        KeyPathComparator(\LargeFile.size, order: .reverse)
    ]
    @State private var minimumSize: Int64 = 100_000_000
    @State private var confirming = false

    private let sizeOptions: [(label: String, value: Int64)] = [
        ("Over 100 MB", 100_000_000),
        ("Over 500 MB", 500_000_000),
        ("Over 1 GB", 1_000_000_000),
        ("Over 5 GB", 5_000_000_000),
    ]

    var body: some View {
        @Bindable var model = model
        let files = filteredFiles
        let total = files.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(files.count.formatted()) large file\(files.count == 1 ? "" : "s") · \(SizeText.string(total))")
                        .font(AppFont.title)
                    Text("The biggest files on this Mac.")
                        .font(AppFont.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Minimum size", selection: $minimumSize) {
                    ForEach(sizeOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 132)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Divider()

            Table(files, selection: $model.selectedLargeFileIDs, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 7) {
                        NativeFileIcon(url: file.url, size: 16)
                        Text(file.name)
                            .lineLimit(1)
                    }
                }
                .width(min: 170, ideal: 220)

                TableColumn("Location", value: \.folder) { file in
                    Text(SizeText.abbreviatedPath(file.folder, home: model.snapshot?.homeURL.path ?? ""))
                        .font(AppFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Size", value: \.size) { file in
                    Text(SizeText.string(file.size))
                        .font(AppFont.callout.weight(.medium))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 76, max: 100)

                TableColumn("Modified") { file in
                    Text(SizeText.relativeDate(file.modified))
                        .font(AppFont.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 76, max: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if files.isEmpty {
                    EmptyStateView(
                        symbolName: model.searchText.isEmpty ? "doc" : "magnifyingglass",
                        title: model.searchText.isEmpty ? "No large files" : "No matches",
                        message: model.searchText.isEmpty
                            ? "Nothing over \(SizeText.string(minimumSize)) was found."
                            : "No files match “\(model.searchText)”."
                    )
                }
            }
            .contextMenu(forSelectionType: LargeFile.ID.self) { selection in
                if !selection.isEmpty {
                    let selected = files.filter { selection.contains($0.id) }
                    if selected.count == 1 {
                        Button("Reveal in Finder") {
                            model.revealInFinder(selected[0].url)
                        }
                        Divider()
                    }
                    Button("Move \(selected.count) Item\(selected.count == 1 ? "" : "s") to Trash") {
                        model.selectedLargeFileIDs = selection
                        confirming = true
                    }
                }
            } primaryAction: { selection in
                if let file = files.first(where: { selection.contains($0.id) }) {
                    model.revealInFinder(file.url)
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search large files")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.selectedLargeFiles.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)

                    Text("\(model.selectedLargeFiles.count) file\(model.selectedLargeFiles.count == 1 ? "" : "s") selected")
                        .font(AppFont.callout.weight(.semibold))
                    Text("· \(SizeText.string(model.selectedLargeFilesSize))")
                        .font(AppFont.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Button("Deselect") {
                        withAnimation(.snappy(duration: 0.2)) {
                            model.selectedLargeFileIDs = []
                        }
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)

                    Button {
                        confirming = true
                    } label: {
                        HStack(spacing: 6) {
                            if model.isCleaning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("Move to Trash")
                        }
                        .font(AppFont.callout.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(model.isCleaning)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(
                    Glass.regular.tint(Color.accentColor.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .alert(
            "Move \(model.selectedLargeFiles.count) file\(model.selectedLargeFiles.count == 1 ? "" : "s") to the Trash?",
            isPresented: $confirming
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.cleanSelectedLargeFiles() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(SizeText.string(model.selectedLargeFilesSize)). You can restore the files from the Trash.")
        }
    }

    private var filteredFiles: [LargeFile] {
        guard let snapshot = model.snapshot else { return [] }
        var files = snapshot.largeFiles.filter { $0.size >= minimumSize }
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            files = files.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.folder.localizedCaseInsensitiveContains(query)
            }
        }
        return files.sorted(using: sortOrder)
    }
}

struct NativeFileIcon: View {
    let url: URL
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
