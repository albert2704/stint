# Distraction blocking beta

Version 0.2.0 beta adds app blocking and a local website proxy. You can get the beta from [GitHub Releases](https://github.com/albert2704/stint/releases/tag/v0.2.0-beta.1). The earlier 0.1.1 download does not include these features.

## Set up

1. Open Settings → Block distractions, enable Block during focus, choose apps and enter website domains, then Save blocklist.
2. Choose Set up website blocker. Finder highlights Install Website Blocker.command inside Stint.
3. Double click the command in Finder. Read its explanation, type yes, and enter your administrator password in Terminal. Stint does not receive your password. This also upgrades the older hosts helper.
4. Return to Stint and choose Refresh. Helper ready means setup is available. During a running focus, the status confirms when proxy routing is active.

No browser extension, Apple Developer subscription or certificate installation is required. The downloaded app is not notarized; follow the [installation guide](install.md) for macOS first launch approval.

## What is blocked

Selected apps are hidden when you switch to them, preserving unsaved work. Chrome, Edge and recovery tools cannot be selected as blocked apps. Browsers remain open. Website entries cover the domain and its subdomains, so youtube.com also covers www.youtube.com and music.youtube.com.

During focus, the helper selects Stint's local HTTP/HTTPS proxy at 127.0.0.1:48197 for supported macOS network services. Allowed connections pass through; blocked destinations are refused. HTTPS remains encrypted between the browser and website. Stint does not inspect its contents, install a certificate or log browsing activity.

This is a cooperative focus aid for browsers using macOS proxy settings. Apps that ignore those settings, VPN configurations, existing custom proxies and PAC scripts are unsupported. Stint refuses to replace an existing enabled proxy. Loaded pages and buffered media can remain visible. Starting focus does not erase cached content or guarantee termination of a direct stream opened before routing changed. Refresh a page to check new access. HTTP supports port 80 and HTTPS tunnels port 443; unusual ports and plain HTTP streaming request bodies are unsupported.

Proxy settings affect all accounts using those network services, including Stint's YouTube music. Choose built in or local music when blocking YouTube. No network settings change until the updated helper is installed and a valid focus session is running.

## Stop or pause blocking

Pause, reset, skip, completion and breaks release blocking and restore previous proxy settings. Unblock this stint asks for confirmation and remains in effect if you pause and resume that interval. Your next focus uses the saved list again.

Stint closes handled tunnels when their destinations become blocked. If the app closes or crashes, the helper detects the missing local server on its next poll and restores routing. If the app stops sending timer updates, a maximum 30 second lease releases protection. The helper restarts after a crash and recovers its journal before applying a fresh focus policy. These mechanisms require the helper to run; they cannot recover a permanently disabled service.

## Remove or recover the helper

Choose Remove helper, double click the highlighted Remove Website Blocker.command in Finder, and complete its Terminal prompts. It stops the helper and restores only Stint's proxy changes. Saved app settings stay in place.

If Stint cannot open, the installed helper supports this emergency command in your own Terminal:

```sh
sudo /Library/PrivilegedHelperTools/io.github.albert2704.stint.hosts release
```

The legacy filename is retained to upgrade the previous helper without installing a second service. The new helper clears old Stint hosts entries during installation and recovery; it does not add hosts entries during focus. Run setup again to enable the helper after emergency release.

If the helper cannot run and web access fails, open System Settings → Network → your active service → Details → Proxies. Disable only Web Proxy (HTTP) and Secure Web Proxy (HTTPS) entries whose server is 127.0.0.1 and port is 48197, then apply. Repeat only for services carrying those Stint values. Do not reset unrelated proxies or delete the recovery journal. The helper keeps a root owned journal at /Library/Application Support/StintHosts/proxy-recovery.plist and uses it to restore the original values when it can run again.

External edits are preserved. If network settings change while focus is running, Stint releases its remaining settings and reports the conflict instead of repeatedly overwriting them. Start a new focus after resolving the conflict.

## Verification status

See [testing](testing.md#version-020-beta-verification) for the actual checks performed. Live Edge checks verified blocked YouTube navigation, allowed GitHub navigation and access returning on pause. App crash recovery restored the saved proxy settings. Chrome was not installed and remains unverified. The previous hosts approach was replaced after it failed to block an existing Edge session reliably.
