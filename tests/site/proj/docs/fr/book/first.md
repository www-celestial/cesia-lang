# Premiers pas

Les noms,
puis [value.Len] :

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

Une valeur qui contient
une fin de ligne :

```cesia
"a\nb" -->
```

Celui-ci s’arrête :

```cesia fails
math.Div(x, 0)
```

Pas exécuté :

```cesia norun
use std/http
http.Fetch("https://example.com")
```

Un tableau fait par le code :

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
