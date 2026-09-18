package com.gleec.gleecdex;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** Destination-first exports: no wallet bytes are retained while the picker is open. */
final class SensitiveExportChannel {
    private static final int REQUEST_CODE = 2207;
    private final Activity activity;
    private final MethodChannel channel;
    private MethodChannel.Result pendingSelection;
    private Uri destination;
    private String destinationToken;

    SensitiveExportChannel(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "gleec/sensitive-file-export");
        channel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "chooseDestination":
                    if (pendingSelection != null || destination != null) {
                        result.error("busy", "An export is already in progress", null);
                        return;
                    }
                    String name = call.argument("fileName");
                    if (name == null || name.isEmpty() || name.contains("/") || name.contains("\\")) {
                        result.error("invalid_name", "Invalid export filename", null);
                        return;
                    }
                    Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("application/json");
                    intent.putExtra(Intent.EXTRA_TITLE, name);
                    pendingSelection = result;
                    try {
                        activity.startActivityForResult(intent, REQUEST_CODE);
                    } catch (RuntimeException error) {
                        pendingSelection = null;
                        result.error("picker_unavailable", "Export destination unavailable", null);
                    }
                    break;
                case "write":
                    String writeToken = call.argument("token");
                    String data = call.argument("data");
                    if (!matches(writeToken) || data == null) {
                        result.error("invalid_destination", "Export destination expired", null);
                        return;
                    }
                    byte[] bytes = data.getBytes(StandardCharsets.UTF_8);
                    try (OutputStream output = activity.getContentResolver().openOutputStream(destination, "wt")) {
                        if (output == null) throw new java.io.IOException();
                        output.write(bytes);
                        output.flush();
                    } catch (Exception error) {
                        discard();
                        result.error("write_failed", "Could not save export", null);
                        return;
                    } finally {
                        java.util.Arrays.fill(bytes, (byte) 0);
                    }
                    destination = null;
                    destinationToken = null;
                    result.success(null);
                    break;
                case "discard":
                    if (matches(call.argument("token"))) discard();
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        });
    }

    boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_CODE) return false;
        MethodChannel.Result result = pendingSelection;
        pendingSelection = null;
        if (result == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            result.success(null);
            return true;
        }
        destination = data.getData();
        destinationToken = UUID.randomUUID().toString();
        result.success(destinationToken);
        return true;
    }

    private boolean matches(String token) {
        return destination != null && destinationToken != null && destinationToken.equals(token);
    }

    private void discard() {
        if (destination != null) {
            try {
                DocumentsContract.deleteDocument(activity.getContentResolver(), destination);
            } catch (Exception ignored) {
                // The document can contain only this export or be empty. Never log its URI.
            }
        }
        destination = null;
        destinationToken = null;
    }

    void dispose() {
        channel.setMethodCallHandler(null);
        if (pendingSelection != null) {
            pendingSelection.error("disposed", "Export destination expired", null);
            pendingSelection = null;
        }
        discard();
    }
}
