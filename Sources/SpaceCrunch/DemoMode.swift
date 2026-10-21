import AppKit
import Foundation
import SpaceCrunchCore
import SwiftUI

/// Development helper: launch with `--demo-dir <dir>` to run a scripted tour of
/// the app, capturing a PNG of every step.
///
/// Unlike `SnapshotMode`, which grabs one still per screen, this walks through
/// the app the way a person would — switching sections, scrolling, drilling into
/// the treemap — and captures a frame at every step. The frames are later
/// assembled into a GIF, so the tour needs to move in small increments: a
/// capture per animated transition, not per destination.
///
/// Frames are written to `<dir>/frames/NNNN.png` in order. The intended
/// duration of each frame is recorded in `<dir>/durations.txt`, one line per
/// frame, so the GIF can be assembled with the right pacing: a screen the
/// viewer should read lingers longer than one that is only passing through.
@MainActor
enum DemoMode {
    static var outputDirectory: String? {
        value(after: "--demo-dir")
    }

    static func run(model: AppModel, directory: URL) async {
        let frames = directory.appendingPathComponent("frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        // Let the scan finish. A whole-disk scan of a real home folder takes
        // minutes, so the wait is generous.
        var waited = 0
        while model.phase == .scanning, waited < 30_000 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }
        if model.phase == .scanning {
            model.cancelScan()
            try? await Task.sleep(for: .milliseconds(600))
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
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
        try? await Task.sleep(for: .milliseconds(700))

        let appearance = value(after: "--appearance") ?? "dark"
        NSApplication.shared.appearance = NSAppearance(
            named: appearance == "light" ? .aqua : .darkAqua
        )
        try? await Task.sleep(for: .milliseconds(800))

        var index = 0
        var holds: [(seconds: Double, motion: Bool)] = []

        /// Captures one frame and records how long it should be held.
        ///
        /// `motion` marks a frame captured mid-scroll, on its way to somewhere.
        /// The GIF builder uses the flag to thin those out: a scroll needs
        /// enough frames to read as movement, but not one per step, and the
        /// dwell frames that follow are what the viewer actually reads.
        func shoot(_ seconds: Double, motion: Bool = false) async {
            let name = String(format: "%04d.png", index)
            index += 1
            holds.append((seconds, motion))
            await CaptureWindow.capture(to: frames.appendingPathComponent(name))
        }

        /// Lets the app settle before the next capture, without recording a
        /// frame for the wait itself.
        func settle(_ milliseconds: Int) async {
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }

        /// Moves the detail column's scroll position in small steps, capturing
        /// each one so the GIF shows the scroll rather than a jump.
        ///
        /// SwiftUI scroll views can't be driven by a value binding, so the clip
        /// view is moved directly and the app is given a beat to redraw.
        func scroll(to fraction: CGFloat, steps: Int = 8) async {
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                CaptureWindow.scrollMainContent(to: fraction * t)
                await settle(70)
                await shoot(0.05, motion: true)
            }
        }

        // MARK: The tour

        // 1. Overview — the hero card and the reclaimable total.
        model.section = .overview
        await settle(900)
        await shoot(1.6)

        // 2. Scroll down past the storage bar to the category breakdown.
        await scroll(to: 0.34)
        await shoot(1.4)

        // 3. The category donut and the biggest folders.
        await scroll(to: 0.66)
        await shoot(1.6)

        // 4. The cleanup preview and the storage map.
        await scroll(to: 1.0)
        await shoot(1.8)

        // 5. Back to the top, then over to Smart Cleanup.
        await scroll(to: 0)
        await settle(300)
        model.section = .cleanup
        await settle(900)
        await shoot(1.8)

        // 6. The cleanup groups further down the page.
        await scroll(to: 0.55)
        await shoot(1.5)
        await scroll(to: 1.0)
        await shoot(1.6)

        // 7. Large files.
        await scroll(to: 0)
        await settle(300)
        model.section = .largeFiles
        await settle(900)
        await shoot(2.0)

        // 8. Browse — the home folder as a treemap.
        model.section = .browse
        await settle(900)
        await shoot(2.0)

        // 9. Drill into the largest folder, so the treemap zooms in.
        if let home = model.snapshot?.homeRoot,
           let largest = home.sortedChildren.first(where: { $0.size > 0 }) {
            model.drill(into: largest)
            await settle(1000)
            await shoot(2.0)
        }

        // 10. Back to the overview for the closing frame.
        model.section = .overview
        model.browsePath = []
        await settle(900)
        await shoot(1.5)

        // Write the timing manifest next to the frames: one line per frame,
        // holding how long to show it and whether it was captured mid-scroll.
        //
        // It ends with a newline so that a reader looping over the lines
        // doesn't drop the last one.
        let manifest = holds
            .map { String(format: "%.3f %d", $0.seconds, $0.motion ? 1 : 0) }
            .joined(separator: "\n") + "\n"
        try? manifest.write(
            to: directory.appendingPathComponent("durations.txt"),
            atomically: true,
            encoding: .utf8
        )

        print("DemoMode: wrote \(index) frames to \(frames.path)")
        NSApplication.shared.terminate(nil)
    }

    private static func value(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }
}
