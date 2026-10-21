# Contributing to SpaceCrunch

Thanks for wanting to help. SpaceCrunch is a small, native macOS app with no
third-party dependencies, and it stays that way.

## Getting set up

```bash
git clone https://github.com/UtkarshDeoli/space-crunch.git
cd space-crunch
swift build
swift run SpaceCrunch
```

You need **macOS 26 or newer** and **Xcode 26+** (Swift 6.2 toolchain). The app
is built on Apple's Liquid Glass APIs, so it won't compile against an older
SDK.

## Before you open a pull request

```bash
swift test          # the core test suite must pass
scripts/build_app.sh # the app bundle must still build
```

## How the code is laid out

| Path | What's in it |
| --- | --- |
| `Sources/SpaceCrunchCore/` | Scanning, classification, cleanup rules, deletion, models. Pure Swift, no UI — this is where the tests live. |
| `Sources/SpaceCrunch/` | The SwiftUI app: views, theme, app model, and the development capture modes. |
| `Tests/SpaceCrunchCoreTests/` | The test suite. |
| `scripts/` | Build, packaging and asset-generation scripts. |

The split matters: `SpaceCrunchCore` must stay free of AppKit and SwiftUI, so
the scanning and deletion logic can be tested without a window server.

## Things worth knowing before you change the scanner

**The scanner must never open a directory by absolute path.** On macOS 26, an
app without Full Disk Access doesn't get `EACCES` when opening a protected
folder — the `open(2)` syscall *blocks forever* inside a TCC authorization
wait. A relative `openat(parentFD, name, O_RDONLY | O_DIRECTORY)` doesn't hang:
it returns `EINTR` after about five seconds on a protected folder and succeeds
instantly on a normal one. So the walk opens each root's parent absolutely
(never protected) and everything below it relatively. Treat a failed open as
"permission denied" for that subtree.

`access(2)`, `stat(2)`, `lstat(2)`, `readdir(2)` and `statfs(2)` all return
success for protected paths, so none of them can detect the condition.

**The job queue must never block.** A bounded queue deadlocks: a walk blocked
in `submit` can't read the folders it has already opened, and only those reads
free the descriptor budget. `submit` never waits; the queue holds pending opens
and grows, and the live descriptor count is bounded by the read budget plus the
distinct parents of queued jobs. Also, don't use `jobs.removeFirst()` on that
queue — it shifts the whole array and makes dequeuing quadratic. Consume by
index and compact in batches.

**Descriptors need an explicit budget.** A whole-volume walk peaked at ~31k
live directory descriptors. launchd starts GUI apps with a soft `RLIMIT_NOFILE`
of 256, so `SpaceCrunchApp.init()` raises the soft limit to `min(hard, 65536)`
before any scan. The pool keeps a hard ceiling on *opened-but-unread* folders.

**Full Disk Access is keyed to the code signature, not the path.** The ad-hoc
signature changes on every rebuild, so macOS silently revokes the grant after
a rebuild. Don't be surprised if a permission toggle needs re-enabling.

## Style

Match the surrounding code. Comments explain *why* something is the way it is,
not what the line does — the existing code is the best reference for tone and
density.

## Pull requests

- Keep the change focused. One topic per PR.
- Add or update tests for behaviour changes in `SpaceCrunchCore`.
- If you change the UI, mention how it looks — a screenshot in the PR is ideal.
