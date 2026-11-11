# ShareMount

A tiny macOS **menu bar app** for connecting to SMB network shares. It lives in
the system tray: click a share's name to mount it, click again to disconnect.
Each share shows a ✓ when it's currently connected. Credentials are remembered
in the Keychain after the first connect, so later mounts are silent.

- Menu-bar-only agent — no Dock icon, stays out of the way.
- **Browse Network…** finds computers and file servers nearby, lists their
  shared folders and drives, and connects or adds them to the menu in one click.
- Add / edit / remove shares in a simple Preferences window.
- **Connect automatically**: per share, reconnects at launch, after wake, when
  the network comes back, and if the connection drops — using the saved password.
- Optional launch at login.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (to build)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the project file:
  `brew install xcodegen`

## Install (the easy way)

```sh
cd ShareMount
./install.sh
```

This builds a Release copy, puts it in **/Applications**, and launches it. Run
it again after pulling changes to update. It finds your Apple Team ID from the
"Apple Development" certificate Xcode created and saves it to
`Config/Signing.local.xcconfig` (not committed), so a stable signature is used
and the Keychain doesn't keep asking for permission after updates.

Then in **Preferences**, turn on **Launch at login**, and for each share save
its password and turn on **Connect automatically**.

## Build & run (for development)

```sh
cd ShareMount
xcodegen generate          # creates ShareMount.xcodeproj from project.yml
open ShareMount.xcodeproj  # then press ⌘R in Xcode
```

Signing uses the Team ID in `Config/Signing.local.xcconfig` (created by
`./install.sh`, or by hand with one line: `DEVELOPMENT_TEAM = ABCDE12345`).
Setting the Team in Xcode's **Signing & Capabilities** tab also works, but
`xcodegen generate` resets it; the xcconfig file doesn't get reset.

The bundle identifier is `io.github.jhdev01.ShareMount` (set in `project.yml`).
Change it there if you sign with a different identity — launch-at-login is
tied to it, so pick one and keep it.

## Tests

The share-location parsing and mount-matching logic is covered by unit tests
in `Tests/`. Run them with ⌘U in Xcode, or from the command line:

```sh
cd ShareMount
xcodegen generate
xcodebuild test -project ShareMount.xcodeproj -scheme ShareMount \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

GitHub Actions runs the same build and tests on every push and pull request
(`.github/workflows/build.yml`).

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
| "Is it connected?" | `getmntinfo` — parses each SMB device name and matches exact host + share name (`MountSource`) |
| Unmounting | `NSWorkspace.unmountAndEjectDevice(at:)` |
| Auto-connect | `AutoConnector`: at launch, on `NWPathMonitor` network-up, on wake, and every 2 min |
| Remembered credentials | Keychain internet-password items, keyed by host (`KeychainStore`) |
| Finding computers | Bonjour `_smb._tcp` browsing with `NetServiceBrowser` (`NetworkBrowser`) |
| Listing a computer's shares | `/usr/bin/smbutil view` — macOS has no public API for this (`ShareLister`) |
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

## Browsing the network

Choose **Browse Network…** (⌘B) from the menu bar icon.

- **Nearby** lists every computer advertising SMB file sharing: Macs with
  File Sharing turned on and most NAS boxes. The first time, macOS asks to let
  ShareMount find devices on your local network — click **Allow**. (If you
  missed it: System Settings → Privacy & Security → Local Network.)
- **Windows PCs** usually don't advertise themselves this way. Type the PC's
  name or IP address in the box under the list and press **Go**.
- Pick a computer to see its shared folders and drives. If it asks you to sign
  in, use an account on *that* computer; it's saved in your Keychain.
- **Connect** mounts a share now. **Add to Menu** saves it so it's one click
  from the menu bar next time.

**To reach a hard drive plugged into another Mac**, share it on that Mac
first: System Settings → General → Sharing → File Sharing (turn on) → ⓘ → **+**
under Shared Folders → choose the drive. It then shows up in Browse Network
like any other share.

When signing in, the username and password are passed to `smbutil` on its
command line, so for those few seconds they're visible to other processes on
your Mac (e.g. via `ps`). That's fine for a personal Mac; keep it in mind on a
shared one.

## Network location format

Any of these work for the **Network location** field:

```
smb://192.168.1.10/Media
192.168.1.10/Media
//nas.local/My Share
\\nas\Media
```

Share names may contain spaces; they're encoded automatically.
