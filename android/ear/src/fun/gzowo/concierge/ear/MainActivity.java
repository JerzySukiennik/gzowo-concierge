// Concierge Ucho - status screen: start or stop listening, see the connection and the sound level, open the battery setting.
package fun.gzowo.concierge.ear;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView status;
    private View bar;
    private Button toggle;
    private Button battery;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);
        int pad = dp(24);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.BLACK);
        root.setPadding(pad, dp(64), pad, pad);

        TextView title = text("Concierge Ucho", 30, Color.WHITE);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        root.addView(title);
        root.addView(text("Słucha w pokoju i przesyła dźwięk do MacPetite po domowym Wi-Fi. Dźwięk nie wychodzi poza dom.", 15, Color.rgb(150, 150, 150)), margins(dp(8), dp(32)));

        status = text("", 18, Color.WHITE);
        root.addView(status, margins(0, dp(14)));

        LinearLayout track = new LinearLayout(this);
        track.setBackground(round(Color.rgb(40, 40, 40), dp(4)));
        bar = new View(this);
        bar.setBackground(round(Color.WHITE, dp(4)));
        track.addView(bar, new LinearLayout.LayoutParams(0, dp(8)));
        root.addView(track, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(8)));

        toggle = button("");
        toggle.setOnClickListener(v -> { if (EarService.running) stop(); else start(); });
        root.addView(toggle, margins(dp(40), dp(12)));

        battery = button("Bateria: bez ograniczeń");
        battery.setOnClickListener(v -> {
            Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + getPackageName()));
            startActivity(i);
        });
        root.addView(battery, margins(0, dp(28)));

        SharedPreferences prefs = getSharedPreferences("ear", MODE_PRIVATE);
        root.addView(text("Adres MacPetite (puste = szukaj sam)", 13, Color.rgb(150, 150, 150)), margins(0, dp(6)));
        EditText host = new EditText(this);
        host.setTextColor(Color.WHITE);
        host.setHintTextColor(Color.rgb(90, 90, 90));
        host.setHint("np. 192.168.1.14");
        host.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        host.setText(prefs.getBoolean("manual", false) ? prefs.getString("host", "") : "");
        host.setOnFocusChangeListener((v, focus) -> {
            if (focus) return;
            String h = host.getText().toString().trim();
            prefs.edit().putString("host", h).putBoolean("manual", !h.isEmpty()).apply();
        });
        root.addView(host);

        setContentView(root);
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
            || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO, android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        } else if (!EarService.running) {
            start();
        }
        tick();
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) start();
    }

    private void start() {
        startForegroundService(new Intent(this, EarService.class));
        EarService.status = "Uruchamiam…";
    }

    private void stop() {
        stopService(new Intent(this, EarService.class));
    }

    private void tick() {
        status.setText(EarService.status);
        toggle.setText(EarService.running ? "Zatrzymaj" : "Słuchaj");
        LinearLayout.LayoutParams lp = (LinearLayout.LayoutParams) bar.getLayoutParams();
        View track = (View) bar.getParent();
        lp.width = (int) (track.getWidth() * Math.min(1f, EarService.level));
        bar.setLayoutParams(lp);
        PowerManager pm = getSystemService(PowerManager.class);
        battery.setVisibility(pm.isIgnoringBatteryOptimizations(getPackageName()) ? View.GONE : View.VISIBLE);
        ui.postDelayed(this::tick, 150);
    }

    private TextView text(String s, int sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        return t;
    }

    private Button button(String s) {
        Button b = new Button(this);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextSize(17);
        b.setTextColor(Color.BLACK);
        b.setBackground(round(Color.WHITE, dp(28)));
        b.setMinHeight(dp(56));
        b.setGravity(Gravity.CENTER);
        return b;
    }

    private GradientDrawable round(int color, int radius) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(radius);
        return d;
    }

    private LinearLayout.LayoutParams margins(int top, int bottom) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = top;
        lp.bottomMargin = bottom;
        return lp;
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
