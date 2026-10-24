package io.github.nikakvo.gpslocker;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.graphics.drawable.Icon;
import android.location.GnssStatus;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.location.LocationRequest;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.FileDescriptor;
import java.io.PrintWriter;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.Executor;

/**
 * Keeps the GNSS engine running with a permanent 1 Hz high-accuracy GPS request,
 * so the chip never drops its satellites while navigation apps come and go.
 *
 * Control (root shell), always through the foreground trampoline:
 *   am start -n io.github.nikakvo.gpslocker/.ToggleActivity -a io.github.nikakvo.gpslocker.START
 *   am start -n io.github.nikakvo.gpslocker/.ToggleActivity -a io.github.nikakvo.gpslocker.STOP
 * Status as JSON (root shell):
 *   dumpsys activity service io.github.nikakvo.gpslocker/.LockService
 */
public final class LockService extends Service {

    static final String TAG = "GPSLocker";
    static final String ACTION_START = "io.github.nikakvo.gpslocker.START";
    static final String ACTION_STOP = "io.github.nikakvo.gpslocker.STOP";

    private static final String CHANNEL_ID = "gps_lock";
    private static final int NOTIF_ID = 1;
    private static final long INTERVAL_MS = 1000L;
    private static final long FIX_STALE_MS = 5000L;

    /** Constellation short names, indexed by GnssStatus.CONSTELLATION_* */
    private static final String[] CONST_NAMES = {"UNK", "GPS", "SBAS", "GLO", "QZSS", "BDS", "GAL", "NavIC"};

    /** Shared with the Quick Settings tile (same process). */
    static volatile boolean sRunning;
    static volatile int sUsed;
    static volatile int sVisible;
    static volatile int sL5;
    /** Set by ToggleActivity: run on the main thread once startForeground() was attempted. */
    static Runnable sStartWaiter;

    private LocationManager lm;
    private NotificationManager nm;
    private HandlerThread thread;
    private Handler handler;
    private Executor executor;

    private boolean locking;
    private volatile Location lastFix;
    private volatile long lastFixElapsed;
    private volatile GnssStatus lastStatus;
    private volatile long startedElapsed;
    private volatile long ttffMs = -1;
    private long lastPublish;
    private int lastTileUsed = -1;
    private boolean lastTileLocked;

    private final LocationListener locationListener = new LocationListener() {
        @Override
        public void onLocationChanged(Location loc) {
            lastFix = loc;
            lastFixElapsed = SystemClock.elapsedRealtime();
            if (ttffMs < 0) ttffMs = lastFixElapsed - startedElapsed;
            publish(false);
        }

        @Override
        public void onProviderEnabled(String provider) {
            publish(true);
        }

        @Override
        public void onProviderDisabled(String provider) {
            publish(true);
        }
    };

    private final GnssStatus.Callback gnssCallback = new GnssStatus.Callback() {
        @Override
        public void onSatelliteStatusChanged(GnssStatus status) {
            lastStatus = status;
            publish(false);
        }

        @Override
        public void onFirstFix(int ttffMillis) {
            // Engine-reported time to first fix is more precise than our own clock
            ttffMs = ttffMillis;
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        lm = getSystemService(LocationManager.class);
        nm = getSystemService(NotificationManager.class);

        NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID, "GPS lock", NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Shows the satellite lock while GPS Locker is active");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);

        thread = new HandlerThread("gps-locker");
        thread.start();
        handler = new Handler(thread.getLooper());
        executor = handler::post;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : ACTION_START;

        if (ACTION_STOP.equals(action)) {
            shutdown();
            return START_NOT_STICKY;
        }

        try {
            Notification n = buildNotification("Starting GPS lock", "Waiting for satellites");
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            } else {
                startForeground(NOTIF_ID, n);
            }
        } catch (RuntimeException e) {
            Log.e(TAG, "startForeground failed", e);
            releaseWaiter();
            refreshTile();
            stopSelf();
            return START_NOT_STICKY;
        }
        releaseWaiter();

        handler.post(this::startLocking);
        return START_STICKY;
    }

    /** Lets the trampoline activity close now that the foreground decision is made. */
    private static void releaseWaiter() {
        Runnable r = sStartWaiter;
        sStartWaiter = null;
        if (r != null) r.run();
    }

    @SuppressLint("MissingPermission")
    private synchronized void startLocking() {
        if (locking) {
            publish(true);
            return;
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            nm.notify(NOTIF_ID, buildNotification("Location permission missing",
                    "Reinstall the module to grant it"));
            return;
        }

        startedElapsed = SystemClock.elapsedRealtime();
        ttffMs = -1;
        lastFix = null;
        lastStatus = null;

        LocationRequest req = new LocationRequest.Builder(INTERVAL_MS)
                .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
                .setMinUpdateIntervalMillis(INTERVAL_MS)
                .build();
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, req, executor, locationListener);
            lm.registerGnssStatusCallback(executor, gnssCallback);
        } catch (RuntimeException e) {
            Log.e(TAG, "GPS request failed", e);
            nm.notify(NOTIF_ID, buildNotification("GPS request failed", String.valueOf(e.getMessage())));
            return;
        }

        locking = true;
        sRunning = true;
        Log.i(TAG, "GPS lock started");
        publish(true);
    }

    private synchronized void stopLocking() {
        if (!locking) return;
        locking = false;
        sRunning = false;
        sUsed = 0;
        sVisible = 0;
        sL5 = 0;
        try {
            lm.removeUpdates(locationListener);
            lm.unregisterGnssStatusCallback(gnssCallback);
        } catch (RuntimeException e) {
            Log.w(TAG, "GPS release failed", e);
        }
        Log.i(TAG, "GPS lock stopped");
        refreshTile();
    }

    private void shutdown() {
        stopLocking();
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    /** Updates the notification and the tile, at most once per second. Runs on the GPS thread. */
    private synchronized void publish(boolean force) {
        if (!locking) return;
        long now = SystemClock.elapsedRealtime();
        if (!force && now - lastPublish < INTERVAL_MS) return;
        lastPublish = now;

        // Dual-frequency chips report one entry per signal (L1 and L5 of the same
        // satellite), so count unique satellites by constellation + svid.
        Set<Integer> visibleSats = new HashSet<>();
        Set<Integer> usedSats = new HashSet<>();
        Set<Integer> l5Sats = new HashSet<>();
        int[] perConst = new int[CONST_NAMES.length];
        GnssStatus st = lastStatus;
        if (st != null) {
            for (int i = 0; i < st.getSatelliteCount(); i++) {
                int c = st.getConstellationType(i);
                int key = c * 1000 + st.getSvid(i);
                if (st.getCn0DbHz(i) > 0f) {
                    visibleSats.add(key);
                    if (isL5(st, i)) l5Sats.add(key);
                }
                if (st.usedInFix(i) && usedSats.add(key) && c >= 0 && c < perConst.length) {
                    perConst[c]++;
                }
            }
        }
        int used = usedSats.size();
        int visible = visibleSats.size();
        sUsed = used;
        sVisible = visible;
        sL5 = l5Sats.size();

        boolean gpsOn = lm.isProviderEnabled(LocationManager.GPS_PROVIDER);
        Location fix = lastFix;
        boolean locked = fix != null && now - lastFixElapsed < FIX_STALE_MS;

        String title;
        String text;
        if (!gpsOn) {
            title = "Location is off";
            text = "Turn on location to lock satellites";
        } else if (locked) {
            title = String.format(Locale.US, "%d/%d sats locked", used, visible);
            StringBuilder sb = new StringBuilder();
            if (fix.hasAccuracy()) sb.append(String.format(Locale.US, "±%.0f m", fix.getAccuracy()));
            if (sL5 > 0) {
                if (sb.length() > 0) sb.append(" · ");
                sb.append("L5 ").append(sL5);
            }
            for (int c = 1; c < perConst.length; c++) {
                if (perConst[c] == 0) continue;
                if (sb.length() > 0) sb.append(" · ");
                sb.append(CONST_NAMES[c]).append(' ').append(perConst[c]);
            }
            text = sb.toString();
        } else {
            title = String.format(Locale.US, "Searching satellites (%d/%d)", used, visible);
            text = "Keep the phone under open sky";
        }
        nm.notify(NOTIF_ID, buildNotification(title, text));

        if (used != lastTileUsed || locked != lastTileLocked) {
            lastTileUsed = used;
            lastTileLocked = locked;
            refreshTile();
        }
    }

    /** L5 / E5a / B2a band, around 1176.45 MHz. */
    private static boolean isL5(GnssStatus st, int i) {
        if (!st.hasCarrierFrequencyHz(i)) return false;
        float f = st.getCarrierFrequencyHz(i);
        return f > 1.16e9f && f < 1.19e9f;
    }

    private Notification buildNotification(String title, String text) {
        PendingIntent stop = PendingIntent.getService(this, 1,
                new Intent(this, LockService.class).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_lock_sat)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(new Notification.Action.Builder((Icon) null, "Stop", stop).build())
                .build();
    }

    private void refreshTile() {
        LockTile.refresh(this);
    }

    /** Live status for the WebUI: dumpsys activity service io.github.nikakvo.gpslocker/.LockService */
    @Override
    protected void dump(FileDescriptor fd, PrintWriter pw, String[] args) {
        try {
            pw.println(statusJson().toString());
        } catch (JSONException e) {
            pw.println("{\"running\":false,\"error\":\"" + e.getMessage() + "\"}");
        }
        pw.flush();
    }

    private JSONObject statusJson() throws JSONException {
        long now = SystemClock.elapsedRealtime();
        JSONObject o = new JSONObject();
        o.put("running", locking);
        o.put("gps_on", lm.isProviderEnabled(LocationManager.GPS_PROVIDER));
        if (!locking) return o;

        o.put("uptime_ms", now - startedElapsed);
        o.put("ttff_ms", ttffMs);
        o.put("used", sUsed);
        o.put("visible", sVisible);
        o.put("l5", sL5);

        Location f = lastFix;
        if (f != null) {
            JSONObject fix = new JSONObject();
            fix.put("lat", f.getLatitude());
            fix.put("lon", f.getLongitude());
            if (f.hasAccuracy()) putNum(fix, "acc", f.getAccuracy());
            if (f.hasAltitude()) putNum(fix, "alt", f.getAltitude());
            if (f.hasSpeed()) putNum(fix, "speed", f.getSpeed());
            if (f.hasBearing()) putNum(fix, "bearing", f.getBearing());
            fix.put("age_ms", now - lastFixElapsed);
            o.put("fix", fix);
        }

        JSONArray sats = new JSONArray();
        GnssStatus st = lastStatus;
        if (st != null) {
            for (int i = 0; i < st.getSatelliteCount(); i++) {
                JSONObject s = new JSONObject();
                s.put("c", st.getConstellationType(i));
                s.put("svid", st.getSvid(i));
                putNum(s, "cn0", st.getCn0DbHz(i));
                putNum(s, "el", st.getElevationDegrees(i));
                putNum(s, "az", st.getAzimuthDegrees(i));
                s.put("used", st.usedInFix(i));
                if (st.hasCarrierFrequencyHz(i)) putNum(s, "freq", st.getCarrierFrequencyHz(i));
                sats.put(s);
            }
        }
        o.put("sats", sats);
        return o;
    }

    private static void putNum(JSONObject o, String key, double v) throws JSONException {
        if (Double.isFinite(v)) o.put(key, Math.round(v * 10.0) / 10.0);
    }

    @Override
    public void onDestroy() {
        stopLocking();
        thread.quitSafely();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
