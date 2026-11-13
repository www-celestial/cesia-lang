# Tests

In this chapter you check that your code does what it should, and keeps doing it as you change it. Cesia has two kinds of
tests: examples written in the documentation of a function, and test functions in `.test.ce` files, which can try a rule on
many generated cases and compare a value with a kept snapshot. `cesia test` runs them all.
Then you document your code, and build a site of it like this one.

## Examples in the documentation

A comment that starts with `(**` documents what it belongs to. Inside a `defn`, it comes first. An example in it, indented,
with `-->` and the value it should give, is a test, a [doctest](glossary.md#doctest):

```cesia
use std/math
defn WithTax(price Number) Number
  (** The price with 20% of tax, to the cent.

        WithTax(10.0) --> 12.0
        WithTax(0.99) --> 1.19 *)
  cents(price * 1.2)
end

cents(x) = math.Round(x * 100) / 100
WithTax(0.99) -->
```

### When an example fails

The example says to the reader what the function does, and `cesia test` checks that it still does. When the value is not the
one written, `cesia test` names the file, the line, and what it got:

```text
src/prices/tax.ce:7: WithTax(0.99) --> 1.2, got 1.19
3 passed, 1 failed
```

`--> error` says that the call must stop with an error.

## Test functions

A test function has a name that starts with `is` and a capital, no parameter, and gives `true` when all is well. It is private,
so it stays in its package. Test functions sit in a file whose name ends with `.test.ce`, beside the code they test: `tax.ce`
and `tax.test.ce`. Such a file sees the private names of its package, and is not part of the program.

```cesia
use std/bug
isZeroStaysZero() = WithTax(0) == 0
defn isRoundsToCents()
  bug.Assert(WithTax(1.234) == 1.48, "1.234 rounds down")
  WithTax(1.235) == 1.48
end
isZeroStaysZero() -->
isRoundsToCents() -->
```

A test that gives `false` fails, and so does one that stops: a [bug.Assert] that is false, a bug. [bug.Assert] with a message says
which part of a long test went wrong.

### When a test fails

A failed test shows what it compared, and the value of each call, field and variable in it, as they were in that run. A test
whose parts are joined by `and`, `or`, `not` or [list.All] names the part that failed:

```text
src/shop/cart.test.ce:4: isTotal failed
  shop.Total(cart) == 30
  | shop.Total(cart) = 27.0
  | cart = Cart(Items = [{Price: 10, Qty: 3}], Discount = 0.1)
src/shop/cart.test.ce:6: isReceipt failed, part 2 of 3
  r.Tax == 2.7
  | r.Tax = 2.6999999999999997
  | the same float but for its last bits: math.Near(r.Tax, 2.7)?
```

Two lists, maps or structs that differ show where they first differ, as `first difference: [3]: 6 vs 7` or
`first difference: .B.C: 2 vs 3`, and two texts the character where they part. A test that stops says where, with the calls
that led there. A test may use `?`: the Err of a `?` fails it, and the line of that `?` is named.

### Near

Floats rarely come out exactly as written: `0.1 + 0.2` is not `0.3`. [math.Near] compares within a tolerance, `rel` of the
larger number or `abs`, whichever is larger, element by element for arrays, maps and structs. Against 0, only `abs` helps:

```cesia
use std/math
math.Near(0.1 + 0.2, 0.3) -->
math.Near([1.0, 2.0], [1.0, 2.0 + 1e-12]) -->
math.Near(1e-12, 0) -->
math.Near(1e-12, 0, abs = 1e-9) -->
```

It belongs to std/math, so a program can use it too, as a loop that stops when a value settles.

## Properties

A test function checks the cases you thought of. A property checks a rule on many cases that Cesia makes, which is called
*property-based testing*: QuickCheck began it in Haskell in 2000, and Hypothesis brought it to Python. [test.ForAll]
takes the rule, a function that gives `true`, and a generator of std/gen, which makes the cases. A fast solution against a
slow sure one is the most useful rule of all:

```cesia norun
use std/test
use std/gen
use std/list
use std/value
radixSort(xs) = list.Sort(xs)   (* stands for your fast solution *)
isSortAgrees() = test.ForAll(xs -> value.Equal(radixSort(xs), list.Sort(xs)), gen.List(gen.Int()))
```

It tries 100 cases, small ones first. When one fails, Cesia makes it smaller as long as it still fails, and shows the
smallest: this is *shrinking*. A case is made from the numbers its generator drew, its *tape*, and Cesia shrinks the tape,
fewer draws and smaller ones, then makes the case again from it, as Hypothesis does: the smaller case always comes from
the same generator, so it is always a case the generator could have made, and a struct whose fields have rules stays
valid as it shrinks.

```text
src/shop/sort.test.ce:6: isSortAgrees failed at case 41 of 100, shrunk from 33 draws to 9:
  xs = [-1, -2]
  value.Equal(radixSort(xs), list.Sort(xs))
  | radixSort(xs) = [-1, -2]
  | list.Sort(xs) = [-2, -1]
  | first difference: [1]: -1 vs -2
  saved, tried first next time; these cases again: cesia test src/shop/sort.test.ce --seed 4127
```

The failure is saved in `.cesia/failures/`, which `cesia new` keeps out of git, and tried first at the next run, until it
passes. Each run tries new cases from a new [seed](glossary.md#seed); `--seed` gives the cases of a run again, and the
numbers of [std/random](data.md#the-same-numbers-again) too, since they come from the same seed.

The generators of std/gen are [gen.Int] and [gen.Float] with their bounds, [gen.Bool], [gen.Text], [gen.List],
[gen.Dict], [gen.Pick] of a list, [gen.Map] of a function, [gen.Then], and [gen.Of], which makes a struct from the types of
its fields, or a map or a list from generators:

```cesia norun
use std/test
use std/gen
use std/list
total(lines) = list.Sum([l.Qty * l.Price for l in lines])
orders = gen.List(gen.Of({Item: gen.Text(), Qty: gen.Int(1, 99), Price: gen.Float(0, 100)}))
isNeverNegative() = test.ForAll(os -> total(os) >= 0, orders)
```

For a struct whose fields have types, as `Item Text`, `Qty Int` and `Price Float`, `gen.Of(Order)` is enough, and
`gen.Of(Order, with = {Qty: gen.Int(1, 99)})` gives the generator of a field by its name.

## Snapshots

Some results are long to write by hand: a page, a report. [test.Snapshot] keeps the text of a value beside the test, in
`page.test.snap` for `page.test.ce`, and compares the value with it at each run:

```cesia norun
use std/test
page(name) = "<h1>$name</h1>\n<p>Total: 3</p>\n"
isPage() = test.Snapshot(page("Ana"))
```

This is *snapshot testing*, as Jest does it for JavaScript, or a *golden test* when the text is a whole output. A new
snapshot fails and shows its text: read it, then `cesia test --update` accepts it. A changed one shows the lines that
changed. The `.snap` file goes into git, where a review sees each change.

## What a test may do

A test reads the files of its project, and writes only in the folder that [test.Temp] gives it: removed when the test
passes, kept and named when it fails. It may listen on this machine, and connect only to its own listeners, so the test of a
server starts the server itself, on a free port:

```cesia norun
use std/net
use std/http
use std/fiber
defn isHello()
  l = net.Listen(0)?
  fiber.Spawn(() -> http.Serve(http.App() then http.AnyMethod("*", r -> {Status: 200, Body: "hi"}), listener = l))
  reply = http.Fetch("http://localhost:$(net.Port(l))/")?
  reply.Status == 200 and reply.Body == "hi"
end
```

That is the permission `net=own`. A test reaches only the listeners it has open, and only while they are open: once it
closes one, its port is out of reach, as another program may take it. It names them by an address of this machine written
out, as `127.0.0.1` or `::1`, or by `localhost`, and it looks up no other name, since a lookup already sends the name out of
the machine. A test that needs a server of the network gets it by name in `allow` of `[test]`, as `net=example.com:443`.

A test has 10 seconds, and its fibers, sockets and servers end with it, as do the programs it started with [sys.Start] or
[sys.Run]: at its end, whether it passed, failed or ran past its time, each one still running gets the TERM signal, and
KILL a second later. `[test]` in `cesia.toml` changes the 10 seconds for the whole project:

```toml
[test]
allow = ["exec=git"]
timeout = "30"
serial = ["tests/db"]
skip = ["tests/e2e"]
```

`allow` adds permissions, as `--allow` does; `timeout` is in seconds, written as a text; `serial` names the files and folders
that share something, as a database, and run alone, after the others; `skip` names those that `cesia test` leaves out
unless its path is in one of them, as end-to-end tests that need a server started first: `cesia test` runs the others,
and `cesia test tests/e2e` those.

## cesia test

`cesia test` runs every example and every test function of the project, and leaves out `std/` and `deps/`. With a path, it
runs those of a folder or of a file, and `file.ce:isName` runs one test, where a name that no test of the file has is a
failure, so that a typo can't pass:

```bash
cesia test
cesia test src/prices
cesia test src/prices/tax.test.ce
cesia test src/prices/tax.test.ce:isRoundsToCents
```

It prints each failure with its place, then how many passed and failed, and ends with the code 1 when one failed, so a script
or a CI can stop on it. A test that calls [sys.Exit], through the code it tests, fails with its own message, and the run goes
on: a test tells its verdict by its value, and only the run ends the program. Each folder is one package, so its examples and its tests run together. Files and packages run side
by side, each in a process of its own: a crash or a test that hangs stops only its own, and is named.

| Option | What it does |
|---|---|
| `--seed N` | the cases and the random numbers of an earlier run again |
| `--cases N` | how many cases each property tries, 100 by default |
| `--update` | accepts the new and the changed snapshots |
| `--allow LIST` | more permissions, beyond what a test may do by default |

### Without the versions by type

`cesia test --no-spec` runs them again without the versions of each function that Cesia makes for the types it sees. The
results must be the same: a difference is a bug of Cesia, worth reporting.

## Documenting your code

The first `(** *)` of a file, before any code, says what its package is for. A short definition has its text at the end of its
line, a field or a parameter too:

```cesia
use std/list
struct Item
  (** A line of an order. *)
  Product Text    (** what is sold *)
  Units Int       (** how many *)
end

Total(items) = list.Sum([i.Units for i in items])   (** How many units an order holds. *)
Total([Item("bread", 2), Item("cake", 1)]) -->
```

Every public name needs its text: a name with a capital is a promise to the code that uses it.

### Reading the texts

`cesia doc` shows the texts from the command line, and so does [cesia.Doc] from a program:

```bash
cesia doc src/prices
cesia doc prices.WithTax
```

```cesia
use std/cesia
cesia.Doc(Total) -->
```

## A site for your project

`cesia doc --site` builds a site of the project, as this one: a page for every module and every public name, with search.
The reference holds the modules of `std/` too, and the band at the top names the Cesia that made the site: the word
Cesia and its version (Cesia's own site shows the version alone). With `--open`, it opens the site in the browser. Its pages are written in `site/`, which `cesia new` keeps out of git.

```bash
cesia doc --site --open
```

### Books

A project can have books too, in `docs/`: each folder of Markdown pages there is a book, whose `index.md` links to its
chapters in their order. `docs/book/` is the home of the site, and another folder, as `docs/guides/`, is a book beside it. A
`files/` folder in a book holds the files its examples read. Every `cesia` block of a page runs when the site is built, and
what it prints is written under it. The blocks of a page are one program, in their order, so a name given in one block is
known in the next.

Words after `cesia` on the first line of a block change what is done with it:

| Word | What it does |
|---|---|
| `norun` | shows the block without running it: a server, a program that waits for input. It is still checked, and norun blocks that follow one another are one program, so a name given in one is known in the next |
| `fails` | the block must stop with an error, whose message is shown under it; one that doesn't fail stops the build |
| `allow=read,write,net,net=own,net=:PORT,ffi=m` | runs the block with these permissions; no other is given |
| `output=md` | what the block prints is Markdown, shown as a part of the page |
| `fold=code`, `fold=output` | the code, or what it printed, is folded, opened by a click |
| `hide=code`, `hide=output` | the code, or what it printed, is not shown |

A `toml` block must be a valid `cesia.toml`, unless it is marked `norun` too: the file of another program, as a server's.

This book is built that way, so its examples can't drift from the language: a block
that gives another value stops the build. Each page runs as a program of the project, from `.cesia/site/`, which `cesia new`
keeps out of git: its blocks can use the packages of `src/` and `deps/`, wherever the site is written.

```text
docs/
  book/
    index.md
    first-steps.md
    files/
  guides/
    index.md
```

### Formulas

A formula is written in TeX between two `$` in a line, or between two lines that hold `$$` alone, as a paragraph of its own:
the syntax GitHub shows too. The build writes it in MathML, which browsers show without a script, in the font STIX Two Math,
which only a page with a formula downloads. This source:

```markdown
A search in a sorted array of $n$ keys costs $O(\log n)$, and the birthday bound is

$$
P(\text{some collision among } k \text{ files}) \le \frac{k(k - 1)}{2} \times 2^{-256}
$$
```

reads: a search in a sorted array of $n$ keys costs $O(\log n)$, and the birthday bound is

$$
P(\text{some collision among } k \text{ files}) \le \frac{k(k - 1)}{2} \times 2^{-256}
$$

The `$` that opens a formula has no space after it; the next `$` closes it, with no space before it and no digit after it,
on the same line, and no backtick between them. So "it costs $5 and $6" holds no formula, `\$` writes a dollar, and a `$` in
code is code. The commands are those of the table; any other, or a character such as ≤ written as it is, stops the build
with its place and what to write: `docs/book/values.md:12: ≤ is no part of a formula: write \le`.

| Kind | Commands |
|---|---|
| relations | `\le` `\ge` `\ne` `\approx` `\equiv` `\sim` `\in` `\notin` `\ni` `\subset` `\subseteq` `\to` |
| operators | `\times` `\cdot` `\pm` `\cup` `\cap` `\bmod`, and `+ - = < > / ! , ; : .` |
| brackets | `( ) [ ] \|`, `\lceil` `\rceil` `\lfloor` `\rfloor`, `\{` `\}` |
| Greek | `\alpha` to `\omega`, `\Gamma` `\Delta` `\Theta` `\Lambda` `\Xi` `\Pi` `\Sigma` `\Phi` `\Psi` `\Omega` |
| functions | `\log` `\ln` `\exp` `\min` `\max` `\sin` `\cos`, with the thin spaces of TeX: $n \log n$ |
| sums and products | `\sum` `\prod`, their limits with `_` and `^`, beside them in a line and above and below in a display |
| structures | `x_i`, `2^{31}`, `f'`, `\frac{a}{b}`, `\sqrt{x}` |
| words and names | `\text{some words}`, upright; `\mathit{vlo}`, a name of several letters in italic |
| others | `\dots` `\infty` `\emptyset`; the spaces `\,` `\;` `\quad` and `\ `; `1{,}000` for a comma inside a number |

The font is a part of STIX Two Math 2.13 (the STIX Fonts Project, SIL Open Font License 1.1), cut to the characters a
formula can hold, 74 KB; the site holds it beside its licence, `math-OFL.txt`.

### Notes and warnings

A quote whose first line is one of GitHub's alerts, `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]`, is
shown in the color of its kind, under its name:

```markdown
> [!TIP]
> `cesia doc --site --open` builds the site and opens it.
```

> [!TIP]
> `cesia doc --site --open` builds the site and opens it.

### Colors

The `color` of the `[site]` table of `cesia.toml` is the color of the project, as `"#3b5bdb"`. The build makes from it the
colors of the links, the headings, the band at the top, the page open in the side, the heads and every other row of the
tables, and the code in a line, in the light look and the dark one. Each text reaches 4.5:1 against its background, the
AA level of WCAG 2.2, by the relative luminance it defines; a color that can't, too light or too pale, stops the build
with the pair and its ratio. Without `color`, the site takes `"#2b5fd9"`.

### The README

The `README.md` of the project is a page of the site, made from it at each build and shown in the side: its links to the
pages of `docs/`, or to a folder of it for its index, lead to the pages of the site. Any other link of the project, as one to
`LICENSE`, is no page of the site and stops the build: write it with its full URL. Its `cesia` blocks are shown in color,
never run.

### The ids of the headings

A heading's id is the one GitHub gives it: in lower case, without punctuation, each space a `-`, and `-1`, `-2` after a title
that comes again. "What's new?" is `whats-new`, so a link `page.md#whats-new` leads to the same place on GitHub and on the
site. The id the site gave it before, `what-s-new`, letters and digits joined by `-`, stays on the heading too, so a link
made then still leads there.

### A French site

`docs/fr/` holds the French of the books, under the same paths: `docs/fr/book/values.md` is the French of
`docs/book/values.md`, and `README.fr.md`, beside `README.md`, that of the README. The site then has a French side under
`fr/`, in `<html lang="fr">`: the same pages, the site's own words in French, a search of its own, and on every page a
switch between EN and FR that stays on the same page. A page not translated yet shows the English one under a note that
says so. The reference, made from the code, is in English on both sides: the French site links to it as "Référence (en
anglais)".

A French page keeps its English page's structure, and the build checks it: the same headings, of the same levels, in the
same order; the same blocks of code, byte for byte, since code is written in English; and the same links, a link to a heading
naming the heading at the same place of its page, since the French ids are those of French titles. A page that drifts stops
the build with its place, so a change of the English text shows where the French must follow; so does a page of `docs/fr/`
that is the French of no English page. The blocks being the same, they run once, for the English page, and the French one
shows what they printed on its own lines.

## Further reading

- Koen Claessen and John Hughes, *QuickCheck*, 2000: properties on random cases.
- David R. MacIver and Alastair F. Donaldson, *Test-Case Reduction via Test-Case Generation*, 2020: shrinking the draws,
  as [test.ForAll] does.
- Guy L. Steele Jr., Doug Lea and Christine H. Flood, *Fast Splittable Pseudorandom Number Generators*, 2014: SplitMix64,
  the generator behind the cases and [std/random].

Each with its link in [References](references.md#tests).

## Next

You can test and document your code. The next chapter, [The prompt and the debugger](debug.md), looks inside a program while it runs.
