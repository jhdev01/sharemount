# ShareMount

A tiny macOS **menu bar app** for connecting to SMB network shares. It lives in
the system tray: click a share's name to mount it, click again to disconnect.
Each share shows a ✓ when it's currently connected. Credentials are remembered
in the Keychain after the first connect, so later mounts are silent.

- Menu-bar-only agent — no Dock icon, stays out of the way.
- Add / edit / remove shares in a simple Preferences window.
- Optional launch at login.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (to build)
- [XcodeGen](https://github.com/yonyz/XcodeGen) to generate the project file:
  `brew install xcodegen`

## Build & run

```sh
cd ShareMount
xcodegen generate          # creates ShareMount.xcodeproj from project.yml
open ShareMount.xcodeproj  # then press ⌘R in Xcode
```

In Xcode, select your development team under
**Target → Signing & Capabilities** (Automatic signing) before running.

> **Don't have XcodeGen?** You can build by hand instead: create a new macOS
> **App** project in Xcode (language: Swift, interface: AppKit/XIB — it doesn't
> matter, the storyboard is deleted), remove the template `AppDelegate`/
> `main`/storyboard, drag the `Sources/` folder in, set **Info.plist** to
> `Sources/Info.plist`, add a `LSUIElement = YES` key, link the **NetFS** and
> **ServiceManagement** frameworks, and set the deployment target to macOS 13.

## How it works

| Concern | Implementation |
| --- | --- |
| Menu bar item + dynamic menu | `NSStatusItem` / `NSMenu`, rebuilt on open (`StatusItemController`) |
| Mounting SMB | `NetFSMountURLSync` from the NetFS framework (`MountManager`) |
| "Is it connected?" | `getmntinfo` — matches mounted devices by host + share name |
| Unmounting | `NSWorkspace.unmountAndEjectDevice(at:)` |
| Remembered credentials | Keychain internet-password items, keyed by host (`KeychainStore`) |
| Add/edit/remove shares | SwiftUI `PreferencesView` in a hosted `NSWindow` |
| Launch at login | `SMAppService.mainApp.register()` (`LoginItem`) |
| No Dock icon | `LSUIElement` + `NSApp.setActivationPolicy(.accessory)` |

Shares are stored as JSON in `UserDefaults`. Passwords are **never** stored
there — only in the Keychain.

## Notes & limitations

- **Not sandboxed.** Mounting arbitrary network shares isn't permitted inside
  the App Sandbox, so this is a personal/internal tool, not an App Store build.
- **Launch at login** is most reliable when the app lives in `/Applications`.
  macOS may show the toggle under System Settings → General → Login Items.
- Connection state refreshes when you open the menu (it's read from the
  kernel's mount table, not a live socket).
- First connect shows a username/password prompt; after a successful mount the
  credentials are saved to the Keychain and reused silently.

## Network location format

Either of these works for the **Network location** field:

```
smb://192.168.1.10/Media
192.168.1.10/Media
```
