# First steps

Names and [value.Len]:

```cesia
use src/greet
use std/io
use std/math
use std/value
x = 2 + 3
x -->
x * 2 --> 10
io.Print(greet.Hello("Ana"))
value.Len("abc") -->
```

A value with a line end:

```cesia
"a\nb" -->
```

This one stops:

```cesia fails
math.Div(x, 0)
```

Not run:

```cesia norun
use std/http
http.Fetch("https://example.com")
```

A table made by code:

```cesia output=md hide=code
io.Print("| a | b |\n|---|---|\n| 1 | 2 |")
```

```cesia fold=output
for k in 1..3
  io.Print(k)
end
```

```toml
[project]
name = "x"
```
