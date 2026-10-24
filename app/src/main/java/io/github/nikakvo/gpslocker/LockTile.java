package io.github.nikakvo.gpslocker;

import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/** Quick Settings tile: one tap locks the GPS, the next tap releases it. */
public final class LockTile extends TileService {

    /** The tile while the Quick Settings panel shows it, so the service can redraw it live. */
    private static volatile LockTile sListening;

    /**
     * Redraws the tile from any thread. While the panel is open the tile is already
     * listening and requestListeningState() is ignored, so we redraw the live instance.
     */
    static void refresh(Context ctx) {
        LockTile t = sListening;
        if (t != null) {
            new Handler(Looper.getMainLooper()).post(t::render);
            return;
        }
        try {
            requestListeningState(ctx, new ComponentName(ctx, LockTile.class));
        } catch (RuntimeException ignored) {
            // Tile not added by the user, nothing to refresh
        }
    }

    @Override
    public void onTileAdded() {
        render();
    }

    @Override
    public void onStartListening() {
        sListening = this;
        render();
    }

    @Override
    public void onStopListening() {
        if (sListening == this) sListening = null;
    }

    @Override
    public void onDestroy() {
        if (sListening == this) sListening = null;
        super.onDestroy();
    }

    @Override
    public void onClick() {
        if (LockService.sRunning) {
            // Stopping needs no foreground state, the app already runs a foreground service
            try {
                startService(new Intent(this, LockService.class).setAction(LockService.ACTION_STOP));
                show(false);
            } catch (RuntimeException e) {
                Log.e(LockService.TAG, "Tile stop failed", e);
            }
            return;
        }
        // Starting goes through the foreground trampoline
        Intent i = new Intent(this, ToggleActivity.class)
                .setAction(LockService.ACTION_START)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
        Runnable launch = () -> launch(i);
        if (isLocked()) {
            unlockAndRun(launch);
        } else {
            launch.run();
        }
    }

    @SuppressWarnings("deprecation")
    private void launch(Intent i) {
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, i,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT));
        } else {
            startActivityAndCollapse(i);
        }
    }

    private void render() {
        show(LockService.sRunning);
    }

    private void show(boolean on) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.setLabel("GPS Locker");
        String sub;
        if (!on) {
            sub = "Off";
        } else if (LockService.sUsed > 0) {
            sub = LockService.sUsed + "/" + LockService.sVisible + " sats";
        } else {
            sub = "Searching";
        }
        t.setSubtitle(sub);
        t.updateTile();
    }
}
