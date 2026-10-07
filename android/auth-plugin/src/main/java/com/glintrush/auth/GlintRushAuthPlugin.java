package com.glintrush.auth;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.ByteBuffer;
import java.security.KeyStore;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Minimal Android bridge: browser launch, strict deep-link capture, and encrypted token storage. */
public final class GlintRushAuthPlugin extends GodotPlugin {
    private static final String KEY_ALIAS = "glint-rush-auth-v1";
    private static final String PREFS = "glint_rush_auth_secure";
    private static final String[] ALLOWED_KEYS = {"refresh_token", "pkce_verifier", "pkce_state"};
    private static final String CALLBACK_SCHEME = "glintrush";
    private static final String CALLBACK_HOST = "auth";
    private static final String CALLBACK_PATH = "/callback";
    private String pendingCallback = "";

    public GlintRushAuthPlugin(Godot godot) {
        super(godot);
        captureIntent(getActivity() == null ? null : getActivity().getIntent());
    }

    @Override
    public String getPluginName() { return "GlintRushAuth"; }

    @Override
    public void onMainResume() {
        Activity activity = getActivity();
        captureIntent(activity == null ? null : activity.getIntent());
    }

    @UsedByGodot
    public boolean openExternalUrl(String address) {
        Uri uri = Uri.parse(address == null ? "" : address);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) return false;
        Activity activity = getActivity();
        if (activity == null) return false;
        try {
            activity.startActivity(new Intent(Intent.ACTION_VIEW, uri));
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    @UsedByGodot
    public synchronized String popAuthCallback() {
        captureIntent(getActivity() == null ? null : getActivity().getIntent());
        String value = pendingCallback;
        pendingCallback = "";
        return value;
    }

    @UsedByGodot
    public boolean storeSecureValue(String key, String value) {
        if (!isAllowedKey(key) || value == null) return false;
        try {
            SecretKey secret = getOrCreateKey();
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, secret);
            cipher.updateAAD(key.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            byte[] nonce = cipher.getIV();
            byte[] ciphertext = cipher.doFinal(value.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            ByteBuffer packed = ByteBuffer.allocate(nonce.length + ciphertext.length);
            packed.put(nonce).put(ciphertext);
            return prefs().edit().putString(key, Base64.encodeToString(packed.array(), Base64.NO_WRAP)).commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    @UsedByGodot
    public String getSecureValue(String key) {
        if (!isAllowedKey(key)) return "";
        String encoded = prefs().getString(key, "");
        if (encoded.isEmpty()) return "";
        try {
            byte[] packed = Base64.decode(encoded, Base64.NO_WRAP);
            if (packed.length <= 12) return "";
            byte[] nonce = Arrays.copyOfRange(packed, 0, 12);
            byte[] ciphertext = Arrays.copyOfRange(packed, 12, packed.length);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), new GCMParameterSpec(128, nonce));
            cipher.updateAAD(key.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return new String(cipher.doFinal(ciphertext), java.nio.charset.StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return "";
        }
    }

    @UsedByGodot
    public boolean removeSecureValue(String key) {
        if (!isAllowedKey(key)) return false;
        return prefs().edit().remove(key).commit();
    }

    private synchronized void captureIntent(Intent intent) {
        if (intent == null || intent.getData() == null) return;
        Uri uri = intent.getData();
        if (CALLBACK_SCHEME.equals(uri.getScheme()) && CALLBACK_HOST.equals(uri.getHost()) && CALLBACK_PATH.equals(uri.getPath())) {
            pendingCallback = uri.toString();
            intent.setData(null);
        }
    }

    private boolean isAllowedKey(String key) {
        if (key == null) return false;
        for (String allowed : ALLOWED_KEYS) if (allowed.equals(key)) return true;
        return false;
    }

    private SharedPreferences prefs() {
        return getActivity().getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
    }

    private SecretKey getOrCreateKey() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        java.security.Key existing = store.getKey(KEY_ALIAS, null);
        if (existing instanceof SecretKey) return (SecretKey) existing;
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build());
        return generator.generateKey();
    }
}
