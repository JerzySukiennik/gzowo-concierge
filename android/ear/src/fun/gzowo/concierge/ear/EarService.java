// Concierge Ucho - foreground service: records the room at 16 kHz and streams it over the home Wi-Fi to the room speaker on MacPetite; MacPetite can switch the microphone mode over the same connection.
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
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public class EarService extends Service {
    static final String TYPE = "_gzowoear._tcp.";
    static final int[] SOURCES = { MediaRecorder.AudioSource.MIC, MediaRecorder.AudioSource.CAMCORDER, MediaRecorder.AudioSource.VOICE_RECOGNITION, MediaRecorder.AudioSource.VOICE_COMMUNICATION, MediaRecorder.AudioSource.UNPROCESSED };
    static volatile String status = "Zatrzymane";
    static volatile float level = 0;
    static volatile boolean running = false;

    private volatile int wantedSource = -1;
    private volatile int cycleSeconds = 0;
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

    private static String sourceName(int s) {
        switch (s) {
            case MediaRecorder.AudioSource.MIC: return "mikrofon";
            case MediaRecorder.AudioSource.CAMCORDER: return "kamera";
            case MediaRecorder.AudioSource.VOICE_RECOGNITION: return "rozpoznawanie mowy";
            case MediaRecorder.AudioSource.VOICE_COMMUNICATION: return "rozmowa";
            case MediaRecorder.AudioSource.UNPROCESSED: return "bez obróbki";
            default: return "źródło " + s;
        }
    }

    private static final class Recorder {
        final AudioRecord rec;
        final AutomaticGainControl agc;
        final NoiseSuppressor ns;

        Recorder(int source) {
            int min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
            rec = new AudioRecord(source, 16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(min, 6400) * 2);
            boolean effects = source == MediaRecorder.AudioSource.VOICE_RECOGNITION;
            agc = effects && AutomaticGainControl.isAvailable() ? AutomaticGainControl.create(rec.getAudioSessionId()) : null;
            if (agc != null) agc.setEnabled(true);
            ns = effects && NoiseSuppressor.isAvailable() ? NoiseSuppressor.create(rec.getAudioSessionId()) : null;
            if (ns != null) ns.setEnabled(true);
            rec.startRecording();
        }

        void close() {
            try { rec.stop(); } catch (Exception ignored) {}
            rec.release();
            if (agc != null) agc.release();
            if (ns != null) ns.release();
        }
    }

    private void stream(String host, int port) {
        SharedPreferences prefs = getSharedPreferences("ear", MODE_PRIVATE);
        Recorder r = null;
        try (Socket socket = new Socket()) {
            status = "Łączę z " + host + "…";
            socket.connect(new InetSocketAddress(host, port), 4000);
            socket.setTcpNoDelay(true);
            OutputStream out = socket.getOutputStream();
            listen(socket);
            int source = prefs.getInt("source", MediaRecorder.AudioSource.CAMCORDER);
            out.write(("GZEAR1 " + android.os.Build.MODEL + " " + sourceName(source) + "\n").getBytes(StandardCharsets.UTF_8));
            r = new Recorder(source);
            getSharedPreferences("ear", MODE_PRIVATE).edit().putString("last", host).apply();
            byte[] buf = new byte[3200];
            byte[] gap = new byte[16000];
            long switched = System.currentTimeMillis();
            int cycleIndex = 0;
            while (running) {
                int want = wantedSource;
                boolean cycleDue = cycleSeconds > 0 && System.currentTimeMillis() - switched > cycleSeconds * 1000L;
                if (cycleDue || (want >= 0 && want != source)) {
                    if (cycleDue) {
                        cycleIndex++;
                        if (cycleIndex >= SOURCES.length) { cycleSeconds = 0; want = prefs.getInt("source", MediaRecorder.AudioSource.CAMCORDER); } else want = SOURCES[cycleIndex];
                    }
                    wantedSource = -1;
                    r.close();
                    out.write(gap);
                    source = want;
                    r = new Recorder(source);
                    switched = System.currentTimeMillis();
                }
                status = "Połączone z " + host + " (" + sourceName(source) + (cycleSeconds > 0 ? ", test" : "") + ")";
                int n = r.rec.read(buf, 0, buf.length);
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
            if (r != null) r.close();
        }
    }

    private void listen(Socket socket) {
        Thread t = new Thread(() -> {
            try {
                BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                String line;
                while ((line = in.readLine()) != null) {
                    String[] p = line.trim().split(" ");
                    if (p.length == 2 && p[0].equals("SOURCE")) {
                        int s = Integer.parseInt(p[1]);
                        getSharedPreferences("ear", MODE_PRIVATE).edit().putInt("source", s).apply();
                        wantedSource = s;
                    } else if (p.length == 2 && p[0].equals("CYCLE")) {
                        wantedSource = SOURCES[0];
                        cycleSeconds = Integer.parseInt(p[1]);
                    }
                }
            } catch (Exception ignored) {}
        }, "ear-commands");
        t.setDaemon(true);
        t.start();
    }

    private void pause(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException ignored) {}
    }
}
