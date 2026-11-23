package com.gleec.gleecdex;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.util.Base64;
import androidx.credentials.GetPublicKeyCredentialOption;
import androidx.credentials.PublicKeyCredential;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialCustomException;
import androidx.credentials.exceptions.NoCredentialException;
import io.flutter.plugin.common.MethodCall;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONObject;

/** Runs the shipped Android bridge against the Android SDK and AndroidX on an emulator. */
public final class PasskeyBridgeInstrumentation extends Instrumentation {
    private static final String INTERNAL_APP = "com.gleec.gleecdex.onboardinginternal";
    private static final int ENCODING = Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING;
    private static final byte[] CHALLENGE = new byte[32];
    private static final byte[] PRF_INPUT = new byte[32];
    private static final byte[] FIXTURE_ID = {5, 6, 7};
    private static final byte[] PRF_RESULT = new byte[32];

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            Context context = getTargetContext();
            check(INTERNAL_APP.equals(context.getPackageName()), "isolated target package");
            requests();
            responses(context);
            failures();
            result.putString("passkey_bridge", "passed");
            finish(Activity.RESULT_OK, result);
        } catch (Exception | AssertionError | LinkageError error) {
            // Generated assertion messages identify only a failing invariant.
            result.putString("passkey_bridge", "failed");
            result.putString("failure", error instanceof AssertionError
                ? error.getMessage() : error.getClass().getSimpleName());
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private static void requests() throws Exception {
        PRF_INPUT[0] = 9;
        for (List<byte[]> allowed : Arrays.asList(
                Collections.<byte[]>emptyList(), Collections.singletonList(FIXTURE_ID))) {
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("rpId", "wallet-bridge.test");
            arguments.put("challenge", CHALLENGE);
            arguments.put("salt", PRF_INPUT);
            arguments.put("allowCredentials", allowed);
            arguments.put("timeoutMs", 120000);
            var request = PasskeyAuthenticatorChannel.publicKeyRequest(
                new MethodCall("getAssertion", arguments));
            var options = request.getCredentialOptions();
            check(options.size() == 1 && options.get(0) instanceof GetPublicKeyCredentialOption,
                "passkey-only Credential Manager request");
            var option = (GetPublicKeyCredentialOption) options.get(0);
            JSONObject json = new JSONObject(option.getRequestJson());
            check("wallet-bridge.test".equals(json.getString("rpId")), "relying party");
            check("required".equals(json.getString("userVerification")), "user verification");
            check(encoded(CHALLENGE).equals(json.getString("challenge")), "challenge encoding");
            check(!json.has("password"), "no password request");
            JSONObject eval = json.getJSONObject("extensions").getJSONObject("prf").getJSONObject("eval");
            check(encoded(PRF_INPUT).equals(eval.getString("first")), "PRF input encoding");
            var allowList = json.getJSONArray("allowCredentials");
            check(allowed.size() == allowList.length(), "discovery versus pinned assertion");
            if (!allowed.isEmpty()) {
                check(encoded(FIXTURE_ID).equals(allowList.getJSONObject(0).getString("id")),
                    "pinned credential encoding");
            }
        }
    }

    @SuppressWarnings("deprecation") // getPackageInfo flags overload works on API 28.
    private static void responses(Context context) throws Exception {
        var signers = context.getPackageManager()
            .getPackageInfo(context.getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES)
            .signingInfo.getApkContentsSigners();
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(signers[0].toByteArray());
        String origin = "android:apk-key-hash:" + encoded(digest);
        PRF_RESULT[0] = 12;
        Map<String, Object> actual = PasskeyAuthenticatorChannel.assertion(
            context, response(origin, encoded(PRF_RESULT)));
        check(Arrays.equals((byte[]) actual.get("credentialId"), FIXTURE_ID), "credential identifier");
        check(Arrays.equals((byte[]) actual.get("prf"), PRF_RESULT), "returned PRF output");
        check(actual.get("userHandle") == null, "absent optional user handle");
        check(actual.size() == 6, "normalised assertion fields");

        requireResponseFailure(context, response(origin, JSONObject.NULL), "prfUnavailable");
        requireResponseFailure(context, response(origin, ""), "prfUnavailable");
        requireResponseFailure(context, response(origin, null), "prfUnavailable");
        requireResponseFailure(context, response("https://wallet-bridge.test", encoded(PRF_RESULT)),
            "invalidResponse");
    }

    private static PublicKeyCredential response(String origin, Object prf) throws Exception {
        var clientData = new JSONObject().put("type", "webauthn.get").put("origin", origin);
        var response = new JSONObject()
            .put("clientDataJSON", encoded(clientData.toString().getBytes(StandardCharsets.UTF_8)))
            .put("authenticatorData", encoded(new byte[37]))
            .put("signature", encoded(new byte[] {1}))
            .put("userHandle", JSONObject.NULL);
        var credential = new JSONObject().put("type", "public-key")
            .put("id", encoded(FIXTURE_ID)).put("rawId", encoded(FIXTURE_ID)).put("response", response);
        if (prf != null) {
            credential.put("clientExtensionResults", new JSONObject().put("prf",
                new JSONObject().put("results", new JSONObject().put("first", prf))));
        }
        return new PublicKeyCredential(credential.toString());
    }

    private static void requireResponseFailure(Context context, PublicKeyCredential credential, String code)
            throws Exception {
        try {
            PasskeyAuthenticatorChannel.assertion(context, credential);
        } catch (PasskeyAuthenticatorChannel.Failure error) {
            check(code.equals(error.code), "expected bridge error " + code);
            return;
        }
        throw new AssertionError("invalid assertion was accepted");
    }

    private static void failures() {
        check("noCredential".equals(PasskeyAuthenticatorChannel.failureCode(new NoCredentialException())),
            "provider with no matching credential");
        check("canceled".equals(PasskeyAuthenticatorChannel.failureCode(new GetCredentialCancellationException())),
            "provider cancellation");
        check("unavailable".equals(PasskeyAuthenticatorChannel.failureCode(
            new GetCredentialCustomException("fixture.provider", "provider details"))),
            "provider failure classification without details");
    }

    private static String encoded(byte[] bytes) {
        return Base64.encodeToString(bytes, ENCODING);
    }

    private static void check(boolean condition, String check) {
        if (!condition) throw new AssertionError(check);
    }
}
