package com.example.app;

import android.os.Bundle;
import android.util.Log;

import androidx.webkit.WebSettingsCompat;
import androidx.webkit.WebViewFeature;

import com.getcapacitor.BridgeActivity;

/**
 * The WebView shell (`docs/android_capacitor.md`). One behaviour beyond the Capacitor
 * template, and the whole reason this file is not empty: WebAuthn.
 *
 * **A WebView exposes no `PublicKeyCredential` until the app asks for it.** That default is
 * what every "passkeys don't work in WebViews" answer online is describing.
 * `WEB_AUTHENTICATION_SUPPORT_FOR_APP` routes the page's WebAuthn calls through Play services
 * Credential Manager — the same path a fully native app takes — which reaches the passkeys in
 * Google Password Manager.
 *
 * Nothing in this skeleton uses WebAuthn yet. The call is here because the default is silent:
 * without it, feature-detection in the page simply finds no API and any passkey feature added
 * later looks unsupported on Android for no visible reason. Two further requirements come with
 * it, and they are not in this file — `get_login_creds` in the site's
 * /.well-known/assetlinks.json, and this app's signing certificate registered there.
 *
 * Two things this cannot fix, so it reports rather than hides them:
 *
 *   - `isFeatureSupported` is a check on the **WebView APK installed on the device**, not on
 *     the Android version. An old system WebView answers false and there is nothing to be done
 *     about it from here.
 *   - Whether the `prf` extension survives the trip through Credential Manager is
 *     undocumented. It does on a current WebView (measured), but a `PrfUnsupportedError` in
 *     the page is a different failure from the opt-in not taking, and the log line below is
 *     what tells the two apart.
 */
public class MainActivity extends BridgeActivity {
    private static final String TAG = "App";

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // The bridge, and therefore the WebView whose settings are changed below, is created
        // here — nothing before this line can reach it.
        super.onCreate(savedInstanceState);

        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION)) {
            Log.w(TAG, "This WebView has no WebAuthn support. "
                + "Needs a current Android System WebView.");
            return;
        }

        WebSettingsCompat.setWebAuthenticationSupport(
            getBridge().getWebView().getSettings(),
            WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_FOR_APP
        );

        // Read back rather than assumed: 0 is NONE, 1 is FOR_APP. A silent no-op here and a
        // dropped `prf` extension look identical from the page, and they are fixed in
        // completely different places.
        Log.i(TAG, "WebAuthn support level: " + WebSettingsCompat.getWebAuthenticationSupport(
            getBridge().getWebView().getSettings()));
    }
}
