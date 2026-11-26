// The loader of a Cesia program compiled to WebAssembly by cesia build --target wasm: it runs the module beside it, in a
// page (<script type="module" src="NAME.js">, the output on the console) or in Node (node NAME.js, the output on stdout
// and stderr, the exit code 1 after an error). The module writes through its memory; an error gives its message and
// hint, then its site and depth: the loader writes it as Cesia does, from the sites of the custom section cesia.sites.
//
// Fibers. The main program and each fiber are calls of the module that JavaScript Promise Integration (JSPI) can
// suspend: a fiber that waits calls park, which gives a promise and suspends the fiber's stack, all of it, until the
// loader resolves it. One fiber runs at a time, in the order of the ready queue, as the interpreter's scheduler does;
// what wakes a fiber (a value sent, a timer, a message of a socket) puts it at the end of that queue. A long run gives
// the event loop back every SLICE milliseconds, at its fuel's checkpoints, so that a page stays fluid.
//
// JavaScript. js.Call(module, name, args) calls the function name of the JavaScript module module, a path beside the
// program or one of the loader's own (cesia:websocket); a text goes as a Uint8Array of its bytes, a number as a number,
// a boolean as a boolean, missing as null, a list as an array, a channel as a handle {send(value), close()} that puts
// values in it from JavaScript, the one way in. What the function gives comes back the same way, a string as its UTF-8.
const node = typeof process === 'object' && process.versions != null && process.versions.node != null
const url = new URL('@WASM@', import.meta.url)
const readFileSync = node ? (await import('node:fs')).readFileSync : null
// The module and the JavaScript modules that js.Call names, all asked for at once: a page compiles the module while its
// bytes arrive, when the server says application/wasm, and the browser loads those modules meanwhile.
const compiled = node ? WebAssembly.compile(readFileSync(url)) : fetch(url).then(r =>
  /^application\/wasm/.test(r.headers.get('content-type') || '') ? WebAssembly.compileStreaming(r) : r.arrayBuffer().then(b => WebAssembly.compile(b)))
const scripts = new Map(@SCRIPTS@.map(s => [s, import(new URL(s, import.meta.url).href)]))
for (const p of scripts.values()) p.catch(() => {})
const SCRATCH = 16384, CALLS = 20480, WINDOW = 65536, SLICE = 8
const KINDS = ['syntax', 'name', 'type', 'index', 'field', 'math', 'permission', 'user', 'io']
const jspi = typeof WebAssembly.Suspending === 'function'
let memory, module, x, table, msg = [], hint = [], lines = ['', '']
const decoder = new TextDecoder()
const encoder = new TextEncoder()
class Stop extends Error {}
class Cancel extends Error {}

// Bytes to an output: in Node as they are, in a page line by line to the console.
function out (fd, b) {
  if (node) { (fd === 1 ? process.stdout : process.stderr).write(b); return }
  const text = lines[fd - 1] + decoder.decode(b, { stream: true })
  const parts = text.split('\n')
  lines[fd - 1] = parts.pop()
  for (const p of parts) (fd === 1 ? console.log : console.error)(p)
}

// A float as Cesia writes it: the first of 15, 16 and 17 digits that reads back the same, then 1.0, 1e20, 1.5e-7.
function floatText (x) {
  if (Number.isNaN(x)) return 'nan'
  if (x === Infinity) return 'inf'
  if (x === -Infinity) return '-inf'
  if (x === 0) return Object.is(x, -0) ? '-0.0' : '0.0'
  const sign = x < 0 ? '-' : ''
  const a = Math.abs(x)
  let p = 15, s
  for (; p <= 17; p++) { s = a.toExponential(p - 1); if (p === 17 || Number(s) === a) break }
  const [m, e] = s.split('e')
  const digits = m.replace('.', '').replace(/0+$/, '') || '0'
  const n = digits.length, ex = Number(e)
  if (ex < -4 || ex >= p) return sign + digits[0] + (n > 1 ? '.' + digits.slice(1) : '') + 'e' + ex
  if (ex < 0) return sign + '0.' + '0'.repeat(-ex - 1) + digits
  if (n <= ex + 1) return sign + digits + '0'.repeat(ex + 1 - n) + '.0'
  return sign + digits.slice(0, ex + 1) + '.' + digits.slice(ex + 1)
}

// Site i of the table that the compiler wrote in NAME.sites, read at the first error: its header, its line of code and
// caret, the function it is in, whether in a library, its file and line. Node reads it at once, a page fetches it, and
// what needs it waits for it.
const sitesUrl = new URL(url.href.replace(/\.wasm$/, '.sites'))
let loading = null
function later_sites (f) {
  if (table) return f()
  if (node) { table = JSON.parse(readFileSync(sitesUrl, 'utf8')); return f() }
  if (!loading) loading = fetch(sitesUrl).then(r => r.json()).then(t => { table = t })
  loading.then(f)
}
function site (i) {
  if (i < 0) return ['', '', '', 0, '', 0]
  const t = table.t, s = table.s, k = 7 * i
  return [t[s[k]], t[s[k + 1]] + t[s[k + 2]], t[s[k + 3]], s[k + 4], t[s[k + 5]], s[k + 6]]
}

// An error: written as Cesia writes it, its trace from the call sites in the memory, the current fiber's own; a fiber's
// task then gets the Err of it, and the fiber stops.
function fail (here, depth, kind) {
  const calls = Array.from(new Int32Array(memory.buffer, CALLS, depth + 2)), m = new Uint8Array(msg.flat()), h = decoder.decode(new Uint8Array(hint.flat()))
  const fib = current, by = hint.length > 0
  msg = []; hint = []
  later_sites(() => report(here, depth, kind, calls, m, h, by, fib))
  throw new Stop()
}
function report (here, depth, kind, calls, m, h, by, fib) {
  const trace = []
  if (site(here)[2]) trace.push('in ' + site(here)[2])
  for (let d = depth; d >= 1; d--) if (site(calls[d])[2]) trace.push('called from ' + site(calls[d])[2])
  // In a library, the line shown is that of the program that called into it.
  let shown = here
  for (let d = depth; site(shown)[3] && d >= 1; d--) if (calls[d] >= 0 && !site(calls[d])[3]) shown = calls[d]
  const t = trace.length <= 20 ? trace : trace.slice(0, 10).concat(['... and ' + (trace.length - 10) + ' more'])
  const s = site(shown)
  out(2, encoder.encode(s[0] + decoder.decode(m) + '\n' + s[1] + (by ? '  ' + h + '\n' : '') + t.map(l => '  ' + l + '\n').join('')))
  if (main !== null && fib !== main) x.ended(fib, textOf(m), textOf(encoder.encode(KINDS[kind])), textOf(encoder.encode(site(here)[4])), site(here)[5])
}

// The scheduler: what runs next, in order; the fibers parked, each with what resumes it; one fiber runs at a time.
const ready = [], parked = new Map(), timers = new Map(), spawned = new WeakMap(), handles = new WeakMap()
let running = false, kicked = false, over = false, current = null, main = null, paused = false, handed = 0, nextTimer = 1
// A slice starts when the program runs again after it gave the event loop back: after a yield, or after it waited with
// nothing ready (idle), which a run from an event, a timer or a message ends.
let sliceStart = performance.now(), idle = false
// The event loop given back: a message, which costs microseconds; past a frame's time since the last time, through the
// browser's next frame first, since Firefox runs no frame between messages (measured: 12 frames a second without it).
const later = node ? f => setImmediate(f) : (() => {
  const c = new MessageChannel(), fs = []
  c.port1.onmessage = () => fs.shift()()
  const post = f => { fs.push(f); c.port2.postMessage(0) }
  let frame = 0
  return f => { const n = performance.now(); if (n - frame > 16) { frame = n; requestAnimationFrame(() => post(f)) } else post(f) }
})()
function kick () { if (!kicked) { kicked = true; queueMicrotask(step) } }
function step () {
  kicked = false
  if (running || over || paused) return
  if (ready.length) {
    if (idle) { idle = false; sliceStart = performance.now() }
    running = true; ready.shift()(); return
  }
  x.flush()
  // Nothing can wake the main program: no fiber ready, no timer, no channel that JavaScript holds.
  if (timers.size === 0 && handed === 0 && parked.has(main)) { running = true; resume(main, 1); return }
  idle = true
}
function resume (fib, code) { const r = parked.get(fib); parked.delete(fib); current = fib; r(code) }
function ran () { running = false; kick() }
function start (fib, fn) {
  current = fib
  fiber(fib, fn).then(ran, e => {
    if (e instanceof Cancel) {
      later_sites(() => { const s = site(spawned.get(fib)); x.ended(fib, null, textOf(encoder.encode('cancelled')), textOf(encoder.encode(s[4])), s[5]) })
    } else if (!(e instanceof Stop)) { over = true; throw e }
    ran()
  })
}
// Parks the current fiber: 0 until a wake, 1 at the end of the ready queue (it lets the others run), 2 until the event
// loop has turned (the page paints and takes its events), then first. Gives 0, or 1 to the main program in a deadlock.
function park (fib, mode) {
  return new Promise(res => {
    parked.set(fib, res)
    running = false
    if (mode === 1) ready.push(() => resume(fib, 0))
    if (mode === 2) {
      paused = true
      later(() => { paused = false; sliceStart = performance.now(); running = true; resume(fib, 0) })
      return
    }
    kick()
  })
}
const nojspi = () => { throw new Error('Fibers need JavaScript Promise Integration: Chrome 137, Firefox 153, Safari 27 or Node 26.') }

// Values to JavaScript and back, through the exports of the module and its second page of memory.
function bytesOf (v) {
  const n = x.size(v), b = new Uint8Array(n)
  for (let at = 0; at < n; at += 65536) { const k = Math.min(65536, n - at); x.bytes(v, at, k); b.set(new Uint8Array(memory.buffer, WINDOW, k), at) }
  return b
}
function textOf (b) {
  const t = x.text(b.length)
  for (let at = 0; at < b.length; at += 65536) { const k = Math.min(65536, b.length - at); new Uint8Array(memory.buffer, WINDOW, k).set(b.subarray(at, at + k)); x.fill(t, at, k) }
  return t
}
function handle (ch) {
  let h = handles.get(ch)
  if (!h) {
    let open = true
    handed++
    h = { send: v => x.post(ch, encode(v)) === 1, close () { if (open) { open = false; handed--; x.shut(ch) } } }
    handles.set(ch, h)
  }
  return h
}
function decode (v) {
  switch (x.kind(v)) {
    case 0: return null
    case 1: case 2: return x.num(v)
    case 3: return x.num(v) !== 0
    case 4: return bytesOf(v)
    case 5: { const n = x.count(v), a = new Array(n); for (let i = 0; i < n; i++) a[i] = decode(x.item(v, i)); return a }
    case 6: return handle(v)
    default: throw new TypeError('js.Call takes numbers, texts, booleans, missing, lists and channels.')
  }
}
function encode (j) {
  if (j === undefined || j === null) return null
  if (typeof j === 'boolean') return x.boolean(j ? 1 : 0)
  if (typeof j === 'number') return x.number(j)
  if (typeof j === 'string') return textOf(encoder.encode(j))
  if (j instanceof Uint8Array) return textOf(j)
  if (j instanceof ArrayBuffer) return textOf(new Uint8Array(j))
  if (Array.isArray(j)) { const l = x.list(j.length); j.forEach((e, i) => x.put(l, i, encode(e))); return x.listed(l) }
  throw new TypeError('A function called by js.Call gives a number, a string, bytes, a boolean, null or an array.')
}

// WebTransport (draft-ietf-webtrans-http3) beside WebSocket, where the browser has it, the page is https and the server
// offers it: a session on the WebSocket's own URL in https, one stream both ways, each message its length (QUIC's
// variable integer) then its UTF-8 bytes, and it acts as a WebSocket (send, close, readyState, onmessage, onclose). The
// two are raced, as Happy Eyeballs races IPv6 and IPv4 (RFC 8305): WebTransport is taken when it is ready first or
// within 300 ms of the WebSocket, the other is closed. A session that fails marks the origin for 10 minutes in
// sessionStorage, and only WebSocket goes there meanwhile, as where UDP doesn't pass: a page never waits on a blocked
// network.
const wtMark = 'cesia-webtransport-failed'
function wtFailed() { try { return Date.now() < +(sessionStorage.getItem(wtMark) || 0) } catch (e) { return false } }
function wtFail() { try { sessionStorage.setItem(wtMark, String(Date.now() + 600000)) } catch (e) {} }
// The server says that it takes sessions: <meta name=webtransport content=on> in the page (http.Serve's webtransport).
function offered() { return typeof document === 'object' && document.querySelector('meta[name=webtransport][content=on]') !== null }
function wtLength(n) {
  if (n < 64) return [n]
  if (n < 16384) return [64 | (n >> 8), n & 255]
  return [128 | (n >>> 24), (n >> 16) & 255, (n >> 8) & 255, n & 255]
}
function overTransport(url, opened, failed, hashes) {
  const s = { readyState: 0, onmessage: null, onclose: null }
  let t = null, writer = null, over = false
  const enc = new TextEncoder(), dec = new TextDecoder()
  const end = code => {
    if (over) return
    over = true
    const was = s.readyState
    s.readyState = 3
    try { if (t) t.close() } catch (e) {}
    if (was === 0) failed()
    else if (s.onclose) s.onclose({ code: code })
  }
  s.send = m => {
    const b = typeof m === 'string' ? enc.encode(m) : new Uint8Array(m), head = wtLength(b.length), all = new Uint8Array(head.length + b.length)
    all.set(head)
    all.set(b, head.length)
    writer.write(all).catch(() => end(1006))
  }
  s.close = code => end(code || 1000)
  // A certificate of 14 days at most that the page already knows by its hash, as a test's or a machine's own.
  const known = hashes && hashes.length ? { serverCertificateHashes: hashes.map(h => ({ algorithm: 'sha-256', value: Uint8Array.from(atob(h), c => c.charCodeAt(0)) })) } : undefined
  // A session carries no cookie: a ticket, asked with the page's cookies just before, says who it is for.
  const u = new URL(url), at = new URL(url)
  at.pathname = (u.pathname.endsWith('/') ? u.pathname.slice(0, -1) : u.pathname) + '/ticket'
  at.search = ''
  fetch(at, { credentials: 'same-origin', cache: 'no-store' }).then(r => r.ok ? r.json() : Promise.reject(r.status)).then(async j => {
    if (over) return
    u.searchParams.set('ticket', j.Ticket)
    t = new WebTransport(u.href, known)
    t.closed.then(() => end(1000), () => end(1006))
    await t.ready
    const stream = await t.createBidirectionalStream()
    writer = stream.writable.getWriter()
    if (over) return
    s.readyState = 1
    opened(s)
    const reader = stream.readable.getReader()
    let buf = new Uint8Array(0)
    for (;;) {
      const got = await reader.read()
      if (got.done) break
      const joined = new Uint8Array(buf.length + got.value.length)
      joined.set(buf)
      joined.set(got.value, buf.length)
      buf = joined
      for (;;) {
        if (buf.length < 1) break
        const w = 1 << (buf[0] >> 6)
        if (buf.length < w) break
        let n = buf[0] & 63
        for (let k = 1; k < w; k++) n = n * 256 + buf[k]
        if (buf.length < w + n) break
        const m = dec.decode(buf.subarray(w, w + n))
        buf = buf.slice(w + n)
        if (s.onmessage) s.onmessage({ data: m })
      }
    }
    end(1000)
  }).catch(() => end(1006))
  return s
}
// A connection to a ws: or wss: URL: ready(socket) once one is open, failed() if none could be. hashes: the
// CertificateHashes of the options, base64 SHA-256 of the server's certificate, for one no authority signed.
function dial(url, ready, failed, hashes) {
  const ws = new WebSocket(url)
  ws.binaryType = 'arraybuffer'
  const race = typeof WebTransport === 'function' && url.startsWith('wss:') && offered() && !wtFailed()
  let chosen = null, wsDead = false, wtDead = !race, grace = 0, wt = null
  const pick = s => {
    if (chosen) return
    chosen = s
    clearTimeout(grace)
    if (s !== ws) { ws.onopen = ws.onclose = null; ws.close(1000) }
    else if (wt) wt.close(1000)
    ready(s)
  }
  const dead = () => { if (!chosen && wsDead && wtDead) failed() }
  ws.onopen = () => { if (wtDead) pick(ws); else grace = setTimeout(() => pick(ws), 300) }
  ws.onclose = () => { wsDead = true; dead() }
  if (race) wt = overTransport('https:' + url.slice(4), s => pick(s), () => { wtDead = true; wtFail(); if (!chosen && ws.readyState === 1) pick(ws); dead() }, hashes)
}
// The loader's own module: the WebSocket of the page or of Node, for std/websocket, or WebTransport where it wins the
// race of dial. A socket opened with a last message sends it when the page goes away (pagehide), before the browser
// closes it.
const utf8 = new TextDecoder('utf-8', { fatal: true })
const sockets = new Map(), lasts = new Map(), dropped = new Set()
let nextSocket = 1, leaving = false
const own = {
  'cesia:websocket': {
    Open (address, messages, events, last) {
      const id = nextSocket++
      const closed = code => { sockets.delete(id); lasts.delete(id); dropped.delete(id); events.send('closed ' + code); messages.close(); events.close() }
      const ready = ws => {
        if (dropped.delete(id)) return ws.close(1000)
        ws.onmessage = e => messages.send(e.data)
        ws.onclose = e => closed(e.code)
        sockets.set(id, ws)
        events.send('open')
      }
      try { dial(decoder.decode(address), ready, () => closed(1006), (globalThis.cesia || {}).certificateHashes) } catch (e) { events.send('error'); return 0 }
      if (last != null) {
        lasts.set(id, decoder.decode(last))
        if (!leaving && !node) { leaving = true; addEventListener('pagehide', () => { for (const [k, t] of lasts) { const w = sockets.get(k); if (w && w.readyState === 1) w.send(t) } }) }
      }
      return id
    },
    Send (id, data) {
      const ws = sockets.get(id)
      if (!ws || ws.readyState !== 1) return false
      let s = null
      try { s = utf8.decode(data) } catch (e) {}
      ws.send(s === null ? data : s)
      return true
    },
    // A socket still dialing is closed as soon as it opens: Dial gave up on it.
    Close (id) { const ws = sockets.get(id); if (!ws) dropped.add(id); else if (ws.readyState < 2) ws.close(1000) },
  },
  'cesia:regex': { Test: (pattern, s) => new RegExp(decoder.decode(pattern), 'u').test(decoder.decode(s)) },
  // The clock of the page or of Node, in its time zone, for std/date's Local.
  'cesia:date': {
    Clock (s) { const d = new Date(s * 1000); return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds()] },
  },
  // The fetch of the page or of Node, for std/http's Fetch: the answer as [status, name, value, ..., body], or [0, why].
  'cesia:fetch': {
    Fetch (address, method, body, headers, reply) {
      const h = new Headers()
      for (let k = 0; k + 1 < headers.length; k += 2) h.append(decoder.decode(headers[k]), decoder.decode(headers[k + 1]))
      const m = decoder.decode(method)
      const ask = { method: m, headers: h, credentials: 'same-origin' }
      if (m !== 'GET' && m !== 'HEAD') ask.body = body
      fetch(node ? decoder.decode(address) : new URL(decoder.decode(address), location.href), ask).then(async r => {
        const out = [r.status]
        r.headers.forEach((v, k) => out.push(k, v))
        out.push(new Uint8Array(await r.arrayBuffer()))
        reply.send(out)
      }, e => reply.send([0, String(e && e.message || e)])).finally(() => reply.close())
    },
  },
}

const rt = {
  write (ptr, len, fd) {
    const b = new Uint8Array(memory.buffer, ptr, len).slice()
    if (fd === 3) msg.push(...b); else if (fd === 4) hint.push(...b); else out(fd, b)
  },
  ftoa (x) {
    const b = encoder.encode(floatText(x))
    new Uint8Array(memory.buffer, SCRATCH, b.length).set(b)
    return b.length
  },
  fail,
  rand32 () { return crypto.getRandomValues(new Int32Array(1))[0] },
  now () { return (performance.timeOrigin + performance.now()) / 1000 },
  // text.Number of the bytes in the window, as Native.number reads them, or NaN; text.Decimals in the scratch area, as
  // printf rounds the exact value, a true half away from zero, and what rounds to zero without its sign.
  number (len) {
    const t = decoder.decode(new Uint8Array(memory.buffer, WINDOW, len))
    return /^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(t) ? Number(t) : NaN
  },
  decimals (x, n) {
    let t = Math.abs(x) < 1e21 ? x.toFixed(n) : BigInt(Math.round(x)).toString() + (n > 0 ? '.' + '0'.repeat(n) : '')
    if (/^-[0.]*$/.test(t)) t = t.slice(1)
    const b = encoder.encode(t)
    new Uint8Array(memory.buffer, SCRATCH, b.length).set(b)
    return b.length
  },
  // At the fuel's checkpoints: 1 lets the fibers ready run (every million steps, as the interpreter), 2 gives the
  // event loop back, else 0.
  checkpoint (full) {
    if (!jspi) return 0
    if (full && ready.length) return 1
    return performance.now() - sliceStart > SLICE ? 2 : 0
  },
  park: jspi ? new WebAssembly.Suspending(park) : nojspi,
  wake (fib) { ready.push(() => resume(fib, 0)); kick() },
  spawn (fib, fn, site) { spawned.set(fib, site); ready.push(() => start(fib, fn)); kick() },
  timer (fib, seconds) {
    const id = nextTimer++
    timers.set(id, setTimeout(() => { timers.delete(id); x.timeout(fib) }, Math.min(seconds * 1000, 2147483647)))
    return id
  },
  untimer (id) { clearTimeout(timers.get(id)); timers.delete(id) },
  unwind () { throw new Cancel() },
  first (fib) { main = current = fib },
}

module = await compiled
const imports = { rt, Math }
for (const imp of WebAssembly.Module.imports(module)) {
  if (imp.module === 'rt' || imp.module === 'Math') continue
  if (!imports[imp.module]) imports[imp.module] = {}
  const m = own[imp.module] || await (scripts.get(imp.module) || import(new URL(imp.module, import.meta.url).href))
  const f = m[imp.name]
  if (typeof f !== 'function') throw new Error('js.Call: ' + imp.module + ' has no function ' + imp.name + '.')
  imports[imp.module][imp.name] = args => encode(f(...decode(args)))
}
const instance = await WebAssembly.instantiate(module, imports)
x = instance.exports
memory = x.memory
const fiber = jspi && x.fiber ? WebAssembly.promising(x.fiber) : nojspi
try {
  await (jspi ? WebAssembly.promising(x.main) : x.main)()
} catch (e) {
  if (!(e instanceof Stop)) throw e
  if (node) process.exitCode = 1
}
// The program ends with its main part: the other fibers stop, as with the interpreter.
over = true
if (node) { for (const t of timers.values()) clearTimeout(t); for (const ws of sockets.values()) ws.close() }
