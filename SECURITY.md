# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | ✅ |
| < 1.0 | ❌ |

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue.

Use GitHub's private vulnerability reporting on the
[Security tab of this repository](https://github.com/UtkarshDeoli/space-crunch/security/advisories/new),
or email the maintainer directly.

Include:

- What the issue is and which version of SpaceCrunch it affects
- Steps to reproduce
- The impact you believe it has

You can expect an acknowledgement within a few days and a fix or mitigation
plan once the report is confirmed.

## Scope

SpaceCrunch is a local, offline utility. It makes no network requests, has no
telemetry, and reads file *metadata* only — never file contents.

The following are **not** vulnerabilities:

- **The app requests broad file access.** It is deliberately not sandboxed,
  because a storage scanner needs to read the whole volume to do its job. It
  reads names, sizes and dates, and never reads or uploads file contents.
- **Deleting to the Trash.** Items are moved to the Trash with
  `FileManager.trashItem` and are restorable from Finder. Every deletion asks
  for confirmation, and permanent deletion is limited to items already in
  `~/.Trash`.
- **The app is not notarized.** Release builds are ad-hoc signed, because
  distribution signing requires a paid Apple Developer Program membership.
  macOS will show a Gatekeeper warning on first launch.
