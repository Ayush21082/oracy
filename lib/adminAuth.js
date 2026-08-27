const crypto = require('crypto')

function env(name, optional = false) {
  const v = process.env[name]
  if (!v && !optional) throw new Error(`Missing env ${name}`)
  return v || ''
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

function requireAdmin(req) {
  return verifyToken(getBearer(req))
}

module.exports = {
  env,
  issueToken,
  verifyToken,
  getBearer,
  requireAdmin,
  timingSafeEqualString
}
