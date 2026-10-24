#!/system/bin/sh
# GPS Locker - cleanup when the module is removed

MODDIR=${0%/*}
. "$MODDIR/common.sh"

am force-stop "$PKG" 2>/dev/null
dumpsys deviceidle whitelist -"$PKG" >/dev/null 2>&1

cur=$(settings get system MILLET_NO_RESTRICT_APP 2>/dev/null)
case "$cur" in
    *"$PKG"*)
        new=$(echo "$cur" | sed "s/, *$PKG//; s/$PKG, *//; s/$PKG//")
        if [ -n "$new" ]; then
            settings put system MILLET_NO_RESTRICT_APP "$new"
        else
            settings delete system MILLET_NO_RESTRICT_APP >/dev/null 2>&1
        fi
        ;;
esac

unlock_in_recents
restore_nav_apps
pm uninstall "$PKG" >/dev/null 2>&1
rm -rf "$DATA_DIR"
