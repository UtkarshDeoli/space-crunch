# SpaceCrunch 1.0.0

The first public release of SpaceCrunch — a native macOS storage scanner that
maps your whole disk, finds the junk worth throwing away, and removes it
safely.

## Highlights

- **Whole-disk treemap.** Every real top-level folder from `/` is scanned and
  mapped as a squarified treemap you can click through, folder by folder,
  without rescanning. Firmlinked paths and mounted disks are skipped, so no
  byte is counted twice.
- **Folders coloured by what they actually contain.** The scanner tallies
  bytes per category as it walks the tree and rolls those tallies up, so a
  blue block really is 12 GB of video — not "some folder called Downloads".
- **Fifteen cleanup groups.** Xcode DerivedData, application and package
  manager caches, logs, `node_modules`, Swift build folders, Xcode Archives,
  simulator devices and runtimes, iOS DeviceSupport, device backups, the
  Docker disk image, old installers, and the Trash. "Safe to remove" groups
  are pre-selected; "Review first" groups need an explicit choice.
- **Large file list** with native Finder icons, sorting, multi-selection and
  Reveal in Finder.
- **Reversible deletion.** Items move to the Trash via
  `FileManager.trashItem`, so everything is restorable. Only items already in
  the Trash are deleted permanently, and every deletion asks for confirmation.
- **Liquid Glass interface.** Built on macOS 26's `glassEffect`,
  `GlassEffectContainer` and `scrollEdgeEffectStyle` APIs — a single shared
  glass group in the detail column, a colour wash behind it, and a real title
  bar.

## Requirements

- macOS 26 or newer
- Xcode 26+ (Swift 6.2 toolchain) to build from source

## Installation

Download the `.dmg` from the assets below, open it, and drag SpaceCrunch into
Applications.

> The release build is **ad-hoc signed**, because signing and notarizing for
> distribution requires a paid
> [Apple Developer Program](https://developer.apple.com/programs/) membership.
> On first launch macOS will show *"SpaceCrunch cannot be opened because it is
> from an unidentified developer."* Right-click the app in Applications →
> **Open** → **Open** to approve it once. After that it launches normally.

## Full Disk Access

Some folders macOS protects are skipped until the app is granted Full Disk
Access:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Add `SpaceCrunch.app`.
3. Relaunch and press `⌘R` to rescan.

Without the permission the app still finishes a full scan in a few minutes —
it opens each directory relative to its parent, which turns macOS's
unbounded authorization wait into a bounded five-second timeout per protected
folder — but the protected folders themselves are counted as permission
problems and left out of the totals.

## Checksums

A `.sha256` file is attached alongside the DMG:

```sh
shasum -a 256 -c SpaceCrunch-1.0.0.dmg.sha256
```

## Building from source

```bash
git clone https://github.com/UtkarshDeoli/space-crunch.git
cd space-crunch
scripts/build_app.sh
open dist/SpaceCrunch.app
```

## License

MIT — see [LICENSE](LICENSE).
