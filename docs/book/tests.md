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

A test that gives `false` fails, and so does one that stops: an [bug.Assert] that is false, a bug. [bug.Assert] with a message says
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

A test function checks the cases you thought of. A property checks a rule on many cases that Cesia makes: [test.ForAll]
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
smallest:

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

A new snapshot fails and shows its text: read it, then `cesia test --update` accepts it. A changed one shows the lines that
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
  fiber.Spawn(() -> http.Serve(r -> {Status: 200, Body: "hi"}, listener = l))
  reply = http.Get("http://localhost:$(net.Port(l))/")?
  reply.Status == 200 and reply.Body == "hi"
end
```

A test has 10 seconds, and its fibers, sockets and servers end with it. `[test]` in `cesia.toml` changes that for the whole
project:

```toml
[test]
allow = ["exec=git"]
timeout = "30"
serial = ["tests/e2e"]
```

`allow` adds permissions, as `--allow` does; `timeout` is in seconds, written as a text; `serial` names the files and folders
that share something, as a database, and run alone, after the others.

## cesia test

`cesia test` runs every example and every test function of the project, and leaves out `std/` and `deps/`. With a path, it
runs those of a folder or of a file, and `file.ce:isName` runs one test:

```bash
cesia test
cesia test src/prices
cesia test src/prices/tax.test.ce
cesia test src/prices/tax.test.ce:isRoundsToCents
```

It prints each failure with its place, then how many passed and failed, and ends with the code 1 when one failed, so a script
or a CI can stop on it. Each folder is one package, so its examples and its tests run together. Files and packages run side
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
With `--open`, it opens the site in the browser. Its pages are written in `site/`, which `cesia new` keeps out of git.

```bash
cesia doc --site --open
```

### Books

A project can have books too, in `docs/`: each folder of Markdown pages there is a book, whose `index.md` links to its
chapters in their order. `docs/book/` is the home of the site, and another folder, as `docs/guides/`, is a book beside it. A
`files/` folder in a book holds the files its examples read. Every `cesia` block of a page runs when the site is built, and
what it prints is written under it. This book is built that way, so its examples can't drift from the language: a block
that gives another value stops the build.

```text
docs/
  book/
    index.md
    first-steps.md
    files/
  guides/
    index.md
```

## Next

You can test and document your code. The next chapter, [The prompt and the debugger](debug.md), looks inside a program while it runs.
