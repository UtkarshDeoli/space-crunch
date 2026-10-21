import Darwin
import SpaceCrunchCore
import SwiftUI

@main
struct SpaceCrunchApp: App {
    @State private var model = AppModel()

    init() {
        raiseOpenFileLimit()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 600)
        }
        .defaultSize(width: 1_180, height: 780)
        // The title and subtitle belong to the real title bar, not to a view
        // floating in the content.
        //
        // With `showsTitle: false` the title was drawn into the content layer,
        // and the title bar's glass then smeared it into an unreadable blur
        // that sat next to a crisp title. Showing the title natively lets the
        // window draw it the way every other Mac app does.
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            SpaceCrunchCommands(model: model)
        }
    }
}

struct SpaceCrunchCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .toolbar) {
            Button("Scan Now") {
                model.startScan()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isScanning)

            Button("Cancel Scan") {
                model.cancelScan()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.isScanning)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailColumn
                // The wash belongs to the detail column. The sidebar keeps the
                // system's own material that way, which is how a native split
                // view looks — and the glow lands in the trailing corner of the
                // content rather than in the middle of the sidebar.
                .background(AppBackground())
                .navigationTitle(model.section.title)
                .navigationSubtitle(subtitle)
                .toolbar {
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                    ToolbarItem(placement: .primaryAction) {
                        scanControl
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if model.isScanning, model.snapshot != nil {
                        ScanStatusBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .animation(.snappy(duration: 0.25), value: model.isScanning)
        .task {
            model.startScanIfNeeded()
            if let directory = DemoMode.outputDirectory {
                await DemoMode.run(
                    model: model,
                    directory: URL(fileURLWithPath: directory, isDirectory: true)
                )
            } else if let directory = SnapshotMode.outputDirectory {
                await SnapshotMode.run(model: model, directory: directory)
            }
        }
    }

    /// The detail column's content, gathered into one glass group.
    ///
    /// The container stops at the content on purpose. A container that reaches
    /// up into the title bar pulls the window's toolbar items into its shared
    /// glass layer, and that group gets composited over the toolbar's labels —
    /// which turns the rescan and sidebar-toggle glyphs into pale ghosts. The
    /// toolbar renders on its own, the way a system app's does.
    private var detailColumn: some View {
        GlassEffectContainer(spacing: 0) {
            detail
        }
    }

    private var subtitle: String {
        guard let snapshot = model.snapshot else { return "Not scanned yet" }
        return "\(SizeText.string(snapshot.totalScanned)) in \(snapshot.fileCount.formatted()) files"
    }

    @ViewBuilder
    private var detail: some View {
        switch model.phase {
        case .scanning where model.snapshot == nil:
            ScanningView()
        case .failed(let message) where model.snapshot == nil:
            EmptyStateView(
                symbolName: "exclamationmark.triangle",
                title: "Scan couldn't start",
                message: message,
                actionTitle: "Try Again"
            ) {
                model.startScan()
            }
        default:
            if model.snapshot == nil {
                EmptyStateView(
                    symbolName: "internaldrive",
                    title: "See what's taking up space",
                    message: "SpaceCrunch maps your storage, finds the junk, and lets you remove it safely.",
                    actionTitle: "Scan My Mac"
                ) {
                    model.startScan()
                }
            } else {
                sectionView
            }
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch model.section {
        case .overview:
            OverviewView()
        case .cleanup:
            SmartCleanupView()
        case .largeFiles:
            LargeFilesView()
        case .browse:
            BrowseView()
        }
    }

    @ViewBuilder
    private var scanControl: some View {
        if model.isScanning {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel") {
                    model.cancelScan()
                }
                .controlSize(.regular)
            }
        } else {
            Button {
                model.startScan()
            } label: {
                Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.glass)
            .help("Scan again (⌘R)")
        }
    }
}

// MARK: - Scan banner

struct ScanStatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Scanning…")
                .font(.system(size: 12, weight: .semibold))

            Text("\(model.progress.files.formatted()) files · \(SizeText.string(model.progress.bytes))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(SizeText.abbreviatedPath(model.progress.currentPath, home: model.snapshot?.homeURL.path ?? ""))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300, alignment: .leading)

            Spacer()

            Button("Cancel") {
                model.cancelScan()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        // The banner floats over the content, so it has to refract what is
        // behind it. A flat bar would read as a different app.
        .glassEffect(
            Glass.regular,
            in: UnevenRoundedRectangle(
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                style: .continuous
            )
        )
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: toast.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(toast.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(
            Glass.regular.tint(tint.opacity(0.2)),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch toast.tint {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

/// launchd starts GUI apps with a soft `RLIMIT_NOFILE` of 256, while the
/// scanner holds thousands of directory descriptors at once. Raise the soft
/// limit to whatever the hard limit allows before any scan begins.
private func raiseOpenFileLimit() {
    var limit = rlimit()
    guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
    let target: rlim_t = min(limit.rlim_max, 65_536)
    guard limit.rlim_cur < target else { return }
    limit.rlim_cur = target
    setrlimit(RLIMIT_NOFILE, &limit)
}
