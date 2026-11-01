# Changelog

## v1.0.1

- WebUI: opens fast again on a quick reopen. The status no longer shows "off" for a few seconds, and the version, navigation apps and "lock after boot" switch no longer stay empty.

## v1.0.0

First release.

- Keeps the GPS receiver locked on its satellites while you switch between navigation apps.
- Quick Settings tile with the live satellite count.
- Live notification: satellites in the fix, accuracy, L5 satellites, count per system.
- WebUI: lock button, live stats, sky plot, signal bars, A-GPS refresh, cold reset, navigation
  apps, lock after boot, help.
- Action button toggles the lock.
- Navigation apps keep getting positions in the background (throttling exemption).
- HyperOS / MIUI: "Clear all" in recents no longer stops the lock.
- Detects when HyperOS / MIUI blocks location or notifications and opens the settings page that
  fixes it.
