# Files

## Reading

```cesia allow=read
use std/sys
Print(sys.Read("notes.txt").Value)
```

A block that stops can repeat a use of the page:

```cesia fails
use std/sys
sys.Write("notes.txt", "no")
```

A server and its client, on this machine only:

```cesia allow=net,net=:18751
use std/web
use std/http
app = web.App() then web.Get("/", r -> web.Plain("hello"), it)
server = Spawn(() -> web.Serve(app, port = 18751))
sys.Sleep(0.05)
http.Get("http://127.0.0.1:18751/").Value.Body -->
```

A --> in a comment or a text is no check of the book:

```cesia
defn twice(x)
  (** Twice x.

        twice(2) --> 5 *)
  x * 2
end
"a --> b" -->
```

Back to [the start](index.md).
