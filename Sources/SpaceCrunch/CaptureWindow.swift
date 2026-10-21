import AppKit
import Foundation

/// Window capture helpers shared by the development snapshot and demo modes.
///
/// The window is grabbed straight from the window server, because only the
/// window server can resolve the backdrop sampling that Liquid Glass depends
/// on — `cacheDisplay` draws glass as a flat fill.
enum CaptureWindow {
    /// Writes a PNG of the app's own window to `url`.
    @MainActor
    static func capture(to url: URL) async {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
            NSLog("CaptureWindow: no visible window")
            return
        }
        // An inactive window draws AppKit-backed controls (the glass buttons)
        // in grey, so the capture wouldn't show the real colours. Focus can take
        // a moment to settle, so give it a few tries before giving up.
        if !window.isKeyWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            for _ in 0..<12 where !window.isKeyWindow {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard let image = captureOwnWindow() else {
            NSLog("CaptureWindow: could not capture window")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            NSLog("CaptureWindow: could not encode PNG")
            return
        }
        do {
            try data.write(to: url)
            print("CaptureWindow: wrote \(url.path) (\(image.width)×\(image.height))")
        } catch {
            NSLog("CaptureWindow: write failed: \(error)")
        }
    }

    /// Grabs this process's own window straight from the window server.
    ///
    /// `CGWindowListCreateImage` is marked unavailable in the SDK, but the
    /// symbol is still exported, and capturing your own process's window
    /// doesn't require Screen Recording permission — so it is resolved by name.
    private static func captureOwnWindow() -> CGImage? {
        typealias CreateFn = @convention(c) (
            CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption
        ) -> CGImage?

        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        let create = unsafeBitCast(symbol, to: CreateFn.self)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let processName = ProcessInfo.processInfo.processName
        var bestID: CGWindowID = 0
        var bestArea: Double = 0

        for info in windowList {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == processName else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            let area = (bounds["Width"] as? Double ?? 0) * (bounds["Height"] as? Double ?? 0)
            if area > bestArea {
                bestArea = area
                bestID = CGWindowID(number)
            }
        }
        guard bestID != 0 else { return nil }

        return create(
            .null,
            .optionIncludingWindow,
            bestID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    /// Scrolls the detail column to a fraction of its content height.
    ///
    /// The largest scroll view in the window is the one that matters — the
    /// sidebar and the treemap are both shorter than the detail column.
    @MainActor
    static func scrollMainContent(to fraction: CGFloat) {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
              let content = window.contentView else { return }

        let scrollViews = allScrollViews(in: content).filter { scroll in
            guard let document = scroll.documentView else { return false }
            return document.frame.height > scroll.contentView.bounds.height + 20
        }
        guard let scroll = scrollViews.max(by: { first, second in
            (first.documentView?.frame.height ?? 0) < (second.documentView?.frame.height ?? 0)
        }), let document = scroll.documentView else { return }

        let maxY = max(0, document.frame.height - scroll.contentView.bounds.height)
        let origin = NSPoint(
            x: scroll.contentView.bounds.origin.x,
            y: maxY * min(1, max(0, fraction))
        )
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private static func allScrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for subview in view.subviews {
            found.append(contentsOf: allScrollViews(in: subview))
        }
        return found
    }
}
