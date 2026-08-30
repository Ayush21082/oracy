const { issueToken, requireAdmin } = require('../lib/adminAuth')
const { supabaseFetch } = require('../lib/supabase')
const {
  emailStatus,
  defaultInviteTemplate,
  sendEmail,
  isEmailConfigured
} = require('../lib/email')

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
      if (size > 200_000) {
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

function isUuid(v) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    String(v || '')
  )
}

module.exports = async function handler(req, res) {
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

    if (!requireAdmin(req)) return json(res, 401, { error: 'Unauthorized' })

    if (req.method === 'GET' && action === 'list') {
      const status = url.searchParams.get('status') // not_sent | sent | all
      let path =
        'interested?select=id,email,created_at,invite_status,invite_sent_at&order=created_at.desc'
      if (status === 'not_sent' || status === 'sent') {
        path += `&invite_status=eq.${status}`
      }
      const rows = await supabaseFetch(path)
      return json(res, 200, {
        rows: rows || [],
        email: emailStatus(),
        template: defaultInviteTemplate()
      })
    }

    if (req.method === 'POST' && action === 'send') {
      if (!isEmailConfigured()) {
        const email = emailStatus()
        const needed = email.missing?.length
          ? email.missing.join(', ')
          : 'EMAIL_PROVIDER=resend, RESEND_API_KEY, EMAIL_FROM'
        return json(res, 503, {
          error: `Email is not configured. Set ${needed} on Vercel, then redeploy. Invites will not be marked Sent until mail actually sends.`,
          code: 'EMAIL_NOT_CONFIGURED',
          email
        })
      }

      const body = await readBody(req)
      const ids = Array.isArray(body.ids) ? body.ids.filter(isUuid) : []
      if (ids.length === 0) return json(res, 400, { error: 'Select at least one person.' })
      if (ids.length > 200) return json(res, 400, { error: 'Select at most 200 people at once.' })

      const subject = String(body.subject || '').trim()
      const text = String(body.body || '').trim()
      if (!subject || !text) return json(res, 400, { error: 'Subject and body are required.' })

      const resendAlready = Boolean(body.resendAlreadySent)

      const inList = ids.map(encodeURIComponent).join(',')
      const people = await supabaseFetch(
        `interested?id=in.(${inList})&select=id,email,invite_status,invite_sent_at`
      )

      const byId = new Map((people || []).map((p) => [p.id, p]))
      const results = { sent: [], skipped: [], failed: [] }

      for (const id of ids) {
        const person = byId.get(id)
        if (!person) {
          results.failed.push({ id, email: null, error: 'Not found' })
          continue
        }
        if (person.invite_status === 'sent' && !resendAlready) {
          results.skipped.push({
            id: person.id,
            email: person.email,
            reason: 'Invite already sent'
          })
          continue
        }

        try {
          const sent = await sendEmail({ to: person.email, subject, body: text })
          const now = new Date().toISOString()
          try {
            await supabaseFetch(`interested?id=eq.${encodeURIComponent(person.id)}`, {
              method: 'PATCH',
              body: { invite_status: 'sent', invite_sent_at: now }
            })
          } catch (patchErr) {
            results.failed.push({
              id: person.id,
              email: person.email,
              error:
                `Mail sent (${sent.id || 'ok'}) but status was not saved: ${patchErr.message || 'update failed'}`,
              code: 'STATUS_UPDATE_FAILED'
            })
            continue
          }
          results.sent.push({
            id: person.id,
            email: person.email,
            invite_sent_at: now,
            providerId: sent.id || null
          })
        } catch (err) {
          results.failed.push({
            id: person.id,
            email: person.email,
            error: err.message || 'Send failed',
            code: err.code || null
          })
        }
      }

      return json(res, 200, {
        ok: true,
        summary: {
          sent: results.sent.length,
          skipped: results.skipped.length,
          failed: results.failed.length
        },
        results
      })
    }

    return json(res, 405, { error: 'Method not allowed' })
  } catch (err) {
    const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 500
    return json(res, status, { error: err.message || 'Server error' })
  }
}
