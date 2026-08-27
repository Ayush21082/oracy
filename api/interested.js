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
    let size = 0
    req.on('data', (c) => {
      size += c.length
      if (size > 4096) {
        reject(new Error('Payload too large'))
        return
      }
      chunks.push(c)
    })
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

function normalizeEmail(raw) {
  return String(raw || '')
    .trim()
    .toLowerCase()
}

function isValidEmail(email) {
  // Practical validation — not a full RFC parser.
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) && email.length <= 254
}

// Simple in-memory rate limit per IP (best-effort on serverless).
const hits = new Map()
function rateLimited(ip) {
  const now = Date.now()
  const windowMs = 60_000
  const max = 8
  const entry = hits.get(ip) || { count: 0, start: now }
  if (now - entry.start > windowMs) {
    entry.count = 0
    entry.start = now
  }
  entry.count += 1
  hits.set(ip, entry)
  return entry.count > max
}

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.statusCode = 204
    return res.end()
  }
  if (req.method !== 'POST') {
    return json(res, 405, { error: 'Method not allowed' })
  }

  try {
    const ip =
      (req.headers['x-forwarded-for'] || '').toString().split(',')[0].trim() ||
      req.socket?.remoteAddress ||
      'unknown'
    if (rateLimited(ip)) {
      return json(res, 429, { error: 'Too many tries. Please wait a moment.' })
    }

    const body = await readBody(req)
    const email = normalizeEmail(body.email)
    if (!isValidEmail(email)) {
      return json(res, 400, { error: 'Enter a valid email address.' })
    }

    const url = `${env('SUPABASE_URL').replace(/\/$/, '')}/rest/v1/interested`
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        apikey: env('SUPABASE_SERVICE_ROLE_KEY'),
        Authorization: `Bearer ${env('SUPABASE_SERVICE_ROLE_KEY')}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal'
      },
      body: JSON.stringify({ email })
    })

    if (response.status === 201 || response.status === 200) {
      return json(res, 200, { ok: true, status: 'created' })
    }

    const text = await response.text()
    let errBody = {}
    try {
      errBody = text ? JSON.parse(text) : {}
    } catch {
      errBody = { message: text }
    }

    // Unique violation
    if (
      response.status === 409 ||
      errBody.code === '23505' ||
      String(errBody.message || '').toLowerCase().includes('duplicate') ||
      String(errBody.details || '').toLowerCase().includes('already exists')
    ) {
      return json(res, 200, {
        ok: true,
        status: 'duplicate',
        message: 'You’re already on the list — we’ll be in touch.'
      })
    }

    return json(res, 500, { error: 'Couldn’t save that email. Try again.' })
  } catch (err) {
    return json(res, 500, { error: err.message || 'Server error' })
  }
}
