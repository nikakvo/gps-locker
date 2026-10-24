#!/system/bin/sh
# GPS Locker - Action button in the root manager: lock or release the GPS

MODDIR=${0%/*}
. "$MODDIR/common.sh"

if ! is_installed; then
    echo "Companion app missing, reinstalling..."
    install_app "$MODDIR/GPSLocker.apk" || { echo "Install failed, see /data/adb/gps-locker/gps-locker.log"; exit 1; }
    grant_all
fi

if is_running; then
    echo "Releasing the GPS..."
    am start -n "$TRAMPOLINE" -a "$PKG.STOP" >/dev/null 2>&1
    echo "GPS Locker is off"
    exit 0
fi

grant_all
access=$(check_access)
if [ "$access" != "ok" ]; then
    echo "The system still blocks GPS Locker ($access)."
    echo "Opening its settings page:"
    echo "$PERMISSION_HINT"
    echo "Then press Action again."
    open_permissions
    exit 0
fi

echo "Locking the GPS..."
am start -n "$TRAMPOLINE" -a "$PKG.START" >/dev/null 2>&1
i=0
while [ $i -lt 20 ]; do
    sleep 1
    i=$((i + 1))
    st=$(status_json)
    used=$(echo "$st" | sed -n 's/.*"used":\([0-9]*\).*/\1/p')
    vis=$(echo "$st" | sed -n 's/.*"visible":\([0-9]*\).*/\1/p')
    if [ -n "$used" ] && [ "$used" -gt 0 ]; then
        echo "Locked: $used/$vis satellites"
        exit 0
    fi
done
if is_running; then
    echo "GPS Locker is on, still searching for satellites"
else
    echo "GPS Locker did not start, see: su -c '/data/adb/modules/gps-locker/gpslocker.sh check'"
fi
