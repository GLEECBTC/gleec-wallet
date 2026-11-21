package com.gleec.gleecdex;

import android.app.Activity;
import android.app.KeyguardManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Base64;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;
import android.security.keystore.UserNotAuthenticatedException;
import androidx.annotation.NonNull;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.FragmentActivity;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONObject;

/** Authenticated Keystore encryption. The caller cannot opt out of the policy
 * attached to an already stored key. No secret is written to preferences. */
final class WalletCredentialVault implements MethodChannel.MethodCallHandler {
    private static final int CONFIRM_CREDENTIAL = 4821;
    private static final String PREFIX = "gleec.wallet.credential.v1.";
    private static final Object STORAGE_LOCK = new Object();
    private final FragmentActivity activity;
    private final MethodChannel channel;
    private final SharedPreferences storage;
    private final KeyguardManager keyguard;
    private final KeyStore keyStore;
    private Pending pending;
    private BiometricPrompt prompt;
    private Object biometricCeremony;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private CancellationSignal credentialCancellation;
    private CredentialRequest credentialRequest;
    private final Map<String, DeletionAuthorization> deletionAuthorizations = new HashMap<>();
    private final Map<String, DeletionAuthorization> deletionReadAuthorizations = new HashMap<>();
    private final BroadcastReceiver lockReceiver;

    private interface ValueCallback { void accept(String value) throws Exception; }
    private interface CipherCallback { void accept(Cipher cipher) throws Exception; }
    private static final class Failure extends Exception {
        final String code;
        Failure(String code) { this.code = code; }
    }
    private static final class Pending {
        final MethodChannel.Result result;
        final ArrayList<String> newAliases = new ArrayList<>();
        boolean committed;
        boolean cancellationRequested;
        Pending(MethodChannel.Result result) { this.result = result; }
    }
    private static final class CredentialRequest {
        final Pending operation;
        Runnable continuation;
        CredentialRequest(Pending operation, Runnable continuation) {
            this.operation = operation; this.continuation = continuation;
        }
    }
    private static final class DeletionAuthorization {
        final String id;
        final String snapshot;
        final long expires;
        DeletionAuthorization(String id, JSONObject record) {
            this(id, record, SystemClock.elapsedRealtime() + 60000);
        }
        DeletionAuthorization(String id, JSONObject record, long expires) {
            this.id = id; this.snapshot = record == null ? null : record.toString(); this.expires = expires;
        }
    }

    WalletCredentialVault(FragmentActivity activity, BinaryMessenger messenger) throws Exception {
        this.activity = activity;
        channel = new MethodChannel(messenger, "gleec.wallet/credential_vault");
        storage = activity.getSharedPreferences("gleec_wallet_credential_vault_v1", Context.MODE_PRIVATE);
        keyguard = (KeyguardManager) activity.getSystemService(Context.KEYGUARD_SERVICE);
        keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        channel.setMethodCallHandler(this);
        lockReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                cancel();
                channel.invokeMethod("deviceLocked", null);
            }
        };
        ContextCompat.registerReceiver(activity, lockReceiver,
            new IntentFilter(Intent.ACTION_SCREEN_OFF), ContextCompat.RECEIVER_NOT_EXPORTED);
    }

    @Override public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (call.method.equals("cancel")) { cancel(); result.success(null); return; }
        if (call.method.equals("capabilities")) {
            boolean canAuthenticate = keyguard != null && keyguard.isDeviceSecure();
            Map<String, Object> value = new HashMap<>();
            value.put("available", true);
            value.put("deviceAuthentication", canAuthenticate);
            value.put("protection", canAuthenticate
                ? (Build.VERSION.SDK_INT >= 30 ? "authenticationBound" : "recentDeviceAuthenticationBound")
                : "osAccountProtected");
            result.success(value); return;
        }
        // A canceled API 28/29 keyguard Activity still owns its result slot.
        // Drain it before starting another operation; never reuse its result.
        if (pending != null || credentialRequest != null) { result.error("busy", "Another authentication is in progress", null); return; }
        Pending operation = new Pending(result);
        pending = operation;
        try {
            if (call.method.equals("savePassword")) { savePassword(operation, call); return; }
            String key = call.argument("key");
            if (key == null || key.isEmpty() || key.length() > 512 || key.indexOf(0) >= 0) throw new Failure("storageFailed");
            String id = digest(key);
            String authorization = call.argument("authorization");
            boolean repair = call.method.equals("repairInvalidated");
            JSONObject record = record(id, !repair && !call.method.equals("prepareDelete") && (!call.method.equals("delete") || authorization == null));
            boolean required = Boolean.TRUE.equals(call.argument("requireAuthentication"));
            String reason = call.argument("reason");
            if (reason == null || reason.isEmpty()) reason = "Unlock your Gleec wallet";
            switch (call.method) {
                case "metadata": complete(operation, record == null ? null : metadata(record)); break;
                case "read":
                    if (record == null) { complete(operation, null); break; }
                    if (required && !enrolled(record)) throw new Failure("invalidated");
                    read(operation, id, record, reason, value -> {
                        if ("delete".equals(call.argument("purpose"))) {
                            synchronized (STORAGE_LOCK) {
                                if (!record.toString().equals(storage.getString(id, null))) throw new Failure("busy");
                                deletionReadAuthorizations.put(id, new DeletionAuthorization(id, record));
                            }
                        }
                        complete(operation, value);
                    });
                    break;
                case "write":
                case "repairInvalidated":
                    String value = call.argument("value");
                    if (value == null || value.length() > 65536) throw new Failure("storageFailed");
                    if (repair) {
                        // This explicit path is called only after the service
                        // verifies the supplied wallet credential with KDF. It
                        // cannot release old data or create unattended access.
                        if (!required || record == null || !allKeysInvalidated(record)) throw new Failure("unavailable");
                        write(operation, id, value, true, record);
                        break;
                    }
                    if (record != null && enrolled(record)) {
                        if (!required) throw new Failure("invalidated");
                        read(operation, id, record, reason, ignored -> write(operation, id, value, true, record));
                    } else write(operation, id, value, required, record);
                    break;
                case "delete":
                    if (authorization != null) {
                        DeletionAuthorization grant = deletionAuthorizations.remove(authorization);
                        String snapshot = record == null ? null : record.toString();
                        if (grant == null || !grant.id.equals(id) || grant.expires < SystemClock.elapsedRealtime()
                            || !java.util.Objects.equals(grant.snapshot, snapshot)) throw new Failure("invalidated");
                        delete(operation, id, record);
                        break;
                    }
                    if (record == null) { complete(operation, null); break; }
                    read(operation, id, record, reason, ignored -> delete(operation, id, record));
                    break;
                case "prepareDelete":
                    if (record == null) { authorizeDeletion(operation, id, null); break; }
                    DeletionAuthorization priorRead = deletionReadAuthorizations.remove(id);
                    if (priorRead != null && priorRead.snapshot.equals(record.toString())
                        && priorRead.expires >= SystemClock.elapsedRealtime()) {
                        authorizeDeletion(operation, id, record, priorRead.expires); break;
                    }
                    if (allKeysInvalidated(record)) {
                        authorizeInvalidatedDeletion(operation, id, record, reason); break;
                    }
                    enrolled(record);
                    read(operation, id, record, reason, ignored -> {
                        authorizeDeletion(operation, id, record);
                    });
                    break;
                default: pending = null; result.notImplemented();
            }
        } catch (Exception error) { fail(operation, error); }
    }

    private JSONObject record(String id, boolean validateKey) throws Exception {
        String stored = storage.getString(id, null);
        if (stored == null) return null;
        JSONObject record = new JSONObject(stored);
        if (record.getInt("version") != 1 || record.getInt("revision") < 1) throw new Failure("invalidated");
        // Inspect the Keystore policy, not an app-controlled enrollment flag.
        if (validateKey) enrolled(record);
        return record;
    }

    private void authorizeDeletion(Pending operation, String id, JSONObject record) throws Exception {
        authorizeDeletion(operation, id, record, SystemClock.elapsedRealtime() + 60000);
    }

    private void authorizeDeletion(Pending operation, String id, JSONObject record, long expires) throws Exception {
        if (pending != operation) return;
        synchronized (STORAGE_LOCK) {
            String snapshot = record == null ? null : record.toString();
            if (!java.util.Objects.equals(snapshot, storage.getString(id, null))) throw new Failure("busy");
            deletionAuthorizations.entrySet().removeIf(entry -> entry.getValue().expires < SystemClock.elapsedRealtime());
            String token = UUID.randomUUID().toString();
            deletionAuthorizations.put(token, new DeletionAuthorization(id, record, expires));
            complete(operation, token);
        }
    }

    private void delete(Pending operation, String id, JSONObject record) throws Exception {
        if (pending != operation) return;
        synchronized (STORAGE_LOCK) {
            String snapshot = record == null ? null : record.toString();
            if (!java.util.Objects.equals(snapshot, storage.getString(id, null))) throw new Failure("busy");
            if (record != null) {
                if (!storage.edit().remove(id).commit()) throw new Failure("storageFailed");
                removeAliases(record);
            }
        }
        complete(operation, null);
    }

    private void authorizeInvalidatedDeletion(Pending operation, String id, JSONObject record, String reason) throws Exception {
        if (pending != operation) return;
        if (keyguard == null || !keyguard.isDeviceSecure()) throw new Failure("unavailable");
        // The old wrappers have already been proven unusable. Authorize only
        // their removal with a new, ephemeral authentication-bound key. No old
        // secret is read or replaced and no unattended wrapper is introduced.
        boolean legacy = Build.VERSION.SDK_INT < 30;
        String alias = createKey(operation, true, legacy);
        CipherCallback authorized = secured -> {
            byte[] proof = secured.doFinal(new byte[0]);
            Arrays.fill(proof, (byte) 0);
            keyStore.deleteEntry(alias);
            authorizeDeletion(operation, id, record);
        };
        if (!legacy) {
            authenticateCipher(operation, encryptCipher(alias), reason, false, authorized, null);
        } else {
            confirmCredential(operation, reason, () -> {
                try { authorized.accept(encryptCipher(alias)); }
                catch (Exception error) { fail(operation, error); }
            });
        }
    }

    private boolean enrolled(JSONObject record) throws Exception {
        JSONObject envelope = record.has("fallback") ? record.getJSONObject("fallback") : record.getJSONObject("primary");
        SecretKey key = key(envelope.getString("alias"));
        KeyInfo info = (KeyInfo) SecretKeyFactory.getInstance(key.getAlgorithm(), "AndroidKeyStore").getKeySpec(key, KeyInfo.class);
        boolean required = info.isUserAuthenticationRequired();
        if (required != !record.getString("mode").equals("local")) throw new Failure("invalidated");
        return required;
    }

    private boolean allKeysInvalidated(JSONObject record) throws Exception {
        String mode = record.getString("mode");
        if (!mode.equals("legacy") && !mode.equals("perUse")) return false;
        if (!record.has(mode.equals("legacy") ? "fallback" : "primary")) throw new Failure("invalidated");
        for (String role : new String[]{"primary", "fallback"}) {
            if (!record.has(role)) continue;
            JSONObject envelope = record.getJSONObject(role);
            String alias = envelope.getString("alias");
            if (!alias.startsWith(PREFIX)) throw new Failure("invalidated");
            // A missing old key or the platform's explicit invalidation error
            // proves it unusable. Lockout, cancellation and generic failures do
            // not authorize repair.
            try {
                if (keyStore.getKey(alias, null) == null) continue;
                decryptCipher(envelope);
                return false;
            } catch (KeyPermanentlyInvalidatedException invalidated) {
                continue;
            } catch (UserNotAuthenticatedException notAuthorized) {
                return false;
            }
        }
        return true;
    }

    private Map<String, Object> metadata(JSONObject record) throws Exception {
        boolean enrolled = enrolled(record);
        Map<String, Object> result = new HashMap<>();
        result.put("enrolled", enrolled);
        result.put("revision", record.getInt("revision"));
        result.put("protection", !enrolled ? "osAccountProtected"
            : record.getString("mode").equals("legacy") ? "recentDeviceAuthenticationBound" : "authenticationBound");
        return result;
    }

    private void write(Pending operation, String id, String value, boolean authenticated, JSONObject old) throws Exception {
        if (pending != operation) return;
        if (authenticated && (keyguard == null || !keyguard.isDeviceSecure())) throw new Failure("unavailable");
        JSONObject next = new JSONObject();
        next.put("version", 1);
        next.put("revision", old == null ? 1 : Math.addExact(old.getInt("revision"), 1));
        next.put("mode", !authenticated ? "local" : Build.VERSION.SDK_INT >= 30 ? "perUse" : "legacy");
        if (!authenticated) {
            String alias = createKey(operation, false, false);
            Cipher cipher = encryptCipher(alias);
            next.put("primary", seal(cipher, alias, value, aad(id, next, "primary", alias)));
            commit(operation, id, next, old);
        } else if (Build.VERSION.SDK_INT >= 30) {
            String alias = createKey(operation, true, false);
            Cipher cipher = encryptCipher(alias);
            authenticateCipher(operation, cipher, "Protect your Gleec wallet", false, secured -> {
                next.put("primary", seal(secured, alias, value, aad(id, next, "primary", alias)));
                commit(operation, id, next, old);
            }, null);
        } else {
            // API 28/29 cannot combine a CryptoObject and device credentials.
            // Keep a separate, OS-authenticated 30-second credential wrapper.
            String fallbackAlias = createKey(operation, true, true);
            confirmCredential(operation, "Protect your Gleec wallet", () -> {
                try {
                    Cipher cipher = encryptCipher(fallbackAlias);
                    next.put("fallback", seal(cipher, fallbackAlias, value, aad(id, next, "fallback", fallbackAlias)));
                    if (!strongBiometrics()) { commit(operation, id, next, old); return; }
                    String biometricAlias = createKey(operation, true, false);
                    Cipher biometricCipher = encryptCipher(biometricAlias);
                    authenticateCipher(operation, biometricCipher, "Enable fingerprint unlock", true, secured -> {
                        next.put("primary", seal(secured, biometricAlias, value, aad(id, next, "primary", biometricAlias)));
                        commit(operation, id, next, old);
                    }, () -> {
                        try { keyStore.deleteEntry(biometricAlias); commit(operation, id, next, old); }
                        catch (Exception error) { fail(operation, error); }
                    });
                } catch (Exception error) { fail(operation, error); }
            });
        }
    }

    private void commit(Pending operation, String id, JSONObject next, JSONObject old) throws Exception {
        if (pending != operation) return;
        synchronized (STORAGE_LOCK) {
            String current = storage.getString(id, null);
            if (old == null ? current != null : !old.toString().equals(current)) throw new Failure("busy");
            String encoded = next.toString();
            // A failed commit can be ambiguous (in-memory preferences may already
            // reference the new record). Retain its keys until reconciliation;
            // deleting them here could turn a recoverable write into data loss.
            operation.committed = true;
            if (!storage.edit().putString(id, encoded).commit() || !encoded.equals(storage.getString(id, null))) throw new Failure("storageFailed");
            if (old != null) removeAliases(old);
        }
        complete(operation, null);
    }

    private void read(Pending operation, String id, JSONObject record, String reason, ValueCallback callback) throws Exception {
        if (pending != operation) return;
        String mode = record.getString("mode");
        if (mode.equals("local")) { callback.accept(open(id, record, "primary", null)); return; }
        if (mode.equals("perUse")) {
            Cipher cipher = decryptCipher(record.getJSONObject("primary"));
            authenticateCipher(operation, cipher, reason, false,
                secured -> callback.accept(open(id, record, "primary", secured)), null);
            return;
        }
        if (!mode.equals("legacy")) throw new Failure("invalidated");
        Runnable fallback = () -> confirmCredential(operation, reason, () -> {
            try { callback.accept(open(id, record, "fallback", null)); }
            catch (Exception error) { fail(operation, error); }
        });
        if (!record.has("primary") || !strongBiometrics()) { fallback.run(); return; }
        try {
            Cipher cipher = decryptCipher(record.getJSONObject("primary"));
            authenticateCipher(operation, cipher, reason, true,
                secured -> callback.accept(open(id, record, "primary", secured)), fallback);
        } catch (KeyPermanentlyInvalidatedException error) { fallback.run(); }
    }

    private void authenticateCipher(Pending operation, Cipher cipher, String reason, boolean legacy,
                                    CipherCallback callback, Runnable fallback) {
        if (pending != operation) return;
        Object ceremony = new Object();
        biometricCeremony = ceremony;
        prompt = new BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), new BiometricPrompt.AuthenticationCallback() {
            @Override public void onAuthenticationSucceeded(@NonNull BiometricPrompt.AuthenticationResult authentication) {
                // AndroidX shares prompt state for this FragmentActivity. Let
                // its terminal callback/dismissal finish before another
                // ceremony can install a callback on that shared state.
                mainHandler.post(() -> {
                    if (pending != operation || biometricCeremony != ceremony) return;
                    biometricCeremony = null; prompt = null;
                    if (operation.cancellationRequested) { fail(operation, new Failure("canceled")); return; }
                    try {
                        if (authentication.getCryptoObject() == null || authentication.getCryptoObject().getCipher() != cipher) throw new Failure("invalidated");
                        callback.accept(cipher);
                    } catch (Exception error) { fail(operation, error); }
                });
            }
            @Override public void onAuthenticationError(int code, @NonNull CharSequence ignored) {
                mainHandler.post(() -> {
                    if (pending != operation || biometricCeremony != ceremony) return;
                    biometricCeremony = null; prompt = null;
                    if (operation.cancellationRequested) { fail(operation, new Failure("canceled")); return; }
                    if (fallback != null && (code == BiometricPrompt.ERROR_NEGATIVE_BUTTON || code == BiometricPrompt.ERROR_LOCKOUT || code == BiometricPrompt.ERROR_LOCKOUT_PERMANENT || code == BiometricPrompt.ERROR_HW_UNAVAILABLE || code == BiometricPrompt.ERROR_NO_BIOMETRICS)) {
                        fallback.run(); return;
                    }
                    String safe = code == BiometricPrompt.ERROR_LOCKOUT || code == BiometricPrompt.ERROR_LOCKOUT_PERMANENT ? "lockedOut"
                        : code == BiometricPrompt.ERROR_CANCELED || code == BiometricPrompt.ERROR_USER_CANCELED || code == BiometricPrompt.ERROR_NEGATIVE_BUTTON ? "canceled" : "unavailable";
                    fail(operation, new Failure(safe));
                });
            }
        });
        BiometricPrompt.PromptInfo.Builder info = new BiometricPrompt.PromptInfo.Builder().setTitle(reason);
        if (legacy) info.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG).setNegativeButtonText("Use device PIN");
        else info.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG | BiometricManager.Authenticators.DEVICE_CREDENTIAL);
        prompt.authenticate(info.build(), new BiometricPrompt.CryptoObject(cipher));
    }

    @SuppressWarnings("deprecation")
    private void confirmCredential(Pending operation, String reason, Runnable continuation) {
        if (pending != operation) return;
        if (keyguard == null || !keyguard.isDeviceSecure()) { fail(operation, new Failure("unavailable")); return; }
        Intent intent = keyguard.createConfirmDeviceCredentialIntent(reason, "Use your device screen lock to unlock your wallet");
        if (intent == null) { fail(operation, new Failure("unavailable")); return; }
        if (credentialRequest != null) { fail(operation, new Failure("busy")); return; }
        credentialRequest = new CredentialRequest(operation, continuation);
        try { activity.startActivityForResult(intent, CONFIRM_CREDENTIAL); }
        catch (Exception error) { credentialRequest = null; fail(operation, new Failure("unavailable")); }
    }

    boolean onActivityResult(int requestCode, int resultCode) {
        if (requestCode != CONFIRM_CREDENTIAL) return false;
        CredentialRequest request = credentialRequest;
        credentialRequest = null;
        if (request != null && pending == request.operation && request.continuation != null) {
            if (resultCode == Activity.RESULT_OK) request.continuation.run();
            else fail(request.operation, new Failure("canceled"));
        }
        return true;
    }

    private boolean strongBiometrics() {
        return BiometricManager.from(activity).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS;
    }

    @SuppressWarnings("deprecation")
    private String createKey(Pending operation, boolean authenticated, boolean legacyCredential) throws Exception {
        String alias = PREFIX + UUID.randomUUID();
        KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setUserAuthenticationRequired(authenticated).setRandomizedEncryptionRequired(true);
        if (authenticated) {
            if (Build.VERSION.SDK_INT >= 30) spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG | KeyProperties.AUTH_DEVICE_CREDENTIAL);
            else if (legacyCredential) spec.setUserAuthenticationValidityDurationSeconds(30);
            else spec.setUserAuthenticationValidityDurationSeconds(-1).setInvalidatedByBiometricEnrollment(true);
        }
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(spec.build());
        generator.generateKey();
        operation.newAliases.add(alias);
        return alias;
    }

    private SecretKey key(String alias) throws Exception {
        if (!alias.startsWith(PREFIX)) throw new Failure("invalidated");
        SecretKey result = (SecretKey) keyStore.getKey(alias, null);
        if (result == null) throw new Failure("invalidated");
        return result;
    }
    private Cipher encryptCipher(String alias) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key(alias)); return cipher;
    }
    private Cipher decryptCipher(JSONObject envelope) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        byte[] iv = Base64.decode(envelope.getString("iv"), Base64.NO_WRAP);
        if (iv.length != 12) throw new Failure("invalidated");
        cipher.init(Cipher.DECRYPT_MODE, key(envelope.getString("alias")), new GCMParameterSpec(128, iv)); return cipher;
    }
    private JSONObject seal(Cipher cipher, String alias, String value, byte[] aad) throws Exception {
        byte[] plain = value.getBytes(StandardCharsets.UTF_8);
        try {
            cipher.updateAAD(aad);
            JSONObject envelope = new JSONObject();
            envelope.put("alias", alias);
            envelope.put("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP));
            envelope.put("ciphertext", Base64.encodeToString(cipher.doFinal(plain), Base64.NO_WRAP));
            return envelope;
        } finally { Arrays.fill(plain, (byte) 0); }
    }
    private String open(String id, JSONObject record, String role, Cipher cipher) throws Exception {
        JSONObject envelope = record.getJSONObject(role);
        if (cipher == null) cipher = decryptCipher(envelope);
        cipher.updateAAD(aad(id, record, role, envelope.getString("alias")));
        byte[] plain = cipher.doFinal(Base64.decode(envelope.getString("ciphertext"), Base64.NO_WRAP));
        try { return new String(plain, StandardCharsets.UTF_8); }
        finally { Arrays.fill(plain, (byte) 0); }
    }
    private byte[] aad(String id, JSONObject record, String role, String alias) throws Exception {
        return ("1|" + id + "|" + record.getInt("revision") + "|" + record.getString("mode") + "|" + role + "|" + alias).getBytes(StandardCharsets.UTF_8);
    }
    private void removeAliases(JSONObject record) {
        for (String role : new String[]{"primary", "fallback"}) {
            try { if (record.has(role)) keyStore.deleteEntry(record.getJSONObject(role).getString("alias")); }
            catch (Exception ignored) { /* An inaccessible orphan never authorizes access. */ }
        }
    }
    private String digest(String key) throws Exception {
        byte[] bytes = MessageDigest.getInstance("SHA-256").digest(key.getBytes(StandardCharsets.UTF_8));
        StringBuilder encoded = new StringBuilder();
        for (byte value : bytes) encoded.append(Character.forDigit((value >>> 4) & 15, 16)).append(Character.forDigit(value & 15, 16));
        return encoded.toString();
    }
    private void complete(Pending operation, Object value) {
        if (pending != operation) return;
        pending = null; prompt = null; biometricCeremony = null; credentialCancellation = null;
        operation.result.success(value);
    }
    private void fail(Pending operation, Exception error) {
        if (pending != operation) return;
        String code = error instanceof Failure ? ((Failure) error).code
            : error instanceof KeyPermanentlyInvalidatedException ? "invalidated"
            // An expired/missing Keystore authorization is not biometric
            // lockout. Only BiometricPrompt's explicit lockout codes say that.
            : error instanceof UserNotAuthenticatedException ? "unavailable" : "storageFailed";
        pending = null; prompt = null; biometricCeremony = null; credentialCancellation = null;
        if (credentialRequest != null && credentialRequest.operation == operation) credentialRequest.continuation = null;
        if (!operation.committed) for (String alias : operation.newAliases) {
            try { keyStore.deleteEntry(alias); } catch (Exception ignored) {}
        }
        operation.result.error(code, "Credential operation could not be completed", null);
    }
    private void cancel() {
        deletionAuthorizations.clear();
        deletionReadAuthorizations.clear();
        Pending operation = pending;
        BiometricPrompt activePrompt = prompt;
        CancellationSignal activeCancellation = credentialCancellation;
        if (operation != null && activePrompt != null) {
            // Do not publish completion while AndroidX still owns this prompt.
            // An immediate new challenge would otherwise receive its stale
            // cancellation. A success already queued cannot authorize data.
            operation.cancellationRequested = true;
            activePrompt.cancelAuthentication();
        } else if (operation != null) fail(operation, new Failure("canceled"));
        if (activeCancellation != null) activeCancellation.cancel();
    }
    void dispose() {
        cancel();
        // There is no next ceremony after disposal; the Activity may never
        // deliver a terminal callback, so settle the outstanding result now.
        if (pending != null) fail(pending, new Failure("canceled"));
        activity.unregisterReceiver(lockReceiver); channel.setMethodCallHandler(null);
    }

    private void savePassword(Pending operation, MethodCall call) {
        String username = call.argument("username");
        String password = call.argument("password");
        if (Build.VERSION.SDK_INT < 34 || username == null || password == null || username.isEmpty() || password.isEmpty()) {
            complete(operation, "unavailable"); return;
        }
        credentialCancellation = new CancellationSignal();
        PasswordManager.save(activity, username, password, credentialCancellation, outcome -> {
            try { complete(operation, outcome); } catch (Exception error) { fail(operation, error); }
        });
    }

    /** Framework API avoids introducing an unavailable AndroidX dependency. */
    @androidx.annotation.RequiresApi(34)
    private static final class PasswordManager {
        static void save(Activity activity, String username, String password, CancellationSignal signal, ValueCallback callback) {
            try {
                android.credentials.CredentialManager manager = activity.getSystemService(android.credentials.CredentialManager.class);
                if (manager == null) { callback.accept("unavailable"); return; }
                android.os.Bundle data = new android.os.Bundle();
                data.putString("androidx.credentials.BUNDLE_KEY_ID", username);
                data.putString("androidx.credentials.BUNDLE_KEY_PASSWORD", password);
                android.credentials.CreateCredentialRequest request = new android.credentials.CreateCredentialRequest.Builder(
                    "android.credentials.TYPE_PASSWORD_CREDENTIAL", data, new android.os.Bundle()).build();
                manager.createCredential(activity, request, signal, activity.getMainExecutor(),
                    new android.os.OutcomeReceiver<android.credentials.CreateCredentialResponse, android.credentials.CreateCredentialException>() {
                        @Override public void onResult(android.credentials.CreateCredentialResponse result) {
                            try { callback.accept("accepted"); } catch (Exception ignored) {}
                            data.clear();
                        }
                        @Override public void onError(android.credentials.CreateCredentialException error) {
                            try { callback.accept(android.credentials.CreateCredentialException.TYPE_USER_CANCELED.equals(error.getType()) ? "declined" : "unavailable"); }
                            catch (Exception ignored) {}
                            data.clear();
                        }
                    });
            } catch (Exception ignored) { try { callback.accept("unavailable"); } catch (Exception ignoredAgain) {} }
        }
    }
}
