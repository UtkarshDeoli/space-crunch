import SpaceCrunchCore
import SwiftUI

struct SmartCleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    header(snapshot)

                    LazyVStack(spacing: 12) {
                        ForEach(snapshot.cleanupGroups) { group in
                            CleanupGroupCard(group: group)
                        }
                    }

                    if snapshot.cleanupGroups.isEmpty {
                        EmptyStateView(
                            symbolName: "checkmark.seal",
                            title: "Nothing to clean up",
                            message: "SpaceCrunch didn't find caches, logs, build artifacts or other clutter worth removing.",
                            actionTitle: "Scan Again"
                        ) {
                            model.startScan()
                        }
                        .card()
                    }

                    Text("Items marked “Review first” are safe to remove, but may need to be downloaded or rebuilt afterwards.")
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                }
                .contentColumn()
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupActionBar()
        }
    }

    private func header(_ snapshot: ScanSnapshot) -> some View {
        let safeGroups = snapshot.cleanupGroups.filter { $0.safety == .safe }
        let reviewGroups = snapshot.cleanupGroups.filter { $0.safety == .review }

        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(SizeText.string(snapshot.reclaimableTotal)) can be reclaimed")
                    .font(AppFont.title)
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(CleanupSafety.safe.color)
                        Text("\(SizeText.string(snapshot.reclaimableSafe)) safe · \(safeGroups.count) groups")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(CleanupSafety.review.color)
                        Text("\(SizeText.string(snapshot.reclaimableReview)) to review · \(reviewGroups.count) groups")
                    }
                }
                .font(AppFont.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Select Safe Items") {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.selectAllSafe()
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button("Deselect All") {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.clearSelection()
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(model.selectedItemIDs.isEmpty)
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Group card

struct CleanupGroupCard: View {
    let group: CleanupGroup

    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var showAllItems = false

    private var selectionState: AppModel.SelectionState {
        model.selectionState(for: group)
    }

    private var visibleItems: [CleanupItem] {
        showAllItems ? group.items : Array(group.items.prefix(25))
    }

    private var tintColor: Color {
        group.items.first?.category.color ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if expanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        CleanupItemRow(item: item, tint: tintColor)
                    }

                    if group.items.count > 25, !showAllItems {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                showAllItems = true
                            }
                        } label: {
                            Text("Show all \(group.items.count) items")
                                .font(AppFont.caption)
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
            }
        }
        // Interactive glass: the card dips when you press it, the way a
        // native button does. A plain glass surface gives no press feedback.
        .glassEffect(
            Glass.regular.interactive(),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    model.toggleGroup(group)
                }
            } label: {
                SelectionCircle(state: selectionState)
            }
            .buttonStyle(.plain)
            .help(selectionState == .all ? "Deselect this group" : "Select this group")

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tintColor.opacity(0.14))
                Image(systemName: group.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tintColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(group.title)
                        .font(AppFont.headline)
                        .lineLimit(1)
                    SafetyBadge(safety: group.safety)
                }
                Text("\(group.subtitle) · \(group.itemCount) item\(group.itemCount == 1 ? "" : "s")")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text(SizeText.string(group.size))
                .font(AppFont.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) {
                expanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Collapses this group" : "Expands this group")
    }
}

// MARK: - Item row

struct CleanupItemRow: View {
    let item: CleanupItem
    let tint: Color

    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private var isSelected: Bool {
        model.selectedItemIDs.contains(item.id)
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                model.toggle(item)
            } label: {
                SelectionCircle(state: isSelected ? .all : .none)
            }
            .buttonStyle(.plain)

            Image(systemName: item.isDirectory ? "folder.fill" : item.category.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(AppFont.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.detail)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let modified = item.modified {
                        Text("·")
                        Text(SizeText.relativeDate(modified))
                    }
                }
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if hovering {
                Button {
                    model.revealInFinder(item.url)
                } label: {
                    Image(systemName: "arrow.forward.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .transition(.opacity)
            }

            Text(SizeText.string(item.size))
                .font(AppFont.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 54, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.045 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Reveal in Finder") {
                model.revealInFinder(item.url)
            }
            Button(isSelected ? "Deselect" : "Select") {
                model.toggle(item)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Action bar

struct CleanupActionBar: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    private var items: [CleanupItem] { model.selectedCleanupItems }
    private var permanent: Bool { model.selectionIsPermanent }
    private var mixed: Bool { model.selectionIsMixed }

    private var actionLabel: String {
        if permanent { return "Delete Permanently" }
        if mixed { return "Remove Items" }
        return "Move to Trash"
    }

    private var alertTitle: String {
        let count = items.count
        let noun = count == 1 ? "item" : "items"
        if permanent { return "Delete \(count) \(noun) permanently?" }
        if mixed { return "Remove \(count) \(noun)?" }
        return "Move \(count) \(noun) to the Trash?"
    }

    private var alertMessage: String {
        if permanent {
            return "This frees \(SizeText.string(model.selectedCleanupSize)) and can't be undone."
        }
        if mixed {
            return "Items already in the Trash are deleted permanently. Everything else moves to the Trash so you can restore it."
        }
        return "This frees \(SizeText.string(model.selectedCleanupSize)). You can restore the items from the Trash."
    }

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: permanent || mixed ? "trash.slash.fill" : "trash.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(permanent ? Color.red : Color.accentColor)

                Text("\(items.count) item\(items.count == 1 ? "" : "s") selected")
                    .font(AppFont.callout.weight(.semibold))
                Text("· \(SizeText.string(model.selectedCleanupSize))")
                    .font(AppFont.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Button("Deselect") {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.selectedItemIDs = []
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
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(actionLabel)
                    }
                    .font(AppFont.callout.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(permanent ? Color.red : Color.accentColor)
                .disabled(model.isCleaning)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(
                Glass.regular.tint((permanent ? Color.red : Color.accentColor).opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .alert(alertTitle, isPresented: $confirming) {
                Button(actionLabel, role: .destructive) {
                    Task { await model.cleanSelectedItems() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }
}
