package com.gleec.gleecdex;

import android.app.KeyguardManager;
import android.content.Context;
import android.os.CancellationSignal;
import android.util.Base64;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.GetPublicKeyCredentialOption;
import androidx.credentials.PublicKeyCredential;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.GetCredentialInterruptedException;
import androidx.credentials.exceptions.NoCredentialException;
import androidx.credentials.exceptions.domerrors.NotAllowedError;
import androidx.credentials.exceptions.publickeycredential.GetPublicKeyCredentialDomException;
import androidx.fragment.app.FragmentActivity;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

/** One user-verified passkey assertion that evaluates the WebAuthn PRF
 * extension, through Credential Manager. It stores nothing and never sees the
 * wallet credential: the Dart passkey tier checks the reply and wipes the
 * PRF output. Credential Manager matches the site's Digital Asset Links to
 * this app's signing certificate before any provider answers. */
final class PasskeyAuthenticatorChannel implements MethodChannel.MethodCallHandler {
    private static final int ENCODING = Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING;
    private final FragmentActivity activity;
    private final MethodChannel channel;
    private final CredentialManager credentials;
    private MethodChannel.Result pending;
    private CancellationSignal cancellation;

    private static final class Failure extends Exception {
        final String code;
        Failure(String code) { this.code = code; }
    }

    PasskeyAuthenticatorChannel(FragmentActivity activity, BinaryMessenger messenger) {
        this.activity = activity;
        credentials = CredentialManager.create(activity);
        channel = new MethodChannel(messenger, "gleec.wallet/passkey");
        channel.setMethodCallHandler(this);
    }

    @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "support": {
                // Passkey providers require a screen lock. A provider must
                // still return PRF output; Dart treats this as a candidate.
                KeyguardManager keyguard =
                    (KeyguardManager) activity.getSystemService(Context.KEYGUARD_SERVICE);
                Map<String, Object> value = new HashMap<>();
                value.put("available", keyguard != null && keyguard.isDeviceSecure());
                result.success(value);
                break;
            }
            case "cancel":
                cancel();
                result.success(null);
                break;
            case "getAssertion":
                begin(call, result);
                break;
            default:
                result.notImplemented();
        }
    }

    private void begin(MethodCall call, MethodChannel.Result result) {
        if (pending != null) { result.error("busy", "Another passkey request is in progress", null); return; }
        final String request;
        try {
            request = requestJson(call);
        } catch (Exception error) {
            result.error("invalidResponse", "Passkey request could not be completed", null);
            return;
        }
        pending = result;
        cancellation = new CancellationSignal();
        GetCredentialRequest credentialRequest = new GetCredentialRequest.Builder()
            .addCredentialOption(new GetPublicKeyCredentialOption(request))
            .build();
        final MethodChannel.Result owner = result;
        credentials.getCredentialAsync(activity, credentialRequest, cancellation,
            ContextCompat.getMainExecutor(activity),
            new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                @Override public void onResult(GetCredentialResponse response) {
                    if (pending != owner) return;
                    try {
                        finish(assertion(response.getCredential()), null);
                    } catch (Failure failure) {
                        finish(null, failure.code);
                    } catch (Exception error) {
                        // Never forward provider exceptions; they can carry data.
                        finish(null, "invalidResponse");
                    }
                }

                @Override public void onError(@NonNull GetCredentialException error) {
                    if (pending != owner) return;
                    finish(null, failureCode(error));
                }
            });
    }

    private static String requestJson(MethodCall call) throws Exception {
        String rpId = call.argument("rpId");
        byte[] challenge = call.argument("challenge");
        byte[] salt = call.argument("salt");
        List<byte[]> allowed = call.argument("allowCredentials");
        Number timeout = call.argument("timeoutMs");
        if (rpId == null || rpId.isEmpty() || rpId.length() > 253 || challenge == null
            || challenge.length < 16 || salt == null || salt.length != 32 || allowed == null
            || allowed.size() > 16) throw new Failure("invalidResponse");
        JSONArray allowCredentials = new JSONArray();
        for (byte[] id : allowed) {
            allowCredentials.put(new JSONObject().put("type", "public-key").put("id", encode(id)));
        }
        return new JSONObject()
            .put("challenge", encode(challenge))
            .put("rpId", rpId)
            .put("timeout", timeout == null ? 120000 : timeout.longValue())
            // A PRF evaluated without verification uses a different secret
            // and would not open the envelope.
            .put("userVerification", "required")
            .put("allowCredentials", allowCredentials)
            .put("extensions", new JSONObject().put("prf",
                new JSONObject().put("eval", new JSONObject().put("first", encode(salt)))))
            .toString();
    }

    private static Map<String, Object> assertion(Credential credential) throws Exception {
        if (!(credential instanceof PublicKeyCredential)) throw new Failure("invalidResponse");
        JSONObject json = new JSONObject(((PublicKeyCredential) credential).getAuthenticationResponseJson());
        JSONObject response = json.getJSONObject("response");
        JSONObject prf = json.optJSONObject("clientExtensionResults") == null ? null
            : json.getJSONObject("clientExtensionResults").optJSONObject("prf");
        JSONObject results = prf == null ? null : prf.optJSONObject("results");
        // optString turns an explicit JSON null into the text "null", which is
        // valid base64url; test for null before reading either value.
        if (results == null || results.isNull("first")) throw new Failure("prfUnavailable");
        String first = results.getString("first");
        if (first.isEmpty()) throw new Failure("prfUnavailable");
        Map<String, Object> value = new HashMap<>();
        value.put("credentialId", decode(json.getString("rawId")));
        boolean noHandle = response.isNull("userHandle") || response.getString("userHandle").isEmpty();
        value.put("userHandle", noHandle ? null : decode(response.getString("userHandle")));
        value.put("authenticatorData", decode(response.getString("authenticatorData")));
        value.put("clientDataJSON", decode(response.getString("clientDataJSON")));
        value.put("signature", decode(response.getString("signature")));
        value.put("prf", decode(first));
        return value;
    }

    private static String failureCode(GetCredentialException error) {
        if (error instanceof GetCredentialCancellationException) return "canceled";
        if (error instanceof GetCredentialInterruptedException) return "interrupted";
        if (error instanceof NoCredentialException) return "noCredential";
        // WebAuthn reports dismissal and timeout alike as NotAllowedError.
        if (error instanceof GetPublicKeyCredentialDomException
            && ((GetPublicKeyCredentialDomException) error).getDomError() instanceof NotAllowedError) {
            return "canceled";
        }
        // Provider configuration, unsupported devices and asset-link failures.
        return "unavailable";
    }

    private void finish(Map<String, Object> value, String failure) {
        MethodChannel.Result result = pending;
        pending = null;
        cancellation = null;
        if (result == null) return;
        if (failure != null) result.error(failure, "Passkey request could not be completed", null);
        else result.success(value);
    }

    /** Answers the waiting call at once; Credential Manager's own
     * cancellation callback finds nothing left to answer. */
    private void cancel() {
        CancellationSignal signal = cancellation;
        if (signal != null) signal.cancel();
        finish(null, "canceled");
    }

    void dispose() {
        cancel();
        channel.setMethodCallHandler(null);
    }

    private static String encode(byte[] bytes) { return Base64.encodeToString(bytes, ENCODING); }

    private static byte[] decode(String value) throws Failure {
        try {
            byte[] bytes = Base64.decode(value, ENCODING);
            if (bytes.length == 0) throw new Failure("invalidResponse");
            return bytes;
        } catch (IllegalArgumentException error) {
            throw new Failure("invalidResponse");
        }
    }
}
