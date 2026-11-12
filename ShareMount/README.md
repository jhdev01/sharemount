# ShareMount

A small macOS **menu bar app** that keeps drives from other computers (SMB
shares — other Macs, NAS boxes, Windows PCs) connected.

- **Menu bar panel** — every drive, grouped by computer, with its status in
  plain words ("Connected · 3.2 TB free", "Password needed", "Server asleep…")
  and the button you need right there: Open, Disconnect, Retry, Sign In.
  The menu bar icon gets a warning badge when a drive needs attention.
- **Keep connected** (on by default) — connects at login, after sleep, when the
  network comes back, and every minute while a drive is unavailable, using the
  password saved in your Keychain. Never pops up prompts on its own.
- **Add a Drive** — finds computers on your network, lists what each shares,
  and adds the ones you tick.
- **Settings** — per-drive page (name, location, Keep connected, password) and
  General (open at login).
- Opens at login by default. No Dock icon.

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

On first launch, **Add a Drive** opens: pick the computer, sign in, tick the
drives. They stay connected from then on, including after restarts.

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
| Menu bar icon + panel | `NSStatusItem` + `NSPopover` hosting SwiftUI `MenuPanelView` (`StatusItemController`) |
| Drive status | `ConnectionManager` publishes a `DriveState` per drive from the mount table (refreshed every 5 s and on mount/unmount) |
| Mounting SMB | `NetFSMountURLSync` from the NetFS framework (`MountManager`) |
| "Is it connected?" | `getmntinfo` — parses each SMB device name and matches exact host + share name (`MountSource`) |
| Unmounting | `NSWorkspace.unmountAndEjectDevice(at:)` |
| Keep connected | `ConnectionManager`: at launch, on `NWPathMonitor` network-up, on wake, and every 60 s |
| Remembered credentials | Keychain internet-password items, keyed by host (`KeychainStore`) |
| Finding computers | Bonjour `_smb._tcp` browsing with `NetServiceBrowser` (`NetworkBrowser`) |
| Listing a computer's shares | `/usr/bin/smbutil view` — macOS has no public API for this (`ShareLister`) |
| Add a Drive | `AddDriveView` + `AddDriveModel` |
| Settings | SwiftUI `NavigationSplitView` (`SettingsView`, `DriveDetailView`, `GeneralSettingsView`) |
| Launch at login | `SMAppService.mainApp.register()` (`LoginItem`) |
| No Dock icon | `LSUIElement` + `NSApp.setActivationPolicy(.accessory)` |

Shares are stored as JSON in `UserDefaults`. Passwords are **never** stored
there — only in the Keychain.

## Notes & limitations

- **Not sandboxed.** Mounting arbitrary network shares isn't permitted inside
  the App Sandbox, so this is a personal/internal tool, not an App Store build.
- **Launch at login** is most reliable when the app lives in `/Applications`.
  macOS may show the toggle under System Settings → General → Login Items.
- Connection state comes from the kernel's mount table, so a server that
  vanished without unmounting can still show as connected until macOS notices.
- Passwords are per computer: one saved password is used for every drive on it.

## Adding a drive

Choose **Add a Drive…** (⌘N) from the menu bar panel or Settings.

- **On your network** lists every computer advertising SMB file sharing: Macs with
  File Sharing turned on and most NAS boxes. The first time, macOS asks to let
  ShareMount find devices on your local network — click **Allow**. (If you
  missed it: System Settings → Privacy & Security → Local Network.)
- **Windows PCs** usually don't advertise themselves this way. Type the PC's
  name or IP address in the box under the list and press **Go**.
- Pick a computer to see its shared folders and drives. If it asks you to sign
  in, use an account on *that* computer; it's saved in your Keychain.
- Tick the drives you want and click **Add**. With **Keep these connected
  automatically** on (the default) they connect right away and stay connected.

**To reach a hard drive plugged into another Mac**, share it on that Mac
first: System Settings → General → Sharing → File Sharing (turn on) → ⓘ → **+**
under Shared Folders → choose the drive. It then shows up in Add a Drive
like any other share.

When signing in, the username and password are passed to `smbutil` on its
command line, so for those few seconds they're visible to other processes on
your Mac (e.g. via `ps`). That's fine for a personal Mac; keep it in mind on a
shared one.

## Network location format

Any of these work for a drive's **Location** (Settings → drive → Change…):

```
smb://192.168.1.10/Media
192.168.1.10/Media
//nas.local/My Share
\\nas\Media
```

Share names may contain spaces; they're encoded automatically.
