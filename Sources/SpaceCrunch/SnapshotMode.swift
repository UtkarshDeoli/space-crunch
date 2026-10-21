import AppKit
import Darwin
import Foundation
import SwiftUI

/// Development helper: launch with `--capture-dir <dir>` to scan, then save a
/// PNG of each section. It captures the app's own window from the window
/// server, so it needs no Screen Recording permission. `--home <path>` scans a
/// fixture instead of the real home.
@MainActor
enum SnapshotMode {
    static var outputDirectory: String? {
        value(after: "--capture-dir")
    }

    static var homeOverride: String? {
        value(after: "--home")
    }

    static func run(model: AppModel, directory: String) async {
        // A full home folder can hold tens of millions of files, and a cold cache
        // makes the scan a slow read. Give it plenty of room before giving up —
        // capturing the scanning screen would be worthless.
        var waited = 0
        while model.phase == .scanning, waited < 18_000 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }
        if model.phase == .scanning {
            model.cancelScan()
            try? await Task.sleep(for: .milliseconds(600))
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        // An unfocused window renders accent-coloured controls in grey, so the
        // capture wouldn't show the real colours.
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        if let rawSize = value(after: "--window-size"),
           let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            let parts = rawSize.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            }
        }
        try? await Task.sleep(for: .milliseconds(500))

        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // A full home folder takes minutes to scan, so it is worth recording
        // every appearance in the one pass rather than scanning again for each.
        let appearances = value(after: "--appearance").map { [$0] } ?? ["dark", "light"]

        let sections: [(section: AppModel.Section, name: String)] = [
            (.overview, "overview"),
            (.cleanup, "cleanup"),
            (.largeFiles, "large-files"),
            (.browse, "browse"),
        ]

        for appearance in appearances {
            NSApplication.shared.appearance = NSAppearance(
                named: appearance == "light" ? .aqua : .darkAqua
            )
            let destination = root.appendingPathComponent(appearance, isDirectory: true)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try? await Task.sleep(for: .milliseconds(600))

            for entry in sections {
                model.section = entry.section
                if entry.section == .browse, let home = model.snapshot?.homeRoot {
                    model.drill(into: home)
                }
                try? await Task.sleep(for: .milliseconds(700))
                await CaptureWindow.capture(to: destination.appendingPathComponent("\(entry.name).png"))

                if entry.section == .overview || entry.section == .cleanup {
                    if entry.section == .overview {
                        CaptureWindow.scrollMainContent(to: 0.42)
                        try? await Task.sleep(for: .milliseconds(650))
                        await CaptureWindow.capture(to: destination.appendingPathComponent("\(entry.name)-middle.png"))
                    }
                    CaptureWindow.scrollMainContent(to: 1)
                    try? await Task.sleep(for: .milliseconds(650))
                    await CaptureWindow.capture(to: destination.appendingPathComponent("\(entry.name)-bottom.png"))
                    CaptureWindow.scrollMainContent(to: 0)
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }

        NSApplication.shared.terminate(nil)
    }


    private static func value(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }
}
