# Install Stint

Stint v0.1.0 targets macOS 12 or later and includes Apple Silicon and Intel code in one universal app. The package build and Apple Silicon startup check passed. Physical Intel and macOS 12 testing have not been completed; see [verification details](testing.md#downloadable-package-verification).

The download includes the app and its runtime. You do not need Flutter, Xcode, or developer tools to use it. See [build from source](development.md) if you want to build Stint yourself.

## Choose a download

You can find these files under **Assets** on the [Stint v0.1.0 release page](https://github.com/albert2704/stint/releases/tag/v0.1.0):

| File | Use |
| --- | --- |
| [Stint-0.1.0-macos-universal.dmg](https://github.com/albert2704/stint/releases/download/v0.1.0/Stint-0.1.0-macos-universal.dmg) | Recommended. Open the disk image, then copy Stint to Applications. |
| [Stint-0.1.0-macos-universal.zip](https://github.com/albert2704/stint/releases/download/v0.1.0/Stint-0.1.0-macos-universal.zip) | Alternative archive containing the same app. |
| [SHA256SUMS.txt](https://github.com/albert2704/stint/releases/download/v0.1.0/SHA256SUMS.txt) | Checksums for checking the downloaded archives. |

The GitHub **Source code** archives contain the project source, not an app ready to open.

**This is a prerelease with an ad hoc signature. It is not signed with an Apple Developer ID and is not notarized by Apple.** A successful checksum comparison does not establish developer identity or Apple approval. Expect a Gatekeeper warning on first launch.

## Install the app

1. You can download the DMG from the release page and open it in Finder.
2. Drag **Stint.app** into **Applications**.
3. Eject the Stint disk image, then open Stint from Applications.

If you prefer the ZIP, double click it in Finder to extract **Stint.app**, then move the app into Applications and open it there.

If Stint is already running, choose **Stint → Quit Stint** before replacing it. Closing the window alone keeps the app running in the menu bar. Keep one copy open at a time, because all copies use the same local data identity.

## First launch and Gatekeeper

Because this prerelease has no Developer ID signature or notarization, macOS may say it cannot verify the developer or check the app. Only continue if you trust this project and the download came from its release page.

After trying to open Stint once, you can use **System Settings → Privacy & Security → Open Anyway**, then confirm **Open** if you still want to run it. Follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445); labels can differ by macOS version. A managed Mac may prevent this exception.

A warning about damage or malware is different from an unidentified developer warning. Do not dismiss it as routine. Stop, download a fresh copy from the release page, and report the exact message if it persists. [Apple explains the different warnings](https://support.apple.com/en-us/102445).

## Optional checksum check

You can download `SHA256SUMS.txt` alongside your chosen archive and compare its listed SHA256 value with Terminal's output. For example, from the folder containing the DMG:

```sh
shasum -a 256 Stint-0.1.0-macos-universal.dmg
```

For the ZIP:

```sh
shasum -a 256 Stint-0.1.0-macos-universal.zip
```

The complete 64-character value should match the line for that filename in `SHA256SUMS.txt`. If it does not, download the archive again before opening it.

## Start your first session

Choose a rhythm and press **Start focus**. The countdown remains in the menu bar when you close the window. You can allow notifications when macOS asks and choose your alert in Settings. Music is optional; **Play with timer** starts and pauses your selected source with the timer.

Your timer, progress, and imported music stay local. YouTube links need an internet connection and a visible player inside the timer panel. See the [user guide](user-guide.md), [privacy notes](privacy.md), and [troubleshooting](troubleshooting.md) for details.

## Updates and removal

Stint does not yet have an automatic updater. You can check the [release page](https://github.com/albert2704/stint/releases), quit the running app, and replace it in Applications with the newer version. Review that version's release notes first.

The app retains the earlier `com.focusdesk.focusDesk` identity and `Focus Desk` data folder. Replacing the app bundle is intended to preserve existing local settings and history, but a manual upgrade has not yet been verified for this package. A copy of your local data is useful before trying a prerelease; see [data storage](architecture.md#persistence-and-compatibility).

To remove Stint, quit it and move the app from Applications to the Trash. Saved data may remain in its macOS container and preferences. Removing the app is not an erase-all-data action; see [privacy and local data](privacy.md#removing-data).
