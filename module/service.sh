#!/system/bin/sh
# GPS Locker - runs at every boot

MODDIR=${0%/*}
. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
# give the package manager and HyperOS security center time to settle
sleep 10

ensure_config
log "boot: module start"

# Reinstall the companion app if it was removed, or if the module ships a newer one
if ! is_installed; then
    if install_app "$MODDIR/GPSLocker.apk"; then
        log "boot: companion app reinstalled"
    else
        log "boot: companion app missing and reinstall failed"
        exit 0
    fi
fi

grant_all
apply_nav_apps
log "boot: permissions applied, access=$(check_access)"

# HyperOS may reapply its own restrictions a bit later, so grant once more
sleep 30
grant_all
log "boot: second pass, access=$(check_access)"

load_config
if [ "$BOOT_LOCK" = "1" ]; then
    am start -n "$TRAMPOLINE" -a "$PKG.START" >/dev/null 2>&1
    log "boot: GPS lock started (BOOT_LOCK=1)"
fi
