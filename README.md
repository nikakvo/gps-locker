<p align="center"><img src="assets/banner.png" alt="GPS Locker" width="100%"></p>

# GPS Locker

A root module that keeps the GPS receiver locked on its satellites while you switch between
navigation apps. Leave Google Maps for a message, come back a minute later and the position is
already there - no new search for satellites.

Android switches the GPS receiver off as soon as no app asks for a position, and some ROMs
(HyperOS, MIUI) cut it even faster to save power. GPS Locker holds the receiver on while you need
it, so every app that asks for a position gets one at once: Google Maps, OsmAnd, Waze, Sygic and
anything else.

## Features

- **Quick Settings tile** - one tap to lock, one tap to release. The subtitle shows the live
  satellite count (`14/22 sats`).
- **Live notification** - satellites in the fix, accuracy, how many have L5, and a count per
  system (GPS, GLONASS, BeiDou, Galileo).
- **WebUI** - big lock button, live stats, sky plot, signal bars per satellite, A-GPS refresh and
  cold reset, navigation app list, lock after boot, built-in help.
- **Action button** in the root manager toggles the lock.
- **Background throttling exemption** for your navigation apps, so they keep getting positions
  while they are not on screen.
- **Survives "Clear all"** on HyperOS / MIUI - the app is locked the same way as a card locked in
  recents.
- **HyperOS / MIUI aware** - detects when the system silently blocks location or notifications
  for the app and opens the one settings page that fixes it.
- Talks to the GPS chip directly, not through Google Play services. Works with or without them.
- Does **not** replace `gps.conf`. The vendor file is tuned for your chip.

The companion app has no icon, no screen and no internet permission. It is only a background
service, the tile and the notification.

## Requirements

| | |
|---|---|
| Root | SukiSU Ultra or KernelSU (WebUI built in). Magisk works too - open the WebUI with MMRL or KSU WebUI Standalone. |
| Android | 12 or newer |
| GPS | Any chip. Dual-frequency (L1 + L5) chips show both bands. |

Tested on a Poco F6 Pro with HyperOS 3 (Android 16). Other devices should work, but they have not
been tested.

## Install

1. Download `GPSLocker-vX.Y.Z.zip` from [Releases](https://github.com/nikakvo/gps-locker/releases)
   and flash it in your root manager. The companion app is installed at the same time.
2. Reboot.
3. Quick Settings -> Edit -> add the **GPS Locker** tile.
4. Tap the tile. The notification shows the satellites.

**HyperOS / MIUI:** the system may block location for a newly installed app without any error.
The WebUI then shows a warning, and the Action button opens the right settings page. Allow
Location **All the time** and **Notifications** once.

## Command line

```sh
su -c '/data/adb/modules/gps-locker/gpslocker.sh help'
su -c '/data/adb/modules/gps-locker/gpslocker.sh start'
su -c '/data/adb/modules/gps-locker/gpslocker.sh stop'
su -c '/data/adb/modules/gps-locker/gpslocker.sh status'
su -c '/data/adb/modules/gps-locker/gpslocker.sh check'
```

Settings and the log live in `/data/adb/gps-locker/`.

## Battery

The GPS receiver uses power while it is locked. Switch the lock on when you drive or travel and
off when you arrive.

## Building

The module is built on Linux / WSL with `build.sh`. It builds and signs the companion app, then
packs the module zip into `dist/`.

Requirements: JDK 17, Android SDK with build-tools 36.0.0 (`ANDROID_HOME`, default
`~/android-sdk`), `zip`, and a keystore.

```sh
git clone https://github.com/nikakvo/gps-locker.git
cd gps-locker
KEYSTORE=~/keys/my.jks KEY_ALIAS=mykey bash build.sh
```

`PASS_FILE` can point to a file (chmod 600) with the keystore password; otherwise `apksigner`
asks for it. If the project has no Gradle wrapper script yet, `build.sh` copies one from another
local project (edit `WRAP_SRC`) - or run `gradle wrapper` once.

## License

[MIT](LICENSE) - Tears Burn (nikakvo)
