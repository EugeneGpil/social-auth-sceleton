import { defineStore, acceptHMRUpdate } from 'pinia'
import { Capacitor } from '@capacitor/core'
import { auth } from 'src/boot/firebase'
import {
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithCredential,
  signInWithPopup,
  signOut,
} from 'firebase/auth'
import { api, TOKEN_KEY } from 'src/api'

/**
 * Is this the packaged Android app rather than a browser?
 *
 * The one thing that branches on it is sign-in (see `loginWithGoogle`). `Capacitor` is safe to
 * import in the browser build — with no native bridge injected it simply answers `false`.
 */
const isNativeApp = () => Capacitor.isNativePlatform()

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    ready: false,
  }),

  getters: {
    isLoggedIn: (state) => !!state.user,
  },

  actions: {
    init() {
      return new Promise((resolve) => {
        onAuthStateChanged(auth, async (firebaseUser) => {
          if (firebaseUser) {
            if (!localStorage.getItem(TOKEN_KEY)) {
              await this._syncWithBackend(firebaseUser)
            }
            this.user = firebaseUser
          } else {
            this.user = null
            localStorage.removeItem(TOKEN_KEY)
          }
          this.ready = true
          resolve(this.user)
        })
      })
    },

    /**
     * Sign in with Google. Resolves to the user, or null if it did not happen.
     *
     * Two implementations, because the packaged Android app cannot use the web one: Google
     * refuses OAuth from an embedded WebView (`403 disallowed_useragent`), and a WebView has
     * no popup to open in the first place — the request escapes to whatever browser the phone
     * has, which then has no opener to hand the result back to. It fails with nothing on
     * screen. See `docs/android_capacitor.md` §3.
     *
     * So on a device the account picker comes from Play services via Credential Manager, and
     * only the resulting Google ID token crosses into the web layer, where it is exchanged for
     * exactly the same Firebase session the browser build gets. That last part is why
     * `skipNativeAuth: true` is set in `capacitor.config.json`: everything in this app —
     * `init()`'s `onAuthStateChanged`, `_syncWithBackend`, the API token — belongs to the
     * Firebase **JS** SDK, so signing in only on the native side would leave the app looking
     * signed out while Android considered it signed in.
     */
    async loginWithGoogle() {
      if (isNativeApp()) return this._loginWithGoogleNatively()

      const provider = new GoogleAuthProvider()
      return signInWithPopup(auth, provider)
        .then(({ user }) => user)
        .catch(() => null)
    },

    /**
     * The Android path: native account picker, then the same `auth` instance as everywhere
     * else.
     *
     * Loaded on demand so the browser build never pulls the plugin into its startup path —
     * this is one bundle serving both, since the app renders the deployed site (§2).
     *
     * Unlike the popup above, a failure here is logged rather than silently becoming `null`.
     * A dismissed picker and a missing or stale `google-services.json` look identical from the
     * button, and the second one is not something the user can fix by pressing it again.
     */
    async _loginWithGoogleNatively() {
      try {
        const { FirebaseAuthentication } = await import('@capacitor-firebase/authentication')
        const { credential } = await FirebaseAuthentication.signInWithGoogle()

        const idToken = credential?.idToken
        if (!idToken) throw new Error('The native sign-in returned no Google ID token.')

        const { user } = await signInWithCredential(auth, GoogleAuthProvider.credential(idToken))

        return user
      } catch (err) {
        console.error('Native Google sign-in failed', err)
        return null
      }
    },

    async _syncWithBackend(firebaseUser) {
      const idToken = await firebaseUser.getIdToken()
      const {
        data: { token },
      } = await api.post('auth/firebase', { id_token: idToken })
      localStorage.setItem(TOKEN_KEY, token)
    },

    async logout() {
      await api.post('auth/logout').catch(() => {})
      localStorage.removeItem(TOKEN_KEY)
      await signOut(auth)
      this.user = null
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAuthStore, import.meta.hot))
}
