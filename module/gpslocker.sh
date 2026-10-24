#!/system/bin/sh
# GPS Locker - command line control (run as root)
#
#   su -c '/data/adb/modules/gps-locker/gpslocker.sh help'

MODDIR=${0%/*}
. "$MODDIR/common.sh"

usage() {
    cat <<EOF
GPS Locker

  start              Lock the GPS
  stop               Release the GPS
  toggle             Lock or release
  status             Live status as JSON
  agps               Refresh assistance data (XTRA orbits and time)
  reset              Cold start: delete assistance data, then refresh it
  fix                Re-apply permissions and exemptions
  check              Show whether location and notifications are really allowed
  permissions        Open the app's system settings page (HyperOS permissions)
  navapps            List the navigation apps exempt from background throttling
  navapps set "a b"  Replace that list (package names, space separated)
  bootlock on|off    Lock the GPS automatically after boot
EOF
}

case "$1" in
start)
    am start -n "$TRAMPOLINE" -a "$PKG.START" >/dev/null 2>&1 && echo "GPS lock starting"
    ;;
stop)
    am start -n "$TRAMPOLINE" -a "$PKG.STOP" >/dev/null 2>&1 && echo "GPS lock stopped"
    ;;
toggle)
    if is_running; then "$0" stop; else "$0" start; fi
    ;;
status)
    status_json
    ;;
info)
    # Settings and environment for the WebUI, as JSON
    load_config
    ver=$(sed -n 's/^version=//p' "$MODDIR/module.prop")
    pkgs=" $(pm list packages 2>/dev/null | sed 's/^package://' | tr '\n' ' ') "
    case "$pkgs" in *" $PKG "*) app=true ;; *) app=false ;; esac
    printf '{"version":"%s","access":"%s","boot_lock":%s,"app":%s,"nav":[' \
        "$ver" "$(check_access)" "${BOOT_LOCK:-0}" "$app"
    seen=" "
    first=1
    for a in $KNOWN_NAV_APPS $NAV_APPS; do
        case "$seen" in *" $a "*) continue ;; esac
        seen="$seen$a "
        case "$pkgs" in *" $a "*) inst=true ;; *) inst=false ;; esac
        case " $NAV_APPS " in *" $a "*) en=true ;; *) en=false ;; esac
        [ "$inst" = true ] || [ "$en" = true ] || continue
        [ $first = 1 ] || printf ','
        first=0
        printf '{"pkg":"%s","installed":%s,"enabled":%s}' "$a" "$inst" "$en"
    done
    printf ']}\n'
    ;;
agps)
    cmd location providers send-extra-command gps force_time_injection
    cmd location providers send-extra-command gps force_psds_injection
    log "agps: refresh requested"
    echo "Assistance data refresh requested"
    ;;
reset)
    cmd location providers send-extra-command gps delete_aiding_data
    sleep 1
    cmd location providers send-extra-command gps force_time_injection
    cmd location providers send-extra-command gps force_psds_injection
    log "reset: cold start requested"
    echo "Assistance data deleted and refresh requested (next fix is a cold start)"
    ;;
fix)
    grant_all
    apply_nav_apps
    echo "access: $(check_access)"
    ;;
permissions)
    open_permissions
    echo "$PERMISSION_HINT"
    ;;
check)
    a=$(check_access)
    echo "access: $a"
    [ "$a" = "ok" ] || echo "fix: su -c '/data/adb/modules/gps-locker/gpslocker.sh permissions'"
    echo "installed: $(pm path "$PKG" 2>/dev/null | sed 's/package://')"
    echo "throttle whitelist: $(settings get global "$THROTTLE_KEY")"
    echo "locked in recents: $(recents_locked)"
    ;;
navapps)
    if [ "$2" = "set" ]; then
        set_config NAV_APPS "\"$3\""
        apply_nav_apps
    fi
    load_config
    for app in $NAV_APPS; do
        if pm path "$app" >/dev/null 2>&1; then echo "$app installed"; else echo "$app not installed"; fi
    done
    ;;
bootlock)
    case "$2" in
        on) set_config BOOT_LOCK 1; echo "Boot lock on" ;;
        off) set_config BOOT_LOCK 0; echo "Boot lock off" ;;
        *) load_config; echo "Boot lock: $BOOT_LOCK" ;;
    esac
    ;;
*)
    usage
    ;;
esac
