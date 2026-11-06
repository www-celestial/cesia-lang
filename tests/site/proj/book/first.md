# First steps

Names and [Len]:

```cesia
use src/greet
x = 2 + 3
x -->
x * 2 --> 10
Print(greet.Hello("Ana"))
Len("abc") -->
```

A value with a line end:

```cesia
"a\nb" -->
```

This one stops:

```cesia fails
Div(x, 0)
```

Not run:

```cesia norun
use std/http
http.Get("https://example.com")
```

A table made by code:

```cesia output=md hide=code
Print("| a | b |\n|---|---|\n| 1 | 2 |")
```

```cesia fold=output
for k in 1..3
  Print(k)
end
```

```toml
[project]
name = "x"
```
