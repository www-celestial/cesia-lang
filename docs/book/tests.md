# Tests

In this chapter you check that your code does what it should, and keeps doing it as you change it. Cesia has two kinds of
tests: examples written in the documentation of a function, and test functions in `.test.ce` files. `cesia test` runs both.
Then you document your code, and build a site of it like this one.

## Examples in the documentation

A comment that starts with `(**` documents what it belongs to. Inside a `defn`, it comes first. An example in it, indented,
with `-->` and the value it should give, is a test, a [doctest](glossary.md#doctest):

```cesia
defn WithTax(price Number) Number
  (** The price with 20% of tax, to the cent.

        WithTax(10.0) --> 12.0
        WithTax(0.99) --> 1.19 *)
  cents(price * 1.2)
end

cents(x) = Round(x * 100) / 100
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
isZeroStaysZero() = WithTax(0) == 0
defn isRoundsToCents()
  Assert(WithTax(1.234) == 1.48, "1.234 rounds down")
  WithTax(1.235) == 1.48
end
isZeroStaysZero() -->
isRoundsToCents() -->
```

A test that gives `false` fails, and so does one that stops: an [Assert] that is false, a bug. [Assert] with a message says
which part of a long test went wrong.

## cesia test

`cesia test` runs every example and every test function of the project, and leaves out `std/` and `deps/`. With a path, it
runs those of a folder or of a file:

```bash
cesia test
cesia test src/prices
cesia test src/prices/tax.test.ce
```

It prints each failure with its place, then how many passed and failed, and ends with the code 1 when one failed, so a script
or a CI can stop on it. Each folder is one package, so its examples and its tests run together.

### Without the versions by type

`cesia test --no-spec` runs them again without the versions of each function that Cesia makes for the types it sees. The
results must be the same: a difference is a bug of Cesia, worth reporting.

## Documenting your code

The first `(** *)` of a file, before any code, says what its package is for. A short definition has its text at the end of its
line, a field or a parameter too:

```cesia
struct Item
  (** A line of an order. *)
  Product Text    (** what is sold *)
  Units Int       (** how many *)
end

Total(items) = Sum([i.Units for i in items])   (** How many units an order holds. *)
Total([Item("bread", 2), Item("cake", 1)]) -->
```

Every public name needs its text: a name with a capital is a promise to the code that uses it.

### Reading the texts

`cesia doc` shows the texts from the command line, and so does [Doc] from a program:

```bash
cesia doc src/prices
cesia doc prices.WithTax
```

```cesia
Doc(Total) -->
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

You can test and document your code. The next chapter, [C and C++](c.md), calls the libraries of the system from Cesia.
