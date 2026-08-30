/**
 * Admin backend health probes.
 * Returns tick/cross style checks for services the Oracy app depends on.
 */

const { issueToken, requireAdmin, env } = require('../lib/adminAuth')
const { emailStatus, isEmailConfigured } = require('../lib/email')

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
      if (size > 50_000) {
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

function truncate(text, max = 160) {
  const t = String(text || '')
    .replace(/\s+/g, ' ')
    .trim()
  return t.length <= max ? t : `${t.slice(0, max - 1)}…`
}

function ok(id, category, name, detail, extra = {}) {
  return { id, category, name, status: 'ok', detail, ...extra }
}
function fail(id, category, name, detail, extra = {}) {
  return { id, category, name, status: 'fail', detail, ...extra }
}
function skip(id, category, name, detail, extra = {}) {
  return { id, category, name, status: 'skip', detail, ...extra }
}

function supabaseBase() {
  return env('SUPABASE_URL').replace(/\/$/, '')
}

function serviceHeaders(extra = {}) {
  const key = env('SUPABASE_SERVICE_ROLE_KEY')
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    ...extra
  }
}

async function timedFetch(url, options = {}, timeoutMs = 12000) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetch(url, { ...options, signal: controller.signal })
    const text = await res.text()
    let data = null
    try {
      data = text ? JSON.parse(text) : null
    } catch {
      data = text
    }
    return { res, text, data }
  } finally {
    clearTimeout(timer)
  }
}

async function checkSupabaseEnv() {
  try {
    const url = process.env.SUPABASE_URL || ''
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY || ''
    if (!url || !key) {
      return fail('sb_env', 'Supabase', 'Admin credentials', 'SUPABASE_URL or SERVICE_ROLE_KEY missing on Vercel')
    }
    if (url.includes('your-project')) {
      return fail('sb_env', 'Supabase', 'Admin credentials', 'Placeholder URL')
    }
    return ok('sb_env', 'Supabase', 'Admin credentials', 'URL + service role present')
  } catch (e) {
    return fail('sb_env', 'Supabase', 'Admin credentials', e.message)
  }
}

async function checkAuthHealth() {
  try {
    const { res } = await timedFetch(`${supabaseBase()}/auth/v1/health`, {
      headers: serviceHeaders()
    })
    if ((res.status >= 200 && res.status < 500) || res.status === 401) {
      return ok('sb_auth_health', 'Supabase', 'Auth health', `HTTP ${res.status}`)
    }
    return fail('sb_auth_health', 'Supabase', 'Auth health', `HTTP ${res.status}`)
  } catch (e) {
    return fail('sb_auth_health', 'Supabase', 'Auth health', truncate(e.message))
  }
}

async function checkAuthSettings() {
  try {
    const { res, data } = await timedFetch(`${supabaseBase()}/auth/v1/settings`, {
      headers: serviceHeaders()
    })
    if (!res.ok) {
      return fail('sb_auth_settings', 'Supabase', 'Auth providers', `HTTP ${res.status}`)
    }
    const external = data?.external || {}
    const enabled = Object.entries(external)
      .filter(([, v]) => v === true || v?.enabled === true)
      .map(([k]) => k)
    const phone = data?.phone || data?.sms
    const bits = []
    if (enabled.length) bits.push(enabled.join(', '))
    if (phone) bits.push('phone')
    return ok(
      'sb_auth_settings',
      'Supabase',
      'Auth providers',
      bits.length ? `Enabled: ${bits.join(' · ')}` : 'Settings reachable'
    )
  } catch (e) {
    return fail('sb_auth_settings', 'Supabase', 'Auth providers', truncate(e.message))
  }
}

async function checkTable(id, name, path, emptyFailDetail) {
  try {
    const { res, data, text } = await timedFetch(`${supabaseBase()}/rest/v1/${path}`, {
      headers: serviceHeaders({ Prefer: 'count=exact' })
    })
    if (!res.ok) {
      return fail(id, 'Database', name, truncate(typeof data === 'object' ? JSON.stringify(data) : text))
    }
    const countHeader = res.headers.get('content-range')
    const countMatch = countHeader && /\/(\d+|\*)/.exec(countHeader)
    const rows = Array.isArray(data) ? data : []
    if (emptyFailDetail && rows.length === 0 && (countMatch?.[1] === '0' || countMatch?.[1] === '*')) {
      // Prefer content-range when present
    }
    if (emptyFailDetail) {
      const total =
        countMatch && countMatch[1] !== '*'
          ? Number(countMatch[1])
          : rows.length
      if (total === 0) {
        return fail(id, 'Database', name, emptyFailDetail)
      }
      return ok(id, 'Database', name, `${total} active`)
    }
    return ok(id, 'Database', name, rows.length ? 'Reachable' : 'Reachable (empty)')
  } catch (e) {
    return fail(id, 'Database', name, truncate(e.message))
  }
}

async function checkStorage() {
  try {
    const { res, text, data } = await timedFetch(
      `${supabaseBase()}/storage/v1/bucket/session-audio`,
      { headers: serviceHeaders() }
    )
    if (res.status === 404) {
      return fail('sb_storage', 'Storage', 'session-audio bucket', 'Bucket missing')
    }
    if (!res.ok) {
      return fail(
        'sb_storage',
        'Storage',
        'session-audio bucket',
        truncate(typeof data === 'object' ? JSON.stringify(data) : text)
      )
    }
    return ok('sb_storage', 'Storage', 'session-audio bucket', 'Bucket exists')
  } catch (e) {
    return fail('sb_storage', 'Storage', 'session-audio bucket', truncate(e.message))
  }
}

async function checkEdgeFunction(id, name, slug) {
  try {
    const url = `${supabaseBase()}/functions/v1/${slug}`
    const { res } = await timedFetch(url, {
      method: 'OPTIONS',
      headers: {
        ...serviceHeaders(),
        'Access-Control-Request-Headers': 'authorization, x-client-info, apikey, content-type'
      }
    })
    if (res.status === 404) {
      return fail(id, 'Edge', name, 'Not deployed')
    }
    if (res.status >= 200 && res.status < 500) {
      return ok(id, 'Edge', name, `Deployed · HTTP ${res.status}`)
    }
    return fail(id, 'Edge', name, `HTTP ${res.status}`)
  } catch (e) {
    return fail(id, 'Edge', name, truncate(e.message))
  }
}

async function probeOpenAIDirect(apiKey) {
  const checks = []
  checks.push(ok('openai_key', 'OpenAI', 'API key', 'Configured on Vercel'))

  const models = await timedFetch('https://api.openai.com/v1/models', {
    headers: { Authorization: `Bearer ${apiKey}` }
  })
  if (!models.res.ok) {
    const errText = models.text || ''
    const quota = /insufficient_quota|exceeded your current quota/i.test(errText)
    checks.push(
      fail(
        'openai_models',
        'OpenAI',
        'API reachability',
        quota ? 'Quota / billing issue' : truncate(errText),
        { costUsd: 0 }
      )
    )
    checks.push(skip('openai_quota', 'OpenAI', 'Token / quota (1-token)', 'Skipped — models list failed'))
    return checks
  }

  checks.push(
    ok('openai_models', 'OpenAI', 'API reachability', 'Models endpoint OK (free)', { costUsd: 0 })
  )

  const chat = await timedFetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      max_tokens: 1,
      messages: [{ role: 'user', content: 'ok' }]
    })
  })

  const chatCost = 0.00001
  if (!chat.res.ok) {
    const errText = chat.text || ''
    const quota = /insufficient_quota|exceeded your current quota/i.test(errText)
    checks.push(
      fail(
        'openai_quota',
        'OpenAI',
        'Token / quota (1-token)',
        quota ? 'Quota exceeded — add billing credits' : truncate(errText),
        { costUsd: 0 }
      )
    )
  } else {
    checks.push(
      ok('openai_quota', 'OpenAI', 'Token / quota (1-token)', 'Completion succeeded · token path OK', {
        costUsd: chatCost
      })
    )
  }
  return checks
}

async function probeOpenAIViaEdge() {
  const url = `${supabaseBase()}/functions/v1/system-status`
  const { res, data, text } = await timedFetch(
    url,
    {
      method: 'POST',
      headers: serviceHeaders(),
      body: JSON.stringify({ ping: true, source: 'admin' })
    },
    25000
  )

  if (res.status === 404) {
    return [
      fail('openai_key', 'OpenAI', 'API key', 'system-status edge not deployed'),
      skip('openai_models', 'OpenAI', 'API reachability', 'Skipped'),
      skip('openai_quota', 'OpenAI', 'Token / quota (1-token)', 'Skipped')
    ]
  }

  if (!res.ok) {
    return [
      fail(
        'openai_key',
        'OpenAI',
        'API key',
        truncate((data && data.error) || text || `HTTP ${res.status}`)
      ),
      skip('openai_models', 'OpenAI', 'API reachability', 'Skipped'),
      skip('openai_quota', 'OpenAI', 'Token / quota (1-token)', 'Skipped')
    ]
  }

  const edgeChecks = Array.isArray(data?.checks) ? data.checks : []
  const mapped = []
  const wanted = [
    ['openai_key', 'API key'],
    ['openai_models', 'API reachability'],
    ['openai_quota', 'Token / quota (1-token)']
  ]
  for (const [id, name] of wanted) {
    const c = edgeChecks.find((x) => x.id === id)
    if (!c) {
      mapped.push(skip(id, 'OpenAI', name, 'Not returned by edge'))
      continue
    }
    const fn = c.status === 'ok' ? ok : c.status === 'fail' ? fail : skip
    mapped.push(
      fn(id, 'OpenAI', name, c.detail || c.status, {
        costUsd: c.costUsd,
        via: 'edge'
      })
    )
  }
  return mapped
}

async function checkOpenAI() {
  const vercelKey = process.env.OPENAI_API_KEY || ''
  if (vercelKey) {
    return probeOpenAIDirect(vercelKey)
  }
  // Fall back to Supabase edge secrets via system-status
  try {
    return await probeOpenAIViaEdge()
  } catch (e) {
    return [
      fail('openai_key', 'OpenAI', 'API key', truncate(e.message)),
      skip('openai_models', 'OpenAI', 'API reachability', 'Skipped'),
      skip('openai_quota', 'OpenAI', 'Token / quota (1-token)', 'Skipped')
    ]
  }
}

async function checkFirebase() {
  const apiKey = process.env.FIREBASE_WEB_API_KEY || process.env.FIREBASE_API_KEY || ''
  const projectId = process.env.FIREBASE_PROJECT_ID || ''

  if (!apiKey) {
    return [
      fail(
        'firebase_key',
        'Firebase',
        'Web API key',
        'Set FIREBASE_WEB_API_KEY on Vercel to probe phone auth backend'
      ),
      skip('firebase_project', 'Firebase', 'Project config', 'Skipped — no API key')
    ]
  }

  const checks = [ok('firebase_key', 'Firebase', 'Web API key', 'Configured on Vercel')]

  try {
    const url = `https://www.googleapis.com/identitytoolkit/v3/relyingparty/getProjectConfig?key=${encodeURIComponent(apiKey)}`
    const { res, data, text } = await timedFetch(url, { method: 'POST', body: '{}' })
    if (!res.ok) {
      checks.push(
        fail(
          'firebase_project',
          'Firebase',
          'Project config',
          truncate((data && (data.error?.message || data.error)) || text || `HTTP ${res.status}`)
        )
      )
      return checks
    }
    const pid = data?.projectId || projectId || 'ok'
    const providers = Array.isArray(data?.idpConfig)
      ? data.idpConfig.map((p) => p.provider).filter(Boolean)
      : []
    const detail = providers.length
      ? `Project ${pid} · providers: ${providers.join(', ')}`
      : `Project ${pid} reachable`
    checks.push(ok('firebase_project', 'Firebase', 'Project config', detail))
  } catch (e) {
    checks.push(fail('firebase_project', 'Firebase', 'Project config', truncate(e.message)))
  }
  return checks
}

async function checkEmail() {
  const status = emailStatus()
  if (!isEmailConfigured()) {
    const missing = (status.missing || []).join(', ') || 'RESEND_API_KEY, EMAIL_FROM'
    return fail(
      'email_provider',
      'Email',
      'Invite email',
      `Not configured — set ${missing} on Vercel, then redeploy`
    )
  }
  return ok(
    'email_provider',
    'Email',
    'Invite email',
    `Ready via ${status.provider} · ${status.from || '—'}`
  )
}

async function runAllChecks() {
  const checks = []
  let estimatedCostUsd = 0

  checks.push(await checkSupabaseEnv())
  checks.push(await checkAuthHealth())
  checks.push(await checkAuthSettings())
  checks.push(
    await checkTable(
      'db_challenges',
      'challenges',
      'challenges?select=id&active=eq.true&limit=1',
      'No active challenges — seed the DB'
    )
  )
  checks.push(await checkTable('db_profiles', 'profiles', 'profiles?select=id&limit=1'))
  checks.push(await checkTable('db_sessions', 'sessions', 'sessions?select=id&limit=1'))
  checks.push(
    await checkTable('db_interested', 'interested (RSVP)', 'interested?select=id&limit=1')
  )
  checks.push(
    await checkTable('db_remote_config', 'remote_config', 'remote_config?select=key&limit=1')
  )
  checks.push(await checkStorage())
  checks.push(await checkEdgeFunction('edge_analyze', 'analyze-session', 'analyze-session'))
  checks.push(await checkEdgeFunction('edge_status', 'system-status', 'system-status'))

  const openai = await checkOpenAI()
  for (const c of openai) {
    checks.push(c)
    if (typeof c.costUsd === 'number') estimatedCostUsd += c.costUsd
  }

  for (const c of await checkFirebase()) checks.push(c)
  checks.push(await checkEmail())

  const summary = {
    ok: checks.filter((c) => c.status === 'ok').length,
    fail: checks.filter((c) => c.status === 'fail').length,
    skip: checks.filter((c) => c.status === 'skip').length
  }

  return {
    ok: summary.fail === 0,
    summary,
    estimatedCostUsd,
    checkedAt: new Date().toISOString(),
    checks
  }
}

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.statusCode = 204
    return res.end()
  }

  try {
    const url = new URL(req.url, 'http://localhost')
    const action = url.searchParams.get('action') || 'run'

    if (req.method === 'POST' && action === 'login') {
      const body = await readBody(req)
      const token = issueToken(body.password || '')
      if (!token) return json(res, 401, { error: 'Invalid password' })
      return json(res, 200, { token, expiresInHours: 12 })
    }

    if (!requireAdmin(req)) return json(res, 401, { error: 'Unauthorized' })

    if ((req.method === 'GET' || req.method === 'POST') && (action === 'run' || action === 'list')) {
      const report = await runAllChecks()
      return json(res, 200, report)
    }

    return json(res, 405, { error: 'Method not allowed' })
  } catch (err) {
    const status = err.status && err.status >= 400 && err.status < 600 ? err.status : 500
    return json(res, status, { error: err.message || 'Server error' })
  }
}
