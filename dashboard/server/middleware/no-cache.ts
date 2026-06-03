// Polling-/API-Antworten dürfen nie gecached werden — sonst zeigt das
// Dashboard stale Heartbeats (Austin's Cache-Verdacht 28.05.).
// Greift NUR auf /api/* — Static + HTML laufen wie gewohnt.
export default defineEventHandler((event) => {
  if (event.path && event.path.startsWith('/api/')) {
    setResponseHeader(event, 'Cache-Control', 'no-store')
    setResponseHeader(event, 'Pragma', 'no-cache')
  }
})
