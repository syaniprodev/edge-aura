#!/bin/bash
set -e

echo "Menyuntikkan kode Native Android..."

# 1. Modifikasi AndroidManifest.xml
MANIFEST="examples/basic/android/app/src/main/AndroidManifest.xml"
# Tambah izin Overlay & Notif Listener
sed -i 's|<application|<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />\n    <application|' $MANIFEST
# Tambah Service
sed -i 's|</application>|<service android:name=".EdgeLightService" android:exported="false" />\n        <service android:name=".NotificationListener" android:label="Aura Edge" android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" android:exported="true">\n            <intent-filter>\n                <action android:name="android.service.notification.NotificationListenerService" />\n            </intent-filter>\n        </service>\n    </application>|' $MANIFEST

# 2. Buat File NotificationListener.java
cat << 'EOF' > examples/basic/android/app/src/main/java/com/aura/edge/NotificationListener.java
package com.aura.edge;

import android.content.Intent;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.os.Build;
import android.util.Log;

public class NotificationListener extends NotificationListenerService {
    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        // Abaikan notifikasi dari aplikasi kita sendiri
        if (sbn.getPackageName().equals(getPackageName())) return;

        Log.d("AuraEdge", "Notifikasi masuk dari: " + sbn.getPackageName());
        
        // Jalankan Overlay Service
        Intent intent = new Intent(this, EdgeLightService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
    }
}
EOF

# 3. Buat File EdgeLightService.java (Penggambar Overlay)
cat << 'EOF' > examples/basic/android/app/src/main/java/com/aura/edge/EdgeLightService.java
package com.aura.edge;

import android.app.Service;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

public class EdgeLightService extends Service {
    private WindowManager windowManager;
    private View overlayView;

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (overlayView != null) {
            windowManager.removeView(overlayView);
        }

        overlayView = new View(this) {
            private final Paint paint = new Paint();
            @Override
            protected void onDraw(Canvas canvas) {
                super.onDraw(canvas);
                paint.setStyle(Paint.Style.STROKE);
                paint.setStrokeWidth(80f); // Ketebalan glow
                paint.setColor(Color.parseColor("#00FFFF")); // Warna Cyan/Aura
                paint.setAntiAlias(true);
                
                // Gambar border di pinggir layar
                canvas.drawRect(0, 0, getWidth(), getHeight(), paint);
            }
        };

        int layoutFlag;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            layoutFlag = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY;
        } else {
            layoutFlag = WindowManager.LayoutParams.TYPE_PHONE;
        }

        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | // Tembus sentuhan
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);

        windowManager.addView(overlayView, params);

        // Hilangkan efek setelah 3 detik
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (overlayView != null) {
                windowManager.removeView(overlayView);
                overlayView = null;
            }
            stopSelf();
        }, 3000);

        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
EOF

# 4. Minta Izin Overlay saat App Dibuka
sed -i 's|super.onCreate(savedInstanceState);|super.onCreate(savedInstanceState);\n        if (!android.provider.Settings.canDrawOverlays(this)) {\n            android.content.Intent intent = new android.content.Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:" + getPackageName()));\n            startActivity(intent);\n        }|' examples/basic/android/app/src/main/java/com/aura/edge/MainActivity.java

echo "Patching selesai!"
