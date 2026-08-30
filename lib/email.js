/**
 * Email provider abstraction (Resend).
 *
 * Set on Vercel (Project → Settings → Environment Variables), then redeploy:
 *   EMAIL_PROVIDER=resend          (also set in vercel.json; optional if omitted)
 *   RESEND_API_KEY=re_...
 *   EMAIL_FROM="Oracy <hello@yourdomain.com>"
 *   INVITE_CTA_URL=https://oracy.heyayush.in   (optional)
 *
 * Do not mark invites as sent unless sendEmail() returns successfully.
 */

const { env } = require('./adminAuth')

function present(name) {
  return Boolean(String(process.env[name] || '').trim())
}

function resolveProvider() {
  const raw = (process.env.EMAIL_PROVIDER || '').toLowerCase().trim()
  if (!raw) return 'resend'
  return raw
}

function missingResendVars() {
  const missing = []
  if (!present('RESEND_API_KEY')) missing.push('RESEND_API_KEY')
  if (!present('EMAIL_FROM')) missing.push('EMAIL_FROM')
  return missing
}

function isEmailConfigured() {
  const provider = resolveProvider()
  if (provider === 'none') return false
  if (provider === 'resend') return missingResendVars().length === 0
  return false
}

function emailStatus() {
  const provider = resolveProvider()
  const missing = []
  if (provider === 'none') {
    missing.push('EMAIL_PROVIDER')
  } else if (provider === 'resend') {
    missing.push(...missingResendVars())
  } else {
    missing.push('EMAIL_PROVIDER')
  }
  return {
    configured: isEmailConfigured(),
    provider,
    from: present('EMAIL_FROM') ? process.env.EMAIL_FROM.trim() : null,
    ctaUrl: process.env.INVITE_CTA_URL || 'https://oracy.heyayush.in',
    missing
  }
}

function defaultInviteTemplate() {
  const cta = process.env.INVITE_CTA_URL || 'https://oracy.heyayush.in'
  return {
    subject: 'Your invite to Oracy 🎙️',
    body:
      `Hey!\n\n` +
      `You signed up to try Oracy — a simple 1-minute-a-day speaking practice.\n\n` +
      `Your invite is ready. Speak for one minute, get AI feedback, and see how you improve over time.\n\n` +
      `Try Oracy → ${cta}\n`
  }
}

function resendErrorMessage(data, status) {
  if (!data || typeof data !== 'object') return `Resend failed (${status})`
  if (typeof data.message === 'string' && data.message) return data.message
  if (typeof data.error === 'string' && data.error) return data.error
  if (data.error && typeof data.error.message === 'string') return data.error.message
  return `Resend failed (${status})`
}

/**
 * @param {{ to: string, subject: string, body: string }} opts
 * @returns {Promise<{ id?: string, provider: string }>}
 */
async function sendEmail({ to, subject, body }) {
  const provider = resolveProvider()

  if (provider === 'none' || !isEmailConfigured()) {
    const status = emailStatus()
    const needed = status.missing.length
      ? status.missing.join(', ')
      : 'EMAIL_PROVIDER=resend, RESEND_API_KEY, EMAIL_FROM'
    const err = new Error(
      `Email is not configured. Set ${needed} on Vercel, then redeploy.`
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
      const err = new Error(resendErrorMessage(data, res.status))
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
