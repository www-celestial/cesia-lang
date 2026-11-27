// glue.js: the module that page.ce calls. It imports shared.js at once and later.js when Later runs; the comment
// that names './unused.js' imports nothing, and the build leaves it.
import { Word } from './shared.js'

export function Later (got) {
  import('./later.js').then(m => { got.send(Word + ' ' + m.Word); got.close() })
}
