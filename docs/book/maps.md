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

A key can also be a text with any characters, or a number:

```cesia
{"first name": "Ana", 2: "two"} -->
```

## Reading

A dot reads the value of a key. It is short for the key in brackets, which also works with a key in a variable:

```cesia
person.Name -->
person["Name"] --> person.Name
key = "Age"
person[key] -->
```

A key that isn't there stops the program: a typo shows at once.

```cesia fails
person.City
```

When a key may be missing, [Get] gives `missing` instead, [GetOr] gives a default, and [Has] asks:

```cesia
Get("City", person) -->
GetOr("City", "unknown", person) -->
Has("Age", person) -->
```

## Changing

A dot or brackets on the left of `=` set a key. As for a list, only this name sees the change: a dictionary is a value, and
another name that held it keeps what it had.

```cesia
other = person
other.City = "Lyon"
other -->
person -->
```

Setting a key is short for [Put], which gives a new dictionary. [Drop] gives one without a key, and [Merge] joins two: for a key
in both, the second wins.

```cesia
Put("City", "Lyon", person) --> other
Drop("Age", person) -->
Merge(person, {Age: 32, Job: "baker"}) -->
```

## Order

A dictionary keeps its keys in the order they came in. Setting a key that is there keeps its place. Two dictionaries are equal
when they hold the same entries, whatever their order:

```cesia
{A: 1, B: 2} == {B: 2, A: 1} -->
Keys(Put("A", 10, {A: 1, B: 2})) -->
```

## Walking through

[Keys] gives the keys in their order, [Values] the values, and [Pairs] both, each as `{Key, Value}`. A `for` goes over one of
them: a dictionary itself is no list.

```cesia
for k in Keys(person)
  Print(k, "is", person[k])
end
```

```cesia
for p in Pairs(person)
  Print(p.Key, "->", p.Value)
end
```

[MapValues] changes every value with a function, and keeps the keys:

```cesia
MapValues(v -> Text(v), person) -->
```

## Counting

A dictionary is the tool for counting. Here, each word of a text gets its count. A word seen for the first time starts at 0:

```cesia
counts = {}
for word in Split(" ", "the cat and the dog and the bird")
  counts[word] = GetOr(word, 0, counts) + 1
end
counts -->
```

This is common enough to have its own function, [Frequencies]:

```cesia
Frequencies(Split(" ", "the cat and the dog and the bird")) --> counts
```

## Nested

A value can be a dictionary itself. [GetIn] reads at the end of a path of keys, and [PutIn] writes there, making the
dictionaries on the way:

```cesia
config = {Server: {Port: 8080, Host: "127.0.0.1"}}
config.Server.Port -->
GetIn(["Server", "Port"], config) --> config.Server.Port
PutIn(["Log", "Level"], "info", config) -->
```

## From lists

[Dict] builds a dictionary from `{Key, Value}` entries, the shape [Pairs] gives, and [Zipmap] from a list of keys and a list of
values:

```cesia
Dict([{Key: "a", Value: 1}, {Key: "b", Value: 2}]) -->
Zipmap(["a", "b"], [1, 2]) -->
```

## Next

You can keep values under names. A dictionary takes any key, which suits data that comes from outside. For data whose fields
you know in advance, the next chapter, [Structs](structs.md), names them once and checks them.
