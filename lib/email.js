/**
 * Email provider abstraction.
 * Configure with:
 *   EMAIL_PROVIDER=resend
 *   RESEND_API_KEY=re_...
 *   EMAIL_FROM="Oracy <hello@yourdomain.com>"
 *   INVITE_CTA_URL=https://oracy.heyayush.in/signal   (optional)
 *   TESTFLIGHT_URL=https://testflight.apple.com/join/XXXXXXXX  (used by /api/testflight)
 *
 * Do not mark invites as sent unless this returns successfully.
 */

const { env } = require('./adminAuth')

function isEmailConfigured() {
  const provider = (process.env.EMAIL_PROVIDER || '').toLowerCase().trim()
  if (!provider || provider === 'none') return false
  if (provider === 'resend') return Boolean(process.env.RESEND_API_KEY && process.env.EMAIL_FROM)
  return false
}

function emailStatus() {
  const provider = (process.env.EMAIL_PROVIDER || 'none').toLowerCase().trim() || 'none'
  return {
    configured: isEmailConfigured(),
    provider,
    from: process.env.EMAIL_FROM || null,
    ctaUrl: process.env.INVITE_CTA_URL || 'https://oracy.heyayush.in/signal'
  }
}

function defaultInviteTemplate() {
  const cta = process.env.INVITE_CTA_URL || 'https://oracy.heyayush.in/signal'
  return {
    subject: 'Your invite to Oracy 🎙️',
    body:
      `Hey!\n\n` +
      `You signed up to try Oracy — a simple 1-minute-a-day speaking practice.\n\n` +
      `Your invite is ready. Open the link below on your iPhone to install the beta via TestFlight.\n\n` +
      `Get Oracy → ${cta}\n`
  }
}

/**
 * @param {{ to: string, subject: string, body: string }} opts
 * @returns {Promise<{ id?: string, provider: string }>}
 */
async function sendEmail({ to, subject, body }) {
  const provider = (process.env.EMAIL_PROVIDER || '').toLowerCase().trim()

  if (!provider || provider === 'none') {
    const err = new Error(
      'Email is not configured. Set EMAIL_PROVIDER (e.g. resend), RESEND_API_KEY, and EMAIL_FROM.'
    )
    err.code = 'EMAIL_NOT_CONFIGURED'
    throw err
  }

  if (provider === 'resend') {
    const apiKey = env('RESEND_API_KEY')
    const from = env('EMAIL_FROM')
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject,
        text: body
      })
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error(data.message || data.error || `Resend failed (${res.status})`)
      err.code = 'EMAIL_PROVIDER_ERROR'
      err.status = res.status
      throw err
    }
    return { id: data.id, provider: 'resend' }
  }

  const err = new Error(`Unknown EMAIL_PROVIDER "${provider}". Supported: resend`)
  err.code = 'EMAIL_NOT_CONFIGURED'
  throw err
}

module.exports = {
  isEmailConfigured,
  emailStatus,
  defaultInviteTemplate,
  sendEmail
}
