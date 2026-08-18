<template>
  <div class="column items-center justify-center q-pa-lg" style="min-height: 100vh">
    <div class="text-h4 text-weight-bold q-mb-xl">App</div>

    <q-btn
      class="full-width q-mb-md"
      color="white"
      text-color="grey-9"
      size="lg"
      unelevated
      rounded
      @click="loginWithGoogle"
    >
      <q-icon name="img:icons/google.svg" size="20px" class="q-mr-sm" />
      Continue with Google
    </q-btn>
  </div>
</template>

<script>
import { mapActions, mapState } from 'pinia'
import { useAuthStore } from 'src/stores/auth'

export default {
  name: 'LoginPage',

  computed: {
    // `mapState` covers getters as well as state, so this is the store's `isLoggedIn` getter.
    ...mapState(useAuthStore, ['isLoggedIn']),
  },

  watch: {
    // `immediate` because the usual case is arriving here already signed in — the Firebase
    // session is restored during boot, so by the time this page renders the answer is often
    // already yes and no change event would ever come.
    isLoggedIn: {
      immediate: true,
      handler(loggedIn) {
        if (loggedIn) this.$router.push('/')
      },
    },
  },

  methods: {
    // Mapped straight off the store rather than wrapped: the browser and the Android app reach
    // Firebase by different routes (see the store's `loginWithGoogle`), and a page should not
    // have to know which one it is running in.
    //
    // Facebook was dropped rather than hidden on native. Facebook refuses embedded-WebView
    // OAuth for the same reason Google does, so a second provider here would be a button that
    // works in the browser and silently fails in the app — see `docs/android_capacitor.md` §3.
    ...mapActions(useAuthStore, ['loginWithGoogle']),
  },
}
</script>
