#!/system/bin/sh
# GPS Locker - shared helpers (sourced by service.sh, gpslocker.sh, uninstall.sh)

PKG=io.github.nikakvo.gpslocker
SVC=$PKG/.LockService
TRAMPOLINE=$PKG/.ToggleActivity
DATA_DIR=/data/adb/gps-locker
CONFIG=$DATA_DIR/config.conf
LOG=$DATA_DIR/gps-locker.log
THROTTLE_KEY=location_background_throttle_package_whitelist
THROTTLE_ORIG=$DATA_DIR/throttle_whitelist.orig
LOCKED_KEY=locked_apps

# Default navigation apps exempted from Android's background location throttling
DEFAULT_NAV_APPS="net.osmand.plus net.osmand com.waze com.sygic.aura com.google.android.apps.maps"

# Navigation apps the WebUI offers when they are installed
KNOWN_NAV_APPS="net.osmand.plus net.osmand app.organicmaps app.comaps com.waze com.google.android.apps.maps com.sygic.aura com.here.app.maps com.generalmagic.magicearth menion.android.locus menion.android.locus.pro com.tomtom.gplay.navapp ru.yandex.yandexnavi com.huawei.maps.app"

log() {
    mkdir -p "$DATA_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
    # keep the log small
    if [ "$(wc -l < "$LOG" 2>/dev/null)" -gt 500 ] 2>/dev/null; then
        tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}

ensure_config() {
    mkdir -p "$DATA_DIR"
    if [ ! -f "$CONFIG" ]; then
        cat > "$CONFIG" <<EOF
# GPS Locker settings
# Lock the GPS automatically after boot (0/1)
BOOT_LOCK=0
# Navigation apps that keep getting GPS updates in the background (space separated)
NAV_APPS="$DEFAULT_NAV_APPS"
EOF
    fi
}

load_config() {
    ensure_config
    BOOT_LOCK=0
    NAV_APPS="$DEFAULT_NAV_APPS"
    . "$CONFIG"
}

set_config() {
    # set_config KEY VALUE
    ensure_config
    if grep -q "^$1=" "$CONFIG"; then
        sed -i "s|^$1=.*|$1=$2|" "$CONFIG"
    else
        echo "$1=$2" >> "$CONFIG"
    fi
}

is_installed() {
    pm path "$PKG" >/dev/null 2>&1
}

# install_app <apk>: install or update the companion app as a normal app
install_app() {
    tmp=/data/local/tmp/gpslocker-install.apk
    cp "$1" "$tmp" && chmod 644 "$tmp" || return 1
    out=$(pm install -r -g "$tmp" 2>&1)
    rm -f "$tmp"
    case "$out" in *Success*) return 0 ;; *) log "install failed: $out"; return 1 ;; esac
}

# Opens the app's system settings page (HyperOS keeps its own permission state
# that only this screen can change)
open_permissions() {
    am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$PKG" >/dev/null 2>&1
}

PERMISSION_HINT="Allow Location \"All the time\" and Notifications, then come back."

# Runtime permissions, app ops, battery and HyperOS exemptions.
# Safe to run any number of times.
grant_all() {
    for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION POST_NOTIFICATIONS; do
        pm grant "$PKG" "android.permission.$p" 2>/dev/null
    done
    for op in COARSE_LOCATION FINE_LOCATION POST_NOTIFICATION RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND; do
        appops set "$PKG" "$op" allow 2>/dev/null
    done
    # HyperOS keeps UID-level modes too; the UID mode wins over the package mode
    for op in COARSE_LOCATION FINE_LOCATION POST_NOTIFICATION; do
        appops set --uid "$PKG" "$op" allow 2>/dev/null
    done
    # MIUI autostart
    appops set "$PKG" 10008 allow 2>/dev/null

    dumpsys deviceidle whitelist +"$PKG" >/dev/null 2>&1

    # HyperOS / MIUI: lock the app like "lock in recents", so "Clear all" leaves it alone
    lock_in_recents

    # Xiaomi Millet: never freeze the app in the background
    cur=$(settings get system MILLET_NO_RESTRICT_APP 2>/dev/null)
    case "$cur" in
        *"$PKG"*) ;;
        ""|null) settings put system MILLET_NO_RESTRICT_APP "$PKG" 2>/dev/null ;;
        *) settings put system MILLET_NO_RESTRICT_APP "$cur, $PKG" 2>/dev/null ;;
    esac
}

# HyperOS / MIUI keep the apps locked in recents in "settings system locked_apps":
#   [{"u":0,"pkgs":["com.termux"]},{"u":-100,"pkgs":[...]}]
# ProcessManager reads the list at boot; "Clear all" (OneKeyClean) skips those apps.
lock_in_recents() {
    cur=$(settings get system "$LOCKED_KEY" 2>/dev/null)
    case "$cur" in
        *"\"$PKG\""*) return 0 ;;
        ""|null) new="[{\"u\":0,\"pkgs\":[\"$PKG\"]}]" ;;
        *'{"u":0,"pkgs":[]}'*) new=$(echo "$cur" | sed "s|{\"u\":0,\"pkgs\":\\[\\]}|{\"u\":0,\"pkgs\":[\"$PKG\"]}|") ;;
        *'{"u":0,"pkgs":['*) new=$(echo "$cur" | sed "s|{\"u\":0,\"pkgs\":\\[|{\"u\":0,\"pkgs\":[\"$PKG\",|") ;;
        *) new=$(echo "$cur" | sed "s|^\\[|[{\"u\":0,\"pkgs\":[\"$PKG\"]},|") ;;
    esac
    settings put system "$LOCKED_KEY" "$new" 2>/dev/null
}

unlock_in_recents() {
    cur=$(settings get system "$LOCKED_KEY" 2>/dev/null)
    case "$cur" in
        *"\"$PKG\""*)
            new=$(echo "$cur" | sed "s|\"$PKG\",||; s|,\"$PKG\"||; s|\"$PKG\"||")
            settings put system "$LOCKED_KEY" "$new" 2>/dev/null
            ;;
    esac
}

# Is the app in ProcessManager's live locked list (survives "Clear all")?
# Prints yes, no, or n/a when the ROM has no such list.
recents_locked() {
    lo=$(dumpsys ProcessManager 2>/dev/null | sed -n '/^LO:/,/^[A-Z]/p')
    if [ -z "$lo" ]; then echo n/a
    elif echo "$lo" | grep -q "^ *$PKG\$"; then echo yes
    else echo no
    fi
}

# Reports which permissions are really effective: "ok" or a list of problems
check_access() {
    problems=""
    for op in FINE_LOCATION POST_NOTIFICATION; do
        m="$(appops get --uid "$PKG" "$op" 2>/dev/null) $(appops get "$PKG" "$op" 2>/dev/null)"
        case "$m" in
            *ignore*|*deny*|*errored*) problems="$problems $op" ;;
        esac
    done
    [ -z "$problems" ] && echo ok || echo "blocked:$problems"
}

# Merge the configured nav apps into Android's background throttle whitelist
apply_nav_apps() {
    load_config
    cur=$(settings get global "$THROTTLE_KEY" 2>/dev/null)
    [ "$cur" = "null" ] && cur=""
    # remember what the system had before we touched it, once
    [ -f "$THROTTLE_ORIG" ] || echo "$cur" > "$THROTTLE_ORIG"
    orig=$(cat "$THROTTLE_ORIG")

    list="$orig"
    for app in $NAV_APPS; do
        pm path "$app" >/dev/null 2>&1 || continue
        case ",$list," in
            *",$app,"*) ;;
            *) list="${list:+$list,}$app" ;;
        esac
    done
    if [ -n "$list" ]; then
        settings put global "$THROTTLE_KEY" "$list"
    else
        settings delete global "$THROTTLE_KEY" >/dev/null 2>&1
    fi
}

restore_nav_apps() {
    if [ -f "$THROTTLE_ORIG" ]; then
        orig=$(cat "$THROTTLE_ORIG")
        if [ -n "$orig" ]; then
            settings put global "$THROTTLE_KEY" "$orig"
        else
            settings delete global "$THROTTLE_KEY" >/dev/null 2>&1
        fi
    fi
}

status_json() {
    out=$(dumpsys activity service "$SVC" 2>/dev/null | grep -o '{.*}' | tail -n1)
    [ -n "$out" ] && echo "$out" || echo '{"running":false}'
}

is_running() {
    status_json | grep -q '"running":true'
}
