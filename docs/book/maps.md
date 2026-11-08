# Maps

In this chapter you keep values under names: a person with a name and an age, a count for each word of a text. Cesia calls
this a dictionary. You read it, add to it, take from it, and walk through it.

## A dictionary

A dictionary sits between braces: each entry is a key, a colon, and a value. A key that is a plain name, `Name`, is the text
`"Name"`:

```cesia
person = {Name: "Ana", Age: 31}
person -->
{Name: "Ana"} --> {"Name": "Ana"}
```

A key is a text or a number: a list, a dictionary or `missing` can't be one. A key can be a text with any characters:

```cesia
{"first name": "Ana", 2: "two"} -->
```

`1` and `1.0` are one key, as they are one number: `{1: "one"}[1.0]` is `"one"`.

## Reading

A dot reads the value of a key. It is short for the key in brackets, which also works with a key in a variable:

```cesia
person.Name -->
person["Name"] --> person.Name
key = "Age"
person[key] -->
```

### A key that isn't there

A key that isn't there stops the program: a typo shows at once.

```cesia fails
person.City
```

When a key may be missing, [dict.Get] gives `missing` instead, [dict.GetOr] gives a default, and [dict.Has] asks. `in`
asks too: `"Age" in person` is short for `dict.Has("Age", person)`.

```cesia
use std/dict
dict.Get("City", person) -->
dict.GetOr("City", "unknown", person) -->
dict.Has("Age", person) -->
"Age" in person --> dict.Has("Age", person)
```

## Changing

A dot or brackets on the left of `=` set a key. As for a list, only this name sees the change: a dictionary is a value, with
[value semantics](glossary.md#value-semantics), and another name that held it keeps what it had.

```cesia
other = person
other.City = "Lyon"
other -->
person -->
```

### Put, Drop and Merge

Setting a key is short for [dict.Put], which gives a new dictionary. The new one shares the rest of its memory with the old one,
which stays as it was: a [persistent data structure](glossary.md#persistent-data-structure). [dict.Drop] gives one without a key,
and [dict.Merge] joins two: for a key in both, the second wins.

```cesia
dict.Put("City", "Lyon", person) --> other
dict.Drop("Age", person) -->
dict.Merge(person, {Age: 32, Job: "baker"}) -->
```

## Order

A dictionary keeps its keys in the order they came in. Setting a key that is there keeps its place. Two dictionaries are equal
when they hold the same entries, whatever their order:

```cesia
{A: 1, B: 2} == {B: 2, A: 1} -->
dict.Keys(dict.Put("A", 10, {A: 1, B: 2})) -->
```

## Walking through

[dict.Keys] gives the keys in their order, [dict.Values] the values, and [dict.Pairs] both: each pair is a struct with a `Key` and a
`Value`. A `for` goes over one of them: a dictionary itself is no list.

```cesia
use std/io
for k in dict.Keys(person)
  io.Print(k, "is", person[k])
end
```

```cesia
for p in dict.Pairs(person)
  io.Print(p.Key, "->", p.Value)
end
```

### Every value at once

[dict.MapValues] changes every value with a function, and keeps the keys:

```cesia
use std/value
dict.MapValues(v -> value.Text(v), person) -->
```

## Counting

A dictionary is the tool for counting. Here, each word of a text gets its count. A word seen for the first time starts at 0:

```cesia
use std/text
counts = {}
for word in text.Split(" ", "the cat and the dog and the bird")
  counts[word] = dict.GetOr(word, 0, counts) + 1
end
counts -->
```

### Frequencies

This is common enough to have its own function, [list.Frequencies]:

```cesia
use std/list
list.Frequencies(text.Split(" ", "the cat and the dog and the bird")) --> counts
```

### Combining dictionaries

[dict.Update] applies a function to the value of one key, [dict.MergeWith] joins two dictionaries and combines the values
of a key in both with a function, [dict.SelectKeys] keeps the keys of a list, and [dict.Invert] swaps the keys and the
values:

```cesia
use std/math
dict.Update("Age", math.Inc, person) -->
dict.MergeWith(math.Add, {bread: 2, cake: 1}, {bread: 3}) -->
dict.SelectKeys(["Name"], person) -->
dict.Invert({a: "x", b: "y"}) -->
```

## Nested

A value can be a dictionary itself. [dict.GetIn] reads at the end of a path of keys, and [dict.PutIn] writes there, making the
dictionaries on the way:

```cesia
config = {Server: {Port: 8080, Host: "127.0.0.1"}}
config.Server.Port -->
dict.GetIn(["Server", "Port"], config) --> config.Server.Port
dict.PutIn(["Log", "Level"], "info", config) -->
dict.UpdateIn(["Server", "Port"], it + 1, config).Server.Port -->
```

## From lists

[dict.Dict] builds a dictionary from a list of entries, each with a `Key` and a `Value`, the shape [dict.Pairs] gives. [dict.Zipmap] builds
one from a list of keys and a list of values:

```cesia
dict.Dict([{Key: "a", Value: 1}, {Key: "b", Value: 2}]) -->
dict.Zipmap(["a", "b"], [1, 2]) -->
```

## How a dictionary is stored, and what it costs

Up to 32 keys, a dictionary is one block: its keys in their order, beside their hashes, and its values. Past 32, while
one name alone holds it, it is a [hash table](glossary.md#hash-table) in the order of insertion, as Python's `dict`: a
read or a write takes a constant time on average, changed in place. Once it is shared and written, as by [dict.Put], it
becomes, once and for good, a [hash array mapped trie](glossary.md#hash-array-mapped-trie) of the kind called
[CHAMP](glossary.md#champ): a tree whose levels are chosen by 5 bits of each key's hash at a time, each node holding the
keys that are alone at their 5 bits, so a read or a write takes about log₃₂ n steps, 3 for 30,000 keys, and a write
copies only the few small nodes on the path to its key. That is how [dict.Put] can give a new dictionary and keep the old
one, at a small cost; the change of form costs about 0.25 s for a million keys, once.
The hash takes a seed drawn at each run, so nobody can send a server keys chosen to collide.
[How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie) shows the details.

A dictionary that nothing else holds is changed in place, so the loop of [Counting](#counting) copies nothing. 500,000
text keys written then read take 0.28 s, against 0.41 s for Python's `dict`, 0.27 s for Go's map and 0.22 s for Java's
`HashMap`, as [Speed](speed.md#computing) measures.

## Further reading

- Python 3.6's compact `dict`, after a design of Raymond Hettinger: the hash table of a dictionary that one name holds.
- Phil Bagwell, *Ideal Hash Trees*, 2001: the hash array mapped trie; Michael J. Steindorfer and Jurgen J. Vinju,
  *Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM Collections*, 2015: CHAMP, its nodes.
- Rich Hickey, *A History of Clojure*, 2020: persistent maps as a language's everyday dictionary.
- James R. Driscoll and others, *Making data structures persistent*, 1989; Chris Okasaki, *Purely Functional Data
  Structures*, 1998.
- Scott A. Crosby and Dan S. Wallach, *Denial of Service via Algorithmic Complexity Attacks*, 2003: why the hash takes a
  seed.

Each with its link in [References](references.md#values-and-maps).

## Next

You can keep values under names. A dictionary takes any key, which suits data that comes from outside. For data whose fields
you know in advance, the next chapter, [Structs](structs.md), names them once and checks them.
