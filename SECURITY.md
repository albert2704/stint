# Security

Stint is an early macOS application. Security fixes currently target the latest default branch. There is no long-term support release policy yet.

## Report a vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/albert2704/stint/security/advisories/new). Include the affected commit or version, macOS version, reproduction steps, and likely impact. A small reproduction using synthetic data is more useful than a copy of your personal workspace.

Do not put credentials, imported audio, saved notes, timer history, or personal file paths in a public issue. If private reporting is unavailable, open a public issue asking for a private contact channel without disclosing the vulnerability.

There is no guaranteed response time or bug bounty. Coordinated disclosure is appreciated.

## Relevant boundaries

- The app stores state locally and does not provide a Stint account or cloud service.
- YouTube playback connects to external YouTube services in a native WebKit view.
- Imported audio is copied into the app's local library.
- The development bundle and downloadable prerelease use ad hoc signatures. They are not signed with an Apple Developer ID or notarized by Apple. A valid checksum or local signature does not establish Apple approval. See the [installation guide](docs/install.md#first-launch-and-gatekeeper) for the first-launch warning.
- The release packaging workflow checks architecture slices, release sandbox entitlements, and bundle integrity. Its disposable-runner smoke check establishes startup only, not a full security audit or testing of every supported device.
- Global shortcuts register specific key combinations. The shortcut recorder captures keys only while you explicitly record a binding in Stint.

See the [privacy notes](docs/privacy.md) for storage and network behavior.
