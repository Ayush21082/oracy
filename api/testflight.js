/**
 * Redirects to the Oracy TestFlight public invite.
 * Set TESTFLIGHT_URL on Vercel (e.g. https://testflight.apple.com/join/XXXXXXXX).
 * Falls back to TESTFLIGHT_URL / INVITE_CTA_URL only when it looks like a TestFlight link.
 */

function isTestFlightUrl(value) {
  if (!value || typeof value !== 'string') return false
  try {
    const u = new URL(value.trim())
    return u.protocol === 'https:' && u.hostname === 'testflight.apple.com'
  } catch {
    return false
  }
}

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.statusCode = 204
    return res.end()
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.statusCode = 405
    res.setHeader('Allow', 'GET, HEAD')
    res.setHeader('Content-Type', 'application/json; charset=utf-8')
    return res.end(JSON.stringify({ error: 'Method not allowed' }))
  }

  const candidates = [process.env.TESTFLIGHT_URL, process.env.INVITE_CTA_URL]
  const target = candidates.find(isTestFlightUrl)

  if (!target) {
    res.statusCode = 503
    res.setHeader('Content-Type', 'text/html; charset=utf-8')
    res.setHeader('Cache-Control', 'no-store')
    return res.end(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Beta link not ready — Oracy</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 28rem; margin: 4rem auto; padding: 0 1.25rem; color: #111; line-height: 1.5; }
    a { color: #9a4a2e; }
  </style>
</head>
<body>
  <h1>Beta link not ready yet</h1>
  <p>The Oracy TestFlight invite isn’t configured on this server. Set <code>TESTFLIGHT_URL</code> to your public TestFlight link (https://testflight.apple.com/join/…).</p>
  <p><a href="/signal">Back to install guide</a></p>
</body>
</html>`)
  }

  res.statusCode = 302
  res.setHeader('Location', target.trim())
  res.setHeader('Cache-Control', 'no-store')
  res.end()
}
