// The loader of a Cesia program compiled to WebAssembly by cesia build --target wasm: it runs the module beside it, in a
// page (<script type="module" src="NAME.js">, the output on the console) or in Node (node NAME.js, the output on stdout
// and stderr, the exit code 1 after an error). The module writes through its memory; an error gives its message and
// hint, then its site and depth: the loader writes it as Cesia does, from the sites of the custom section cesia.sites.
const node = typeof process === 'object' && process.versions != null && process.versions.node != null
const url = new URL('@WASM@', import.meta.url)
const bytes = node ? (await import('node:fs')).readFileSync(url) : await (await fetch(url)).arrayBuffer()
const SCRATCH = 16384, CALLS = 20480
let memory, module, msg = [], hint = [], lines = ['', '']
const decoder = new TextDecoder()
const encoder = new TextEncoder()
class Stop extends Error {}

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

function fail (site, depth) {
  const sites = JSON.parse(decoder.decode(WebAssembly.Module.customSections(module, 'cesia.sites')[0]))
  const calls = new Int32Array(memory.buffer, CALLS, depth + 2)
  const trace = []
  if (sites[site][2]) trace.push('in ' + sites[site][2])
  for (let d = depth; d >= 1; d--) if (sites[calls[d]][2]) trace.push('called from ' + sites[calls[d]][2])
  // In a library, the line shown is that of the program that called into it.
  let shown = site
  for (let d = depth; sites[shown][3] && d >= 1; d--) if (!sites[calls[d]][3]) shown = calls[d]
  const t = trace.length <= 20 ? trace : trace.slice(0, 10).concat(['... and ' + (trace.length - 10) + ' more'])
  const text = decoder.decode(new Uint8Array(msg.flat())), h = decoder.decode(new Uint8Array(hint.flat()))
  const s = sites[shown]
  out(2, encoder.encode(s[0] + text + '\n' + s[1] + (hint.length ? '  ' + h + '\n' : '') + t.map(l => '  ' + l + '\n').join('')))
  throw new Stop()
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
  checkpoint () {},
  rand32 () { return crypto.getRandomValues(new Int32Array(1))[0] }
}

module = await WebAssembly.compile(bytes)
const instance = await WebAssembly.instantiate(module, { rt, Math })
memory = instance.exports.memory
try {
  instance.exports.main()
} catch (e) {
  if (!(e instanceof Stop)) throw e
  if (node) process.exitCode = 1
}
