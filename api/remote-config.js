const crypto = require('crypto')

function env(name) {
  const v = process.env[name]
  if (!v) throw new Error(`Missing env ${name}`)
  return v
}

function json(res, status, body) {
  res.statusCode = status
  res.setHeader('Content-Type', 'application/json; charset=utf-8')
  res.setHeader('Cache-Control', 'no-store')
  res.setHeader('X-Content-Type-Options', 'nosniff')
  res.end(JSON.stringify(body))
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = []
    req.on('data', (c) => chunks.push(c))
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8')
      if (!raw) return resolve({})
      try {
        resolve(JSON.parse(raw))
      } catch {
        reject(new Error('Invalid JSON'))
      }
    })
    req.on('error', reject)
  })
}

function timingSafeEqualString(a, b) {
  const aa = Buffer.from(String(a))
  const bb = Buffer.from(String(b))
  if (aa.length !== bb.length) {
    crypto.timingSafeEqual(aa, aa)
    return false
  }
  return crypto.timingSafeEqual(aa, bb)
}

function issueToken(password) {
  const secret = env('ADMIN_PASSWORD')
  if (!timingSafeEqualString(password, secret)) return null
  const exp = Date.now() + 12 * 60 * 60 * 1000
  const payload = Buffer.from(JSON.stringify({ role: 'admin', exp })).toString('base64url')
  const sig = crypto.createHmac('sha256', secret).update(payload).digest('base64url')
  return `${payload}.${sig}`
}

function verifyToken(token) {
  if (!token || typeof token !== 'string' || !token.includes('.')) return false
  const secret = env('ADMIN_PASSWORD')
  const [payload, sig] = token.split('.')
  const expected = crypto.createHmac('sha256', secret).update(payload).digest('base64url')
  if (!timingSafeEqualString(sig, expected)) return false
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
    return data.role === 'admin' && typeof data.exp === 'number' && data.exp > Date.now()
  } catch {
    return false
  }
}

function getBearer(req) {
  const h = req.headers.authorization || ''
  const m = /^Bearer\s+(.+)$/i.exec(h)
  return m ? m[1].trim() : ''
}

async function supabaseFetch(path, { method = 'GET', body } = {}) {
  const url = `${env('SUPABASE_URL').replace(/\/$/, '')}/rest/v1/${path}`
  const res = await fetch(url, {
    method,
    headers: {
      apikey: env('SUPABASE_SERVICE_ROLE_KEY'),
      Authorization: `Bearer ${env('SUPABASE_SERVICE_ROLE_KEY')}`,
      'Content-Type': 'application/json',
      Prefer: method === 'PATCH' ? 'return=representation' : 'return=representation'
    },
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
    throw err
  }
  return data
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', 'null')
  res.setHeader('Access-Control-Allow-Methods', 'GET, PATCH, POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type')
  if (req.method === 'OPTIONS') {
    res.statusCode = 204
    return res.end()
  }

  try {
    const url = new URL(req.url, 'http://localhost')
    const action = url.searchParams.get('action') || 'list'

    if (req.method === 'POST' && action === 'login') {
      const body = await readBody(req)
      const token = issueToken(body.password || '')
      if (!token) return json(res, 401, { error: 'Invalid password' })
      return json(res, 200, { token, expiresInHours: 12 })
    }

    const token = getBearer(req)
    if (!verifyToken(token)) return json(res, 401, { error: 'Unauthorized' })

    if (req.method === 'GET' && action === 'list') {
      const rows = await supabaseFetch(
        'remote_config?select=key,value,description,updated_at&order=key.asc'
      )
      return json(res, 200, { rows })
    }

    if (req.method === 'PATCH' && action === 'update') {
      const body = await readBody(req)
      const key = String(body.key || '').trim()
      if (!/^[a-z0-9_]{3,64}$/.test(key)) {
        return json(res, 400, { error: 'Invalid key' })
      }
      if (typeof body.value !== 'boolean') {
        return json(res, 400, { error: 'value must be boolean' })
      }
      const rows = await supabaseFetch(
        `remote_config?key=eq.${encodeURIComponent(key)}`,
        { method: 'PATCH', body: { value: body.value } }
      )
      if (!Array.isArray(rows) || rows.length === 0) {
        return json(res, 404, { error: 'Key not found' })
      }
      return json(res, 200, { row: rows[0] })
    }

    return json(res, 405, { error: 'Method not allowed' })
  } catch (err) {
    const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 500
    return json(res, status, { error: err.message || 'Server error' })
  }
}
