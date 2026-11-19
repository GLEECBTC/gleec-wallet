package com.gleec.gleecdex;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Keeps the screen on while a move code is shown, and opens the app's settings page. */
final class DeviceControlsChannel implements MethodChannel.MethodCallHandler {
    private final Activity activity;
    private final MethodChannel channel;

    DeviceControlsChannel(@NonNull Activity activity, @NonNull BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "gleec.wallet/device_controls");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "keepScreenOn": {
                Boolean on = call.argument("on");
                activity.runOnUiThread(() -> {
                    if (Boolean.TRUE.equals(on)) {
                        activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    } else {
                        activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    }
                    result.success(null);
                });
                break;
            }
            case "openSettings": {
                Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.getPackageName(), null));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                try {
                    activity.startActivity(intent);
                    result.success(true);
                } catch (RuntimeException ignored) {
                    result.success(false);
                }
                break;
            }
            default:
                result.notImplemented();
        }
    }

    void dispose() {
        channel.setMethodCallHandler(null);
    }
}
