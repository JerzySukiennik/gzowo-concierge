// Concierge Ucho - foreground service: records the room at 16 kHz and streams it over the home Wi-Fi to the room speaker on MacPetite.
package fun.gzowo.concierge.ear;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.audiofx.AutomaticGainControl;
import android.media.audiofx.NoiseSuppressor;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.IBinder;
import android.os.PowerManager;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public class EarService extends Service {
    static final String TYPE = "_gzowoear._tcp.";
    static volatile String status = "Zatrzymane";
    static volatile float level = 0;
    static volatile boolean running = false;

    private Thread worker;
    private PowerManager.WakeLock wake;
    private WifiManager.WifiLock wifi;
    private WifiManager.MulticastLock multicast;

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("ear", "Ucho", NotificationManager.IMPORTANCE_LOW));
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(this, "ear")
            .setContentTitle("Concierge Ucho")
            .setContentText("Słucha dla głośnika w pokoju")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(open)
            .setOngoing(true)
            .build();
        startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
        if (!running) {
            running = true;
            wake = getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ear:stream");
            wake.acquire();
            WifiManager wm = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ear:wifi");
            wifi.acquire();
            multicast = wm.createMulticastLock("ear:mdns");
            multicast.acquire();
            worker = new Thread(this::loop, "ear");
            worker.start();
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (worker != null) worker.interrupt();
        if (wake != null && wake.isHeld()) wake.release();
        if (wifi != null && wifi.isHeld()) wifi.release();
        if (multicast != null && multicast.isHeld()) multicast.release();
        status = "Zatrzymane";
        level = 0;
        super.onDestroy();
    }

    private void loop() {
        SharedPreferences prefs = getSharedPreferences("ear", MODE_PRIVATE);
        while (running) {
            String host = prefs.getString("host", "");
            int port = prefs.getInt("port", 47110);
            if (host.isEmpty()) {
                status = "Szukam MacPetite w sieci…";
                String[] found = discover();
                if (found == null) { pause(3000); continue; }
                host = found[0];
                port = Integer.parseInt(found[1]);
            }
            stream(host, port);
            if (!prefs.getBoolean("manual", false)) prefs.edit().remove("host").apply();
            pause(2000);
        }
    }

    private String[] discover() {
        NsdManager nsd = getSystemService(NsdManager.class);
        final String[] result = new String[2];
        final CountDownLatch done = new CountDownLatch(1);
        NsdManager.DiscoveryListener listener = new NsdManager.DiscoveryListener() {
            public void onDiscoveryStarted(String t) {}
            public void onDiscoveryStopped(String t) {}
            public void onStartDiscoveryFailed(String t, int e) { done.countDown(); }
            public void onStopDiscoveryFailed(String t, int e) {}
            public void onServiceLost(NsdServiceInfo s) {}
            public void onServiceFound(NsdServiceInfo s) {
                nsd.resolveService(s, new NsdManager.ResolveListener() {
                    public void onResolveFailed(NsdServiceInfo i, int e) {}
                    public void onServiceResolved(NsdServiceInfo i) {
                        if (i.getHost() == null) return;
                        result[0] = i.getHost().getHostAddress();
                        result[1] = String.valueOf(i.getPort());
                        done.countDown();
                    }
                });
            }
        };
        try {
            nsd.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, listener);
            done.await(8, TimeUnit.SECONDS);
        } catch (Exception ignored) {
        } finally {
            try { nsd.stopServiceDiscovery(listener); } catch (Exception ignored) {}
        }
        return result[0] == null ? null : result;
    }

    private void stream(String host, int port) {
        AudioRecord rec = null;
        AutomaticGainControl agc = null;
        NoiseSuppressor ns = null;
        try (Socket socket = new Socket()) {
            status = "Łączę z " + host + "…";
            socket.connect(new InetSocketAddress(host, port), 4000);
            socket.setTcpNoDelay(true);
            OutputStream out = socket.getOutputStream();
            out.write(("GZEAR1 " + android.os.Build.MODEL + "\n").getBytes(StandardCharsets.UTF_8));
            int min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
            rec = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(min, 6400) * 2);
            if (AutomaticGainControl.isAvailable()) { agc = AutomaticGainControl.create(rec.getAudioSessionId()); if (agc != null) agc.setEnabled(true); }
            if (NoiseSuppressor.isAvailable()) { ns = NoiseSuppressor.create(rec.getAudioSessionId()); if (ns != null) ns.setEnabled(true); }
            rec.startRecording();
            status = "Połączone z " + host;
            getSharedPreferences("ear", MODE_PRIVATE).edit().putString("last", host).apply();
            byte[] buf = new byte[3200];
            while (running) {
                int n = rec.read(buf, 0, buf.length);
                if (n <= 0) continue;
                out.write(buf, 0, n);
                long sum = 0;
                for (int i = 0; i + 1 < n; i += 8) { int s = (short) ((buf[i] & 0xff) | (buf[i + 1] << 8)); sum += (long) s * s; }
                level = (float) Math.min(1.0, Math.sqrt(sum / Math.max(1.0, n / 8.0)) / 32768.0 * 6);
            }
        } catch (Exception e) {
            status = "Brak połączenia, ponawiam…";
        } finally {
            level = 0;
            if (rec != null) { try { rec.stop(); } catch (Exception ignored) {} rec.release(); }
            if (agc != null) agc.release();
            if (ns != null) ns.release();
        }
    }

    private void pause(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException ignored) {}
    }
}
