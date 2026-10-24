package io.github.nikakvo.gpslocker;

import android.app.Activity;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * Invisible trampoline. Android 14+ only lets a location foreground service go
 * foreground while the app itself is in the foreground, so the tile and the shell
 * start the lock through this activity. It stays (invisibly) open until the service
 * reports that startForeground() went through, then closes.
 *
 * Shell: am start -n io.github.nikakvo.gpslocker/.ToggleActivity -a io.github.nikakvo.gpslocker.START
 * Actions: START, STOP or TOGGLE (default).
 */
public final class ToggleActivity extends Activity {

    private static final long MAX_WAIT_MS = 3000L;

    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String action = getIntent() != null ? getIntent().getAction() : null;
        boolean turnOn;
        if (LockService.ACTION_START.equals(action)) {
            turnOn = true;
        } else if (LockService.ACTION_STOP.equals(action)) {
            turnOn = false;
        } else {
            turnOn = !LockService.sRunning;
        }

        if (!turnOn) {
            if (LockService.sRunning) {
                try {
                    startService(new Intent(this, LockService.class).setAction(LockService.ACTION_STOP));
                } catch (RuntimeException e) {
                    Log.e(LockService.TAG, "Stop failed", e);
                }
            }
            close();
            return;
        }

        if (LockService.sRunning) {
            close();
            return;
        }
        pendingStart = true;
    }

    private boolean pendingStart;

    @Override
    protected void onResume() {
        super.onResume();
        if (!pendingStart) return;
        pendingStart = false;

        // Resumed = fully in the foreground. Stay here until the service went foreground.
        LockService.sStartWaiter = this::close;
        main.postDelayed(this::close, MAX_WAIT_MS);
        try {
            startForegroundService(new Intent(this, LockService.class).setAction(LockService.ACTION_START));
        } catch (RuntimeException e) {
            Log.e(LockService.TAG, "Start failed", e);
            LockService.sStartWaiter = null;
            close();
        }
    }

    private void close() {
        main.removeCallbacksAndMessages(null);
        if (isFinishing() || isDestroyed()) return;
        // Remove the task too, so no empty task is left behind in recents
        finishAndRemoveTask();
        if (Build.VERSION.SDK_INT >= 34) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0);
        } else {
            overridePendingTransition(0, 0);
        }
    }

    @Override
    protected void onDestroy() {
        main.removeCallbacksAndMessages(null);
        if (LockService.sStartWaiter != null) LockService.sStartWaiter = null;
        super.onDestroy();
    }
}
