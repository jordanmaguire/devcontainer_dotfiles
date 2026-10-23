// Serves one review as a web page on 127.0.0.1 and reports the user's choice on stdout.
//
// Reads `{ title, changes }` (the mod's parsed Proposal) as JSON on stdin, then writes one JSON line per event:
//   { "url": "http://127.0.0.1:<port>/<token>/" }   once listening
//   { "selected": [1, 3] }                          when the user presses Apply, then exits
//
// The token is random per run, so only the page the mod hands out can post a choice. The review is never written to
// stdout, stderr or a URL.
import { randomBytes } from 'node:crypto'
import { createServer } from 'node:http'
import { readFileSync } from 'node:fs'

const IDLE_MS = 4 * 60 * 60 * 1000
const MAX_BODY = 64 * 1024
const LOCAL_HOSTS = new Set(['127.0.0.1', 'localhost'])

const review = JSON.parse(readFileSync(0, 'utf8'))
const ids = new Set(review.changes.map(change => change.id))
const token = randomBytes(16).toString('hex')
const page = readFileSync(new URL('./page.html', import.meta.url), 'utf8')
const nonce = randomBytes(16).toString('base64')
const html = page
  .replaceAll('{{nonce}}', nonce)
  .replace('{{title}}', review.title.replace(/[&<>"]/g, char => `&#${char.charCodeAt(0)};`))
  .replace('{{data}}', () => JSON.stringify(review).replace(/</g, '\\u003c'))

const emit = event => process.stdout.write(`${JSON.stringify(event)}\n`)

const hostname = url => {
  try {
    return new URL(url).hostname
  } catch {
    return ''
  }
}

const send = (res, status, type, body, extra = {}) => {
  res.writeHead(status, {
    'Content-Type': type,
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    ...extra,
  })
  res.end(body)
}

const readBody = req =>
  new Promise((resolve, reject) => {
    let body = ''
    req.setEncoding('utf8')
    req.on('data', chunk => {
      body += chunk
      if (body.length > MAX_BODY) reject(new Error('too large'))
    })
    req.on('end', () => resolve(body))
    req.on('error', reject)
  })

const parseSelected = body => {
  const { selected } = JSON.parse(body)
  if (!Array.isArray(selected) || !selected.every(id => ids.has(id))) throw new Error('bad selection')

  return [...new Set(selected)].sort((a, b) => a - b)
}

let idle = setTimeout(() => process.exit(0), IDLE_MS)

const server = createServer(async (req, res) => {
  clearTimeout(idle)
  idle = setTimeout(() => process.exit(0), IDLE_MS)

  // A page on another site cannot reach this server by a name it controls (DNS rebinding) or post to it.
  const origin = req.headers.origin
  if (!LOCAL_HOSTS.has(hostname(`http://${req.headers.host}`)) || (origin && !LOCAL_HOSTS.has(hostname(origin))))
    return send(res, 403, 'text/plain', 'Forbidden')

  const path = new URL(req.url ?? '/', 'http://127.0.0.1').pathname
  if (req.method === 'GET' && path === `/${token}/`)
    return send(res, 200, 'text/html; charset=utf-8', html, {
      'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; form-action 'none'`,
    })

  if (req.method === 'POST' && path === `/${token}/submit`) {
    let selected
    try {
      selected = parseSelected(await readBody(req))
    } catch {
      return send(res, 400, 'application/json', '{"ok":false}')
    }
    emit({ selected })
    res.on('finish', () => server.close(() => process.exit(0)))

    return send(res, 200, 'application/json', '{"ok":true}', { Connection: 'close' })
  }

  return send(res, 404, 'text/plain', 'Not found')
})

server.listen(0, '127.0.0.1', () => emit({ url: `http://127.0.0.1:${server.address().port}/${token}/` }))
