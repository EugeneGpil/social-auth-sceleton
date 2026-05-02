import { defineStore, acceptHMRUpdate } from 'pinia'
import { auth } from 'src/boot/firebase'
import { onAuthStateChanged, signOut } from 'firebase/auth'

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
        onAuthStateChanged(auth, (user) => {
          this.user = user
          this.ready = true
          resolve(user)
        })
      })
    },

    async logout() {
      await signOut(auth)
      this.user = null
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAuthStore, import.meta.hot))
}