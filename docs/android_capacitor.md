# The Android app

The Android build is a **Capacitor WebView shell that renders the deployed site** rather than a bundled
copy of the front end. One `make` target produces a sideloadable APK; the app's UI is whatever
`server.url` points at, so a normal front deploy ships app updates without a Play release.

Everything here has been measured on a device, not inferred. The two things that are *not* free — Google
sign-in and WebAuthn — each need a specific piece of configuration, and both fail silently when it is
missing. That is what most of this document is about.

---

## 1. Why a remote URL and not bundled assets

`capacitor.config.json` sets `server.url`. The alternative — `quasar build -m capacitor`, assets served
from `https://localhost` — is a **different origin**, and that difference is not cosmetic:

- **WebAuthn breaks permanently.** `rpId` is derived from the origin. A passkey registered against
  `app.example.com` cannot be asserted from an `rpId` of `localhost`, so every existing credential
  becomes unusable. If the app ever wraps a data key under a passkey (the PRF pattern), bundling is a
  one-way loss of user data triggered by a build-config change.
- **Same-origin API access goes away.** In production nginx routes `/api`, `/storage` and `/sanctum` to
  Laravel on the front end's own origin, so `VITE_API_URL` can stay empty. From `https://localhost`
  every request is cross-origin and `VITE_API_URL` must name a real host.
- **Firebase's authorised domains** are configured per origin too.

`server.url` avoids all three by simply keeping the origin the site already has. The Capacitor bridge
works fine against a remote URL — that is exactly what `quasar dev -m capacitor -T android` does against
a LAN dev server — so nothing is given up.

The cost is that the app needs a network connection to render at all. The service worker mitigates it
after the first launch, and if a genuinely offline-first shell is ever wanted, the safe form is
`server.hostname` set to the real domain (which keeps the origin) with the API moved to a *different*
host. That is a deploy-layout decision, not a config tweak.

**Trade-off worth knowing:** the plain alternative to all of this is a Trusted Web Activity (Bubblewrap),
where Google sign-in and WebAuthn both work with zero native code. Its one drawback is that Chrome shows
a "Running in Chrome" disclosure on first launch, once per install, and no manifest or asset-links change
removes it — it is Chrome's own UI. Losing that bar is the entire reason for the WebView route. If the
bar does not bother you, the TWA is less work.

---

## 2. What must be changed per project

The repo ships placeholders in four files. All four have to agree, and `make capacitor-sync` /
`capacitor-debug` print a warning while the first two are still unset.

| File | Value | Placeholder |
| --- | --- | --- |
| `front/src-capacitor/capacitor.config.json` | `appId` | `com.example.app` |
| `front/src-capacitor/capacitor.config.json` | `server.url` | `https://app.example.com` |
| `front/src-capacitor/capacitor.config.json` | `appName` | `App` |
| `front/src-capacitor/android/app/build.gradle` | `namespace`, `applicationId` | `com.example.app` |
| `front/src-capacitor/android/app/src/main/res/values/strings.xml` | all four strings | `App` / `com.example.app` |
| `front/src-capacitor/android/app/src/main/java/…/MainActivity.java` | package + directory path | `com/example/app` |

`com.example.*` is deliberate: Play rejects it at upload, so the placeholder cannot ship by accident.

**The application id is permanent.** Once an AAB is uploaded to Play it can never change for that
listing, and it is also the identity used by `google-services.json` and by `assetlinks.json`. Choose it
before the first upload, not after.

`server.url` must be **https**. A cleartext URL additionally needs a network-security-config exception,
and Firebase auth will not work over http anyway.

---

## 3. Google sign-in: why the web path cannot work here

`signInWithPopup` fails **twice over** in an embedded WebView, and this is confirmed on-device, not
theoretical:

1. There is no popup. The OAuth URL escapes to whatever browser the phone has, the Firebase handler
   loads there, finds no opener to `postMessage` its result to, and closes the tab. The app is never told
   anything — and if the caller swallows the rejection, there is not even a message on screen.
2. Google has refused OAuth from embedded WebViews since 2021 (`403: disallowed_useragent`). There is no
   user-agent workaround worth building; the whole point of the restriction is that an app hosting a
   WebView could read the password out of it.

Facebook refuses embedded WebViews for the same reason, which is why this skeleton has a Google button
only. Adding a second provider means either its own native plugin path or a button that works in the
browser and silently fails in the app.

### The native path

`front/src/stores/auth.js` branches on `Capacitor.isNativePlatform()`:

- **Browser** — `signInWithPopup`, unchanged.
- **App** — `FirebaseAuthentication.signInWithGoogle()` from
  `@capacitor-firebase/authentication`, which shows the Play services account-picker sheet, then
  `signInWithCredential(auth, GoogleAuthProvider.credential(idToken))` on the **same JS-SDK `auth`
  instance** as the browser build.

That last step is what `"skipNativeAuth": true` in `capacitor.config.json` exists for. This app's entire
session lives in the Firebase **JS** SDK — `onAuthStateChanged`, `_syncWithBackend`, the Sanctum token —
so signing in only on the native layer would leave the app looking signed out while Android considered it
signed in. With `skipNativeAuth`, the plugin hands back a credential instead of establishing its own
session, and the web layer finishes the job. Same Firebase `uid`, same backend user, same everything
downstream.

The plugin is imported dynamically so the browser bundle never pulls it into its startup path — one
bundle serves both, since the app renders the deployed site.

**No backend change is needed.** `POST /api/auth/firebase` verifies a Firebase ID token and mints a
Sanctum token; where the Firebase session came from is invisible to it.

### Firebase Console setup (required, and its failure mode is invisible)

Project settings → General → Your apps → **Add app → Android**, package name = your `applicationId`.

The registration wizard has no fingerprint field. They go in afterwards, under **Add fingerprint**, and
**both are needed**. Get them from the debug keystore that `make capacitor-debug` generates
(`docker/volumes/android_home/debug.keystore`, storepass `android`):

```
make capacitor CMD="keytool -list -v \
  -keystore /home/app/.android/debug.keystore \
  -storepass android -alias androiddebugkey" | grep -E 'SHA1:|SHA256:'
```

(The keystore does not exist until the first `make capacitor-debug` has run — Gradle generates it.
The label really is `SHA256:` with no hyphen, unlike the `SHA-256` older keytool printed and unlike
the console's own labels; grepping for the hyphenated form silently returns only the SHA-1.)

**SHA-1 is not optional, and its absence is invisible in the console.** A freshly registered Android app's
`google-services.json` contains only the *web* OAuth client (`client_type: 3`). The Android client
(`client_type: 1`) is created when the first SHA-1 lands. Until it exists, native Google sign-in fails
with a generic developer error and nothing in the console looks wrong.

So: add both fingerprints, **then re-download** `google-services.json` — the first download is stale by
construction — and put it at `front/src-capacitor/android/app/google-services.json`.

Verify what you actually got before building:

```
node -e "const j=require('./front/src-capacitor/android/app/google-services.json');
j.client.forEach(c => console.log(c.client_info.android_client_info.package_name,
  (c.oauth_client||[]).map(o=>o.client_type)))"
```

Expect your package name with **both `1` and `3`** present.

That file is meant to be **committed**. It is compiled into every shipped APK and its keys are scoped to
the package name plus the registered fingerprints, so it is configuration rather than a secret, and
committing it is what lets a fresh clone build without a trip to the console. The *signing keystore* is
the actual secret, and it stays out of git (`.gitignore`).

`app/build.gradle` applies the `google-services` plugin only when the file is present, so the APK still
builds without it — with native sign-in broken. That is convenient for checking the toolchain and a trap
if you forget which state you are in.

---

## 4. WebAuthn in a WebView

`MainActivity.java` calls `setWebAuthenticationSupport(WEB_AUTHENTICATION_SUPPORT_FOR_APP)`.

**A WebView exposes no `PublicKeyCredential` until the app asks for it.** That default is what every
"passkeys don't work in WebViews" answer online is actually describing. The opt-in routes the page's
WebAuthn calls through Play services Credential Manager — the same path a native app takes — reaching the
passkeys in Google Password Manager.

Nothing in this skeleton uses WebAuthn yet. The call is here because the default is silent: without it,
feature detection in the page simply finds no API, and a passkey feature added later looks unsupported on
Android for no visible reason.

Two things do not come from this file, and both are needed for it to be useful:

- `androidx.webkit` as an explicit dependency in `app/build.gradle`. `capacitor-android` already depends
  on it, but as an `implementation` dependency of a library module, so its classes are not on this
  module's compile classpath — `MainActivity` cannot see `WebSettingsCompat` without the line.
- `get_login_creds` in the site's `/.well-known/assetlinks.json`, with this app's **signing
  certificate** SHA-256 listed. Without it Credential Manager refuses the request, and the refusal looks
  nothing like a configuration error.

The support level is logged rather than assumed — `adb logcat -s App`, expect `WebAuthn support level: 1`
(0 is NONE, 1 is FOR_APP). A silent no-op here and a dropped `prf` extension look identical from the
page and are fixed in completely different places.

`isFeatureSupported` is a check on the **WebView APK installed on the device**, not on the Android
version. An old system WebView answers false and there is nothing the app can do about it.

Measured, for the record: the `prf` extension **does** survive the trip through Credential Manager on a
current WebView, and produces the same output Chrome does.

---

## 5. Building

The toolchain is containerised (`docker/capacitor/Dockerfile`, compose profile `capacitor`), so no JDK or
Android SDK is needed on the host. JDK 21 and Debian trixie, because the generated project compiles at
Java 21 and Debian 12 has no `openjdk-21` in any repo.

```
make capacitor-install   # once, and after any dependency change
make capacitor-sync      # after any edit to capacitor.config.json
make capacitor-debug     # → front/src-capacitor/android/app/build/outputs/apk/debug/app-debug.apk
```

- `capacitor-install` is not optional and not obvious: `capacitor.settings.gradle` declares the plugin
  subprojects as paths inside `../node_modules`, so without it Gradle fails at settings evaluation with a
  path error that mentions nothing about npm.
- `capacitor-sync` is what copies `capacitor.config.json` into `app/src/main/assets/`. Editing that file
  does nothing until this runs. It also copies `webDir`, and refuses to run when the directory is
  missing — the target creates a placeholder `www/index.html`, never rendered because the app loads
  `server.url`.
- `adb` is deliberately absent from the image (a container has no USB). Sideload from the host:
  `adb install -r <path>`.

Debug builds carry `versionNameSuffix "-dev"` but **the same package name** as a release build, because
every id has to exist in `google-services.json` and the `google-services` plugin fails the build outright
for one that does not. One package means one Android app to register, with one set of fingerprints. The
consequence: a debug build and a Play-signed build cannot coexist on a phone — `adb uninstall <appId>`
first, since the debug key is not Play's.

---

## 6. Before shipping to Play

The debug APK is not shippable. What is still missing:

- **Release signing** — a `signingConfigs` block in `app/build.gradle` reading a gitignored
  `key.properties`, pointing at an upload keystore kept outside the repo.
- **`versionCode`** strictly increasing, forever after. It is `1` today.
- **The Play App Signing certificate.** This is the classic production-only breakage and it hits both
  mechanisms at once: Play re-signs the AAB, so the app your users run is signed with a certificate that
  is registered nowhere by default. Its **SHA-1 must go into the Firebase console** or Google sign-in
  fails in production only, and its **SHA-256 into `assetlinks.json`** or WebAuthn fails in production
  only. Both are in Play Console → Test and release → App integrity. Do not discover this after rollout.
- **Icons and splash** — still the Capacitor template's.
- A decision on whether the release build keeps `server.url`. It can, and that is what keeps the origin
  stable and lets a front deploy ship app updates without a Play release.
- A **privacy policy URL** and an in-app **account deletion** path, both required by Play policy for any
  app with accounts. The skeleton has neither.

---

## Sources

- [Authenticate users with WebView — Android Developers](https://developer.android.com/identity/sign-in/credential-manager-webview)
- [androidx.webkit release notes](https://developer.android.com/jetpack/androidx/releases/webkit)
- [Upcoming security changes to Google's OAuth 2.0 endpoint in embedded webviews](https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/)
- [@capacitor-firebase/authentication — Firebase JS SDK usage](https://github.com/capawesome-team/capacitor-firebase/blob/main/packages/authentication/docs/firebase-js-sdk.md)
- [WebAuthn origin validation in native apps — Corbado](https://www.corbado.com/blog/webauthn-origin-validation-native-apps)
