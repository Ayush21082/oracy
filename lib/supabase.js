const { env } = require('./adminAuth')

async function supabaseFetch(path, { method = 'GET', body, prefer } = {}) {
  const url = `${env('SUPABASE_URL').replace(/\/$/, '')}/rest/v1/${path}`
  const headers = {
    apikey: env('SUPABASE_SERVICE_ROLE_KEY'),
    Authorization: `Bearer ${env('SUPABASE_SERVICE_ROLE_KEY')}`,
    'Content-Type': 'application/json',
    Prefer: prefer || (method === 'GET' ? 'return=representation' : 'return=representation')
  }
  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  })
  const text = await res.text()
  let data
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = text
  }
  if (!res.ok) {
    const err = new Error(typeof data === 'object' ? JSON.stringify(data) : String(data))
    err.status = res.status
    err.body = data
    throw err
  }
  return data
}

module.exports = { supabaseFetch }
