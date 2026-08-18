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

<script setup>
import { watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from 'src/stores/auth'

const router = useRouter()
const authStore = useAuthStore()

watch(
  () => authStore.isLoggedIn,
  (loggedIn) => {
    if (loggedIn) router.push('/')
  },
  { immediate: true },
)

// Google only, and the sign-in itself lives in the store: the browser and the Android app
// reach Firebase by different routes (see `loginWithGoogle`), and a page should not have to
// know which one it is running in.
//
// Facebook was dropped rather than hidden on native. Facebook refuses embedded-WebView OAuth
// for the same reason Google does, so a second provider here would be a button that works in
// the browser and silently fails in the app — see `docs/android_capacitor.md` §3.
const loginWithGoogle = () => authStore.loginWithGoogle()
</script>
