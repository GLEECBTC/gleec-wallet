package com.gleec.gleecdex;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import com.google.android.gms.auth.api.identity.AuthorizationRequest;
import com.google.android.gms.auth.api.identity.AuthorizationResult;
import com.google.android.gms.auth.api.identity.Identity;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.common.api.Scope;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Google authorization for the Drive app-data folder, through Play
 * services. It returns a short-lived access token, keeps nothing and never
 * logs the token. */
final class GoogleDriveAuthChannel implements MethodChannel.MethodCallHandler {
    private static final int REQUEST_CODE = 3313;
    private static final String DRIVE_APPDATA = "https://www.googleapis.com/auth/drive.appdata";
    private static final String MESSAGE = "Google sign-in could not be completed";
    private final Activity activity;
    private final MethodChannel channel;
    private MethodChannel.Result pending;

    GoogleDriveAuthChannel(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "gleec.wallet/google_drive_auth");
        channel.setMethodCallHandler(this);
    }

    @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"authorize".equals(call.method)) { result.notImplemented(); return; }
        if (pending != null) { result.error("busy", MESSAGE, null); return; }
        pending = result;
        final MethodChannel.Result owner = result;
        try {
            AuthorizationRequest request = AuthorizationRequest.builder()
                .setRequestedScopes(Collections.singletonList(new Scope(DRIVE_APPDATA)))
                .build();
            Identity.getAuthorizationClient(activity).authorize(request)
                .addOnCompleteListener(ContextCompat.getMainExecutor(activity), task -> {
                    if (pending != owner) return;
                    if (!task.isSuccessful()) { finish(null, failureCode(task.getException())); return; }
                    AuthorizationResult authorization = task.getResult();
                    if (authorization == null || !authorization.hasResolution()) {
                        finish(authorization, null);
                        return;
                    }
                    // Consent or an account choice is needed first.
                    PendingIntent consent = authorization.getPendingIntent();
                    try {
                        if (consent == null) throw new IllegalStateException();
                        activity.startIntentSenderForResult(
                            consent.getIntentSender(), REQUEST_CODE, null, 0, 0, 0);
                    } catch (Exception error) {
                        finish(null, "unavailable");
                    }
                });
        } catch (Exception error) {
            // Never forward Play services exceptions; they can carry account data.
            finish(null, "unavailable");
        }
    }

    boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_CODE) return false;
        if (pending == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null) { finish(null, "canceled"); return true; }
        try {
            finish(Identity.getAuthorizationClient(activity).getAuthorizationResultFromIntent(data), null);
        } catch (Exception error) {
            finish(null, failureCode(error));
        }
        return true;
    }

    private static String failureCode(Exception error) {
        return error instanceof ApiException
            && ((ApiException) error).getStatusCode() == CommonStatusCodes.CANCELED
            ? "canceled" : "unavailable";
    }

    private void finish(AuthorizationResult authorization, String failure) {
        MethodChannel.Result result = pending;
        pending = null;
        if (result == null) return;
        if (failure == null && authorization == null) failure = "unavailable";
        if (failure == null) {
            String token = authorization.getAccessToken();
            List<String> granted = authorization.getGrantedScopes();
            // Google's consent screen lets the user untick a scope.
            if (granted == null || !granted.contains(DRIVE_APPDATA)) failure = "canceled";
            else if (token == null || token.isEmpty()) failure = "unavailable";
            else {
                Map<String, Object> value = new HashMap<>();
                value.put("accessToken", token);
                result.success(value);
                return;
            }
        }
        result.error(failure, MESSAGE, null);
    }

    void dispose() {
        finish(null, "canceled");
        channel.setMethodCallHandler(null);
    }
}
