'use strict'
// Standalone reproducer: on Windows, Chrome 153+ sometimes aborts the first navigation issued
// right after a session is created (Page.navigate -> net::ERR_ABORTED), and ChromeDriver reports
// the WebDriver Navigate command as successful anyway, leaving the page on its initial document.
//
// Talks raw HTTP to ChromeDriver; no Selenium, no npm dependencies.
//
//   node first-navigation-abort.js --chromedriver <path> --chrome <path> [--iterations 30] [--bidi] [--headless] [--chrome-logs] [--log chromedriver.log]
const { spawn } = require('node:child_process')
const http = require('node:http')
const net = require('node:net')
const fs = require('node:fs')

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name)
  if (i === -1) return fallback
  const v = process.argv[i + 1]
  return v === undefined || v.startsWith('--') ? true : v
}
const chromedriver = arg('chromedriver')
const chrome = arg('chrome')
const iterations = Number(arg('iterations', 30))
const bidi = arg('bidi', false) === true
const headless = arg('headless', false) === true
const logPath = arg('log', 'chromedriver.log')
const chromeLogs = arg('chrome-logs', false) === true
if (!chromedriver || !chrome) {
  console.error('usage: node first-navigation-abort.js --chromedriver <path> --chrome <path> [--iterations N] [--bidi] [--headless] [--log file]')
  process.exit(2)
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer()
    s.on('error', reject)
    s.listen(0, '127.0.0.1', () => {
      const port = s.address().port
      s.close(() => resolve(port))
    })
  })
}
function request(method, url, body) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body)
    const headers = { 'content-type': 'application/json; charset=utf-8' }
    if (data) headers['content-length'] = Buffer.byteLength(data)
    const req = http.request(url, { method, headers }, (res) => {
      let raw = ''
      res.setEncoding('utf8')
      res.on('data', (c) => (raw += c))
      res.on('end', () => {
        let json = null
        try {
          json = JSON.parse(raw)
        } catch {
          // non-JSON body
        }
        resolve({ status: res.statusCode, body: json, raw })
      })
    })
    req.on('error', reject)
    if (data) req.write(data)
    req.end()
  })
}

async function main() {
  const page = http.createServer((req, res) => {
    res.setHeader('content-type', 'text/html')
    res.end('<!DOCTYPE html><html><body><div id="box">box</div></body></html>')
  })
  await new Promise((r) => page.listen(0, '127.0.0.1', r))
  const pageUrl = `http://127.0.0.1:${page.address().port}/page.html`

  const port = await freePort()
  const driverArgs = [`--port=${port}`, '--verbose', `--log-path=${logPath}`]
  if (chromeLogs) driverArgs.push('--enable-chrome-logs')
  const driver = spawn(chromedriver, driverArgs, { stdio: 'ignore' })
  const base = `http://127.0.0.1:${port}`
  for (let i = 0; i < 100; i++) {
    try {
      const r = await request('GET', base + '/status')
      if (r.body && r.body.value && r.body.value.ready) break
    } catch {
      // not up yet
    }
    await sleep(100)
  }

  const alwaysMatch = {
    browserName: 'chrome',
    'goog:chromeOptions': { binary: chrome, args: headless ? ['--headless=new'] : [] },
  }
  if (bidi) {
    alwaysMatch.webSocketUrl = true
    alwaysMatch.unhandledPromptBehavior = 'ignore'
  }

  let lost = 0
  let version = ''
  for (let i = 1; i <= iterations; i++) {
    const s = await request('POST', base + '/session', { capabilities: { alwaysMatch } })
    const value = s.body && s.body.value
    if (!value || !value.sessionId) {
      console.error(`#${i} session not created: ${s.raw.slice(0, 300)}`)
      continue
    }
    version = version || (value.capabilities && value.capabilities.browserVersion) || ''
    const sbase = `${base}/session/${value.sessionId}`
    const t0 = Date.now()
    const nav = await request('POST', sbase + '/url', { url: pageUrl })
    const navMs = Date.now() - t0
    const find = await request('POST', sbase + '/element', { using: 'css selector', value: '#box' })
    const current = await request('GET', sbase + '/url')
    const ok = find.status === 200
    if (!ok) lost++
    const err = ok ? 'ok' : 'FAIL ' + ((find.body && find.body.value && find.body.value.error) || find.status)
    console.log(
      `#${String(i).padStart(3)}  navigate ${nav.status} in ${String(navMs).padStart(5)}ms  find ${err.padEnd(22)}  url=${current.body && current.body.value}`,
    )
    await request('DELETE', sbase)
  }

  driver.kill()
  page.close()
  const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : ''
  const aborted = (log.match(/net::ERR_ABORTED/g) || []).length
  console.log(`\nChrome ${version}  ${bidi ? 'BiDi' : 'classic'}  ${headless ? 'headless' : 'headed'}  ${process.platform}`)
  console.log(`${lost}/${iterations} sessions: Navigate returned 200 but the page was never loaded`)
  console.log(`${aborted} Page.navigate responses with net::ERR_ABORTED in ${logPath}`)
  if (chromeLogs) {
    const sandbox = (log.match(/Sandbox cannot access executable/g) || []).length
    const crashes = (log.match(/Network service crashed/g) || []).length
    console.log(`${sandbox} "Sandbox cannot access executable" and ${crashes} "Network service crashed" messages from Chrome`)
  }
}
main().catch((e) => {
  console.error(e)
  process.exit(1)
})
