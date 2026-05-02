const BASE = import.meta.env.VITE_API_URL

export const TOKEN_KEY = 'sanctum_token'

async function request(method, path, body) {
  const token = localStorage.getItem(TOKEN_KEY)
  const res = await fetch(`${BASE}/api/${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

export const api = {
  get: (path) => request('GET', path),
  post: (path, body) => request('POST', path, body),
}