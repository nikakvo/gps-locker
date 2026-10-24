#!/system/bin/sh
# GPS Locker - installer

SKIPUNZIP=0
PKG=io.github.nikakvo.gpslocker

ui_print "- GPS Locker"

API=$(getprop ro.build.version.sdk)
if [ "$API" -lt 31 ]; then
    abort "! Android 12 (API 31) or newer is required, this device is API $API"
fi

APK="$MODPATH/GPSLocker.apk"
[ -f "$APK" ] || abort "! GPSLocker.apk is missing from the module"

# The companion app is installed as a normal app. A system-app overlay does not
# work with root managers that unmount modules for apps (KernelSU / SukiSU),
# because SystemUI and the app itself could not read the APK.
ui_print "- Installing the companion app"
TMP_APK=/data/local/tmp/gpslocker-install.apk
cp "$APK" "$TMP_APK" && chmod 644 "$TMP_APK"
OUT=$(pm install -r -g "$TMP_APK" 2>&1)
rm -f "$TMP_APK"
case "$OUT" in
    *Success*) ui_print "  installed" ;;
    *) abort "! App install failed: $OUT" ;;
esac

# All module data lives in one folder
mkdir -p /data/adb/gps-locker
. "$MODPATH/common.sh"
ensure_config
grant_all

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in gpslocker.sh service.sh action.sh uninstall.sh; do
    set_perm "$MODPATH/$f" 0 0 0755
done

ui_print "- Done. Add the GPS Locker tile in Quick Settings."
ui_print "  HyperOS: the first time, press Action once to allow location."
