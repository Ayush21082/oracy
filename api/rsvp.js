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

function normalizeEmail(raw) {
  const email = String(raw || '').trim().toLowerCase()
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return null
  return email
}

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.statusCode = 204
    return res.end()
  }
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' })

  try {
    const body = await readBody(req)
    // Honeypot — bots fill hidden fields
    if (body.company || body.website) return json(res, 200, { ok: true })

    const email = normalizeEmail(body.email)
    if (!email) return json(res, 400, { error: 'Enter a valid email' })

    const url = `${env('SUPABASE_URL').replace(/\/$/, '')}/rest/v1/waitlist_rsvps?on_conflict=email`
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        apikey: env('SUPABASE_SERVICE_ROLE_KEY'),
        Authorization: `Bearer ${env('SUPABASE_SERVICE_ROLE_KEY')}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal,resolution=merge-duplicates'
      },
      body: JSON.stringify({
        email,
        source: typeof body.source === 'string' ? body.source.slice(0, 40) : 'website'
      })
    })

    if (response.status === 409) {
      return json(res, 200, { ok: true, already: true })
    }

    if (!response.ok) {
      const text = await response.text()
      // Unique violation often 409; PostgREST may return 23505 in body
      if (text.includes('23505') || text.toLowerCase().includes('duplicate')) {
        return json(res, 200, { ok: true, already: true })
      }
      throw new Error(text || 'Could not save RSVP')
    }

    return json(res, 200, { ok: true })
  } catch (err) {
    return json(res, 500, { error: 'Something went wrong. Try again in a moment.' })
  }
}
