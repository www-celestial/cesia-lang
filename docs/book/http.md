# HTTP

In this chapter you make a site, then call one. You write a web server, with routes, parameters in the path, JSON in and out,
and a log of each request; you test it without the network; you serve it; and you ask it with the client, from the same
program. All of it is in [std/http].

## An application

[http.App] starts an application with no route. Each [route](glossary.md#route) adds one: a method, a path, and a
[handler](glossary.md#handler), the function of the request that gives the response. [http.Get] adds a route for `GET`,
[http.Post] one for `POST`, as [http.Put] and [http.Delete] do for theirs. [http.Plain] makes a plain text response, and
[http.Json] a JSON one:

```cesia
use std/http
app = http.App()
  then http.Get("/", r -> http.Plain("Welcome"))
  then http.Get("/hello/:name", r -> http.Plain("Hello, $(r.Params.name)!"))
  then http.Get("/stock", r -> http.Json({bread: 40, cake: 6}))
```

### Words in the path

A part of a path that starts with `:` takes any word, and the handler finds it in `r.Params`. The application is a value: each
route gives a new one, and [then] chains them.

### A handler of several lines

A handler of several lines is written after its route, as a [do block](functions.md#do-blocks), with `_` in the place
of the handler: the path comes first. Without the `_`, the block would take the first place, that of the path.

```cesia
use std/text
app = app
  then http.Get("/shout/:word", _) do r
    word = text.Upper(r.Params.word)
    http.Plain("$(word)!")
  end
```

The same route, with the handler written inside the parentheses, the older way:

```cesia
same = http.App()
  then http.Get("/shout/:word", defn (r)
    word = text.Upper(r.Params.word)
    http.Plain("$(word)!")
  end)
```

## Trying it without the network

[http.Handler] gives the function that the server calls for each request. You can call it yourself, with a request as a
dictionary, which is how you test a server:

```cesia
use std/io
handle = http.Handler(app)
ask(path) = handle({Method: "GET", Path: path, Query: "", Headers: [], Body: ""})
ask("/hello/Ana").Body -->
ask("/shout/hey").Body -->
ask("/stock").Status -->
io.Print(ask("/stock").Body)
ask("/nowhere").Status -->
```

A path that no route takes gets a `404`.

## How a request finds its route

The first route added that takes the path, then the method, answers. A written part of a pattern takes only itself, a
part with `:` any word, and a final `*` the rest of the path. A route of `:id` added before one of `me` would take
`/users/me` too; added after it, as here, it takes the other words:

```cesia
users = http.App()
  then http.Get("/users/me", r -> http.Plain("you"))
  then http.Get("/users/:id", r -> http.Plain("user $(r.Params.id)"))
askUsers(method, path) = http.Handler(users)({Method: method, Path: path, Query: "", Headers: [], Body: ""})
askUsers("GET", "/users/me").Body -->
askUsers("GET", "/users/7").Body -->
askUsers("HEAD", "/users/7").Status -->
askUsers("DELETE", "/users/7").Status -->
```

The path comes first: a path that only routes of other methods take gets a `405`, Method Not Allowed, and a `HEAD` the
route of its `GET`, whose body the server leaves out.

[http.Handler] puts the routes in a [trie](glossary.md#trie) of the parts of their paths, once: each written part leads to
a branch of its own, found by a hash table, and the `:` parts of one place share one branch. A request follows the parts
of its own path down the tree, so its route costs the same to find among 500 routes as among 5. Each route keeps its
place in the order they were added, and the walk leaves out a branch whose routes all come after the one it has found:
the answer is always the one the routes tried one by one would give, which `tests/lang/http-routes.ce` checks on random
sets of routes.

An API of 200 routes, 40 resources with their list, their creation, one item, its change and its removal:

```cesia
defn api(resources)
  a = http.App()
  for name in resources
    a = a
      then http.Get("/api/v1/$name", r -> http.Json([]))
      then http.Post("/api/v1/$name", r -> http.Json({Made: true}, status = 201))
      then http.Get("/api/v1/$name/:id", r -> http.Json({Id: r.Params.id}))
      then http.Put("/api/v1/$name/:id", r -> http.Json({Changed: r.Params.id}))
      then http.Delete("/api/v1/$name/:id", r -> http.Plain("", status = 204))
  end
  a
end
shopApi = http.Handler(api(["res$i" for i in 1..40]))
askApi(method, path) = shopApi({Method: method, Path: path, Query: "", Headers: [], Body: ""})
askApi("GET", "/api/v1/res40/7").Body -->
askApi("PATCH", "/api/v1/res40/7").Status -->
```

What it costs, measured on 2026-11-25 on the machine of [Speed](speed.md#beside-the-giants): the handler called with a
request and no network, so the route, its params and the handler's response, in microseconds, the medians of 5 runs
alternated with the version before the tree, which tried the routes one by one, and beside the `ServeMux` of Go 1.26.3
doing the same, its `ServeHTTP` called directly.

| Routes, and the one asked | One by one | The tree | Go's `ServeMux` |
|---|---:|---:|---:|
| 10, the first | 3.0 | 3.1 | 0.32 |
| 10, the last | 6.7 | 2.8 | 0.30 |
| 100, the last | 44.8 | 2.8 | 0.28 |
| 500, the last | 235 | 2.9 | 0.33 |
| 500, a path that none takes: a `404` | 243 | 0.84 | 1.48 |
| the API above, its last item | 159 | 3.5 | 0.36 |

Go is 8 to 12 times faster on a route that answers, as its handler is compiled where Cesia's runs in the interpreter: a
request that no route takes runs no handler, and gets its `404` from Cesia in 0.84 µs, faster than Go. The tree costs
once what the routes tried one by one didn't: 91 µs to build for the 200 routes of the API, when [http.Handler] is
called, at the start of a server.

## JSON in

[http.BodyJson] reads the body of a request as JSON. With `From`, the body is checked before your code uses it, and a wrong one
gets a `400` that says what is wrong:

```cesia
use std/result
struct Purchase
  Product Text
  Units Int
end

defn addPurchase(request)
  match http.BodyJson(request) then result.AndThen(Purchase.From)
    result.Ok(order) -> http.Json({Product: order.Product, Units: order.Units, Total: order.Units * 1.25}, status = 201)
    result.Err(e) -> http.Json({Error: e.Message}, status = 400)
  end
end

shop = app then http.Post("/orders", addPurchase)
post(body) = http.Handler(shop)({Method: "POST", Path: "/orders", Query: "", Headers: [], Body: body})
io.Print(post("{\"Product\": \"bread\", \"Units\": 4}").Body)
io.Print(post("{\"Product\": \"bread\", \"Units\": \"four\"}").Body)
io.Print(post("not json").Body)
```

## Middleware

A [middleware](glossary.md#middleware) sits in front of the routes: it sees each request, and the response that comes back. [http.Logger] writes a line
per request, as [Logs and metrics](#logs-and-metrics) says. [http.Wrap] puts a middleware in front of an application:

```cesia
logged = http.Wrap(http.Logger, shop)
http.Handler(logged)({Method: "GET", Path: "/stock", Query: "", Headers: [], Body: ""}).Status -->
```

### A middleware of your own

A middleware of your own is a function of `next` and the request, which calls `next(request)` to go on. `servedBy` adds a
header to each response, which says what served it:

```cesia
defn servedBy(next, request)
  response = next(request)
  http.WithHeader("x-served-by", "cesia", response)
end
http.Handler(http.Wrap(servedBy, shop))({Method: "GET", Path: "/", Query: "", Headers: [], Body: ""}).Headers -->
```

![A GET / request goes through the middleware servedBy, which calls next(request), to the routes of shop, where the first that fits, GET /, leads to its handler, which gives 200 and Welcome; the response comes back through servedBy, which adds the header x-served-by, and leaves with 2 headers.](images/http-middleware.svg)

## Serving

[http.Serve] serves an application until the program gets a stop signal, as Ctrl-C: see [Stopping](#stopping). It listens on port 8080 unless `port`
says otherwise, and on `127.0.0.1`, this machine only, unless `host` does. It needs the permission to listen on its port.
Here is a small `shop.ce`:

```cesia norun
(* shop.ce: one route, served on port 8080 *)
use std/http

hello = http.App()
  then http.Get("/hello/:name", r -> http.Plain("Hello, $(r.Params.name)!"))
http.Serve(http.Wrap(http.Logger, hello))
```

Run it, and ask it from another terminal:

```bash
cesia run --allow net=:8080 shop.ce
curl localhost:8080/hello/Ana
```

Each response it sends has a `Date` header, the time of the response in the form of RFC 9110 (section 5.6.7), as
`date: Wed, 25 Nov 2026 13:40:00 GMT`, since a server with a clock must send one (section 6.6.1): caches and clients
read the age of a response from it. The server writes the line again when the second changes, not for each response. A
handler that sets its own `Date`, by [http.WithHeader], keeps it; the responses of [http.Handler], which no network
carries, have none.

### Stopping

A stop signal stops a server cleanly: TERM, which systemd, Docker and Kubernetes send, INT, which Ctrl-C sends, or HUP,
which a terminal sends as it closes. The server accepts no more connections, and the requests in progress end, each by
its deadline, with a response that tells its client that the connection closes, so that the client asks again
elsewhere. Then [http.Serve] gives `Ok`, and the program goes on to its end, which gives the exit code 0 unless it says
otherwise. A second signal doesn't wait: the program ends at once, with 128 and the number of the signal, 143 for TERM
and 130 for INT, as a shell gives them. The programs it started with [sys.Start] or [sys.Run] hear of the first signal
too, as the chapter [Files](files.md#programs-that-keep-running) says. Started by `cesia do serve`, the server is still
one process: the last task takes the place of `cesia do`, as the chapter Commands says, so the TERM of a supervisor
reaches it once, and its stop is a clean one.

### Every core

A server runs on one core. `--workers` runs several, which serve the same port together, as many as `N`, or one per core
with `cores`:

```bash
cesia run --workers cores --allow net=:8080 shop.ce
```

The first process runs the program up to its listener, opens it, and becomes the supervisor: it starts the workers and
serves nothing itself. Each worker runs the program from its start, and takes its connections from that one listener,
which the supervisor keeps open. The workers share nothing but the port: each has its memory, its fibers and its
values, as programs of their own, and what they must share goes to a database. The supervisor starts again a worker
that ends, and TERM or Ctrl-C stops them all, each as [Stopping](#stopping) says; it ends with 0 when they all did. A
program that can't start, as one with an error, ends at once, with the code of its first worker. `--workers` needs
Linux or macOS: on Windows, a program serves on one core. This is the *pre-fork* model of nginx: processes, not threads,
so a bug in one worker can't touch the memory of another, and the supervisor starts a new one;
[How Cesia works](internals.md#on-every-core) shows it in detail.

Measured on 2026-11-07 on the machine of [Speed](speed.md#beside-the-giants), one run of `tools/http-bench.sh` with the
server on two physical cores and their two hyperthreads, and the load client on the other four, requests per second:

| Load | 1 process | `--workers 2` | `--workers 4` | Go, 4 cores |
|---|---:|---:|---:|---:|
| tiny route, 100 kept connections | 57,215 | 116,982 | 94,978 | 98,479 |
| tiny route, 1,000 kept connections | 34,752 | 67,890 | 84,188 | 89,337 |
| JSON route, 100 kept connections | 41,340 | 80,020 | 72,132 | 78,988 |
| a new connection per request, 100 | 28,674 | 45,850 | 38,690 | 29,750 |

```cesia allow=read,write
use std/plot
workers = plot.Bars(["tiny 100", "tiny 1,000", "JSON 100", "new 100"], [[57215, 34752, 41340, 28674],
  [116982, 67890, 80020, 45850], [94978, 84188, 72132, 38690], [98479, 89337, 78988, 29750]],
  label = ["1 process", "--workers 2", "--workers 4", "Go, 4 cores"], color = ["#9aaae8", "#3a5ad9", "#1d2d6c", "#000000"])
cores = plot.Of([workers], title = "Requests per second on four cores, one run",
  x = "route, connections", y = "requests per second", size = [640, 360])
plot.Save(cores, "http-workers.svg") -->
```

Two workers double one process. Four gain only at 1,000 connections, since the machine has four physical cores, two of
which ran the client.

### A new version without a pause

HUP replaces the workers of a server under `--workers`: new ones start from the files as they are now, and once each of
them accepts, the old ones stop as on TERM, each after its requests in progress. The listener never closes, so no
connection is refused or lost in between, and no request fails. A new version that can't start, as one with an error,
leaves the running workers alone:

```bash
kill -HUP $(pgrep -o -f "cesia run --workers")
```

Under systemd, `ExecReload=/bin/kill -HUP $MAINPID` does it with `systemctl reload`. Without `--workers`, HUP stops the
server, as TERM does.

### Logs and metrics

[std/log] writes a line of JSON for each event, with its time in UTC, its level and its message, then the fields given:
tools such as jq, Loki or Datadog read them as they come. [log.Info], [log.Warn] and [log.Error] give the level:

```cesia
use std/log
log.Info("order placed", {Order: 7, Total: 12.5})
```

[http.Logger] writes one of these lines for each request, with its method, its path, its status and the milliseconds it
took. [std/metrics] counts: [metrics.Add] adds to a counter, [metrics.Observe] puts a value, as the seconds a request
took, in a histogram, and [metrics.Text] gives them all in the text format that Prometheus reads, for a route of the
program. [http.Metrics] counts each request by method and status, with its time:

```cesia
use std/metrics
use std/text
counted = shop then http.Get("/metrics", r -> http.Plain(metrics.Text())) then http.Wrap(http.Metrics)
http.Handler(counted)({Method: "GET", Path: "/stock", Query: "", Headers: [], Body: ""}).Status -->
text.Contains("http_requests_total{method=\"GET\",status=\"200\"} 1", metrics.Text()) -->
```

Nothing is logged or counted unless the program asks. A line of the log costs about 5 microseconds and a count about 3,
which a server that answers in 17 sees: on one core, at 100 kept connections, a tiny route answered 57,000 to 60,000
requests a second without them, 44,000 to 49,000 with [http.Logger], and 50,000 to 53,000 with [http.Metrics], measured on
2026-11-07. Under `--workers`, each worker counts its own requests, and a scrape reads the
counts of the worker that answers it; their log lines don't cut each other.

### Serving and asking in one program

The block below serves the shop on a port and asks it with the client, [http.Fetch], in one program. [fiber.Spawn] runs the server beside the
rest of the program, as the chapter [Fibers](fibers.md) explains, and [sys.Sleep] lets it start. `net=own` is the permission
for that: the program listens on this machine, and connects only to its own listeners.

```cesia allow=net=own
use std/sys
use std/fiber
fiber.Spawn(() -> http.Serve(logged, port = 18761))
sys.Sleep(0)
r = http.Fetch("http://127.0.0.1:18761/hello/Bo")
r.Value.Status -->
r.Value.Body -->
sent = http.Fetch("http://127.0.0.1:18761/orders", method = "POST", body = "{\"Product\": \"cake\", \"Units\": 2}")
io.Print(sent.Value.Body)
```

The program ends when its last line is done, and the server with it.

### What a server holds

A server faces clients that are slow, greedy or broken, and keeps serving the others:

- Each request has `timeout` seconds, 60 unless [http.Serve] says otherwise, to arrive and to be answered. A client that
  sends a byte at a time is closed at its deadline. A handler that takes longer gets a `503` for its client, and runs on
  alone; [fiber.Wait] with a `timeout` is how the server waits for it.
- A head of more than 16 KB gets a `431`, a body larger than `maxBody`, 1 MB unless [http.Serve] says otherwise, a `413`.
- The bodies being read at once take at most a quarter of the memory limit, which `--limit memory=` sets and is 80% of
  the RAM otherwise: past it, a request with a body gets a `503` at once, instead of the server reaching the limit.
- A handler that panics gets a `500`, and so does one that takes more memory than the limit: only its request fails.

### A body in pieces

A response is made whole before it goes, which an export of a large table can't afford. [http.Stream] sends its body
in pieces as they are made, each a *chunk* of HTTP/1.1 (RFC 9112, section 7.1): `send(piece)` hands one to the
client, and the body ends when the function returns.

```cesia norun
use std/csv
use std/result
invoices(page) = [["INV-$page", "paid", 120]]   (* a page of the table, as a database gives it *)
defn export(send)
  for page in 1..100
    send(csv.Text(invoices(page)))?
  end
  result.Ok(missing)
end
app = http.App() then http.Get("/invoices.csv", r -> http.Stream(export, headers = [{Name: "content-type", Value: "text/csv"}]))
```

- `send` gives an `Err` once the client is gone, or when a piece took more than `timeout` seconds to come or to be
  taken: a client that stops reading holds the server's fiber for one timeout, and one piece in memory, no more. The
  `?` after `send` stops the export then.
- A panic in the middle, or an `Err` that the function gives, cuts the body short, without its last chunk, so the client
  sees an error rather than a body that looks whole.
- `HEAD` gets the head alone, and the function doesn't run; a client of HTTP/1.0, which knows no chunks, gets the pieces
  as they are, and the connection ends with the body.

Measured on 2026-11-13, an export of 100,000 rows of 7 cells, 6 MB of CSV, the rows made as they are asked, as a
database gives them (`bench/export.ce`): the peak of the server's memory grew by 77 MB for the whole body, by 32 MB in
pieces of 1,000 rows, most of it what the collector had not yet taken back of the pages before.

### A body that comes in pieces

A request's body is read whole before its handler runs, at most `maxBody` bytes: a file sent to the server can't fit.
A route given `stream`, the most bytes its body may hold, gets a body too large for one read in pieces instead, as the
handler reads them: `r.Body` is `""`, `r.Size` its length, and `r.Read()` gives an `Ok` of the next piece, `""` once
it is all read, or an `Err` when the client stops sending.

```cesia norun
use std/result
use std/text
defn upload(r)
  (* stores a scan as it comes; a small one came whole, in r.Body *)
  n = 0
  piece = r.Read()?
  while piece != ""
    n += text.ByteLength(piece)   (* write it where it goes: a part of a file of the database *)
    piece = r.Read()?
  end
  http.Plain("$n bytes")
end
app = http.App() then http.Route("POST", "/scans", upload, stream = 10485760)
```

- The body is read only as the handler asks for it, a piece at a time (what one read of the socket brings, 64 KiB at
  most): the server never holds it whole, whatever its size.
- A body larger than `stream` gets a `413` before the handler runs; a head with two `Content-Length` lines a `400`, as
  for any request.
- A client that sent `Expect: 100-continue`, as curl does for a large body, is told to go on at the first `Read` only:
  a handler that refuses the request first (a `401`, a type it doesn't take) answers before the client sent its body.
- The handler has the request's `timeout`, plus a second for each 64 KiB of the body, and each piece must come within
  `timeout` seconds of the one before: a client that sends a byte a minute is closed, one on a slow line is not.
- The connection closes after the response.
- A body that came whole, small enough for one read, is in `r.Body`, and `r.Read` is missing: a handler that takes
  both looks for `Read` with `dict.Has("Read", r)`.

## More of std/http

| To | Use |
|---|---|
| add a route | [http.Get], [http.Post], [http.Put], [http.Delete], [http.AnyMethod] for any method, [http.Route] for any one by name; a final `*` in a path takes the rest of it, in `r.Params["*"]` |
| serve files | [http.Static] serves a folder under a prefix, and no path can leave the folder; [http.FileResponse] sends one file, its type from its extension |
| answer | [http.Plain], [http.Json], [http.Html], [http.Redirect], [http.NotFound], [http.Stream] for a body in pieces; [http.WithHeader] adds a header, [http.SetCookie] a cookie; [http.Reason] is the text of a status |
| read a request | [http.BodyJson] its body as JSON, [http.Form] as a form, [http.HeaderValue] a header by its name in lower case; `r.Peer` is the address of the client, without its port, as [net.Peer] gives it, to limit a client by; [http.ParseUrl] takes a URL apart |
| pass data on | a middleware puts a key in the request, as the person signed in, and the handler finds it there: see [http.Wrap] |
| wrap | [http.Logger], [http.Metrics], [http.Cors], which lets the pages of another origin read the responses, and [http.SameOrigin], which refuses the requests of another site: see below |
| write HTML | [http.Escape] escapes a value for a page, [http.Template] fills `{{name}}` with escaped values |
| the defaults | [http.DefaultTimeout] is 60 seconds, [http.DefaultMaxBody] 1,048,576 bytes |

```cesia
files = http.App() then http.Route("PATCH", "/files/*", r -> http.Plain(r.Params["*"]))
http.Handler(files)({Method: "PATCH", Path: "/files/a/b.txt", Query: "", Headers: [], Body: ""}).Body -->
http.Redirect("/login").Headers -->
http.Reason(404) -->
http.Template("<p>Hello, {{name}}!</p>", {name: "<Ana>"}) -->
```

### Escaping

[http.Template] and [http.Escape] write `<` as `&lt;`, `&` as `&amp;` and the quotes as `&quot;` and `&#39;`. Without
that, a name typed by a visitor, as `<script>...</script>`, would run as code in the page of every other visitor: *cross-site
scripting*, XSS. A value goes into a page escaped, as a value goes into SQL through `?`.

### Requests from another site

A page of another site can make the browser of a visitor send a request to your app, with the visitor's cookies: a form
that posts to `/pay`, a WebSocket that opens. That is *cross-site request forgery*, CSRF. [http.SameOrigin], a
middleware, gives such a request a `403` when it can change something: any method but `GET`, `HEAD` and `OPTIONS`, and
the `GET` that opens a WebSocket.

```cesia
pay = http.Handler(http.App() then http.Post("/pay", r -> http.Plain("paid")) then http.Wrap(http.SameOrigin))
pay({Method: "POST", Path: "/pay", Query: "", Headers: [{Name: "sec-fetch-site", Value: "cross-site"}], Body: ""}).Status -->
pay({Method: "POST", Path: "/pay", Query: "", Headers: [{Name: "sec-fetch-site", Value: "same-origin"}], Body: ""}).Status -->
```

It reads what the browser writes, which no page can change:

- `Sec-Fetch-Site`, which every browser sends since 2023 (W3C, Fetch Metadata): `same-origin` passes, and `none`, an
  address the person typed; `same-site`, a sibling host such as `blog.shop.example`, and `cross-site` get the `403`.
- Without it, the `Origin` of an older browser, `scheme://host:port`, must be `http://` or `https://` then the `Host` of
  the request, its port too. The letters A to Z match in either case, any other byte only itself: a browser writes an
  international name in Punycode, in ASCII (RFC 6454), so no change of case can make two hosts one.
- A request with neither comes from no browser, so from no visitor's cookies: it passes, and the app checks who sent it,
  by a cookie or a token.

These are the steps of `http.CrossOriginProtection` in Go 1.25, with their limit: by the `Origin` alone the scheme isn't
checked, since the `Host` has none, so an older browser lets a page of `http://shop.example`, which a machine on the way
can forge, post to `https://shop.example`. HSTS, the `Strict-Transport-Security` header, closes that: the browser never
opens the `http://` page. [live.Route] checks its WebSockets the same way.

## WebSocket

A *WebSocket*, RFC 6455, is a connection that stays open after an HTTP request and carries messages both ways, for a chat
or a live page. [http.Websocket] adds a route of one: `onMessage(text, send)` runs for each message, and `send(text)`
answers. The handshake, the *upgrade* of the request, gives the status `101`; [std/websocket] does the rest, with
[websocket.Accept], a silent connection closed after [websocket.DefaultIdle] seconds, a frame larger than
[websocket.MaxFrame] refused, a text or the reason of a close that isn't UTF-8 closed with 1007, and a close whose code
RFC 6455 §7.4 refuses, or of one byte, closed with 1002. A frame that comes in pieces is read into one buffer, joined
once:

```cesia
chat = http.Handler(http.App() then http.Websocket("/chat", (m, send) -> send(m)))
handshake = [{Name: "upgrade", Value: "websocket"}, {Name: "sec-websocket-key", Value: "dGhlIHNhbXBsZSBub25jZQ=="}]
chat({Method: "GET", Path: "/chat", Query: "", Headers: handshake, Body: ""}).Status -->
chat({Method: "GET", Path: "/chat", Query: "", Headers: [], Body: ""}).Status -->
```

### A client

[websocket.Dial] opens a connection to a server, as a browser does: it connects to a `ws://` URL and makes the
handshake, the HTTP request by which the client asks the server to switch the connection to WebSocket. It gives an `Ok`
of a [websocket.Conn], whose field `Messages` is a channel of [std/fiber]: each message of the server comes on it whole,
in order, and the channel closes when the connection ends. [websocket.Send] sends a text message, and [websocket.Close]
closes the connection and tells how it ended:

```cesia allow=net=own
use std/websocket
use std/net
use std/fiber
listener = net.Listen(0).Value
fiber.Spawn(() -> http.Serve(http.App() then http.Websocket("/echo", (m, send) -> send(m)), listener = listener))
c = websocket.Dial("ws://127.0.0.1:$(net.Port(listener))/echo").Value
websocket.Send("hi", c) -->
fiber.Receive(c.Messages, timeout = 1) -->
websocket.Close(c) -->
```

`headers`, a list of `{Name, Value}` as [http.Fetch] takes, go with the handshake: a cookie, for a server that knows
its visitors by one, or an `Origin`, for a server that checks where a page comes from, as [http.SameOrigin] does. A name that isn't a *token* of
RFC 9110, letters, digits and marks such as `-` and `_`, a name the handshake writes itself (`Host`, `Upgrade`, `Connection`,
`Content-Length`, `Transfer-Encoding`, and those that start with `Sec-WebSocket-`), or a line end or a zero byte in a
value, gives an `Err` before any connection: a value from a visitor can't add a header of its own, which is *header
injection*.

```cesia allow=net=own
websocket.Dial("ws://127.0.0.1:1/", headers = [{Name: "Cookie", Value: "sid=1\r\nX-Admin: 1"}]) -->
```

Receiving has no function of its own: it is the channel, so all that [Fibers](fibers.md) do with a channel works on it: a
`for` loop, which is [fiber.Receive] again and again until the channel closes, a timeout, [fiber.Select]. The connection comes last in [websocket.Send], as the channel does in
[fiber.Send]: a connection carries messages as a channel does. Fibers may send at once; each message goes out whole.

```cesia norun
for m in c.Messages
  io.Print(m)
end
got = fiber.Select([sys.Stops(), c.Messages], timeout = 30)
```

What the client does for RFC 6455, so that a program never has to:

- Each frame it sends, a header of a few bytes then the bytes of the message, is *masked*: its bytes are xored with a
  key of 4 bytes, new for each frame, from the system's source of randomness (§5.3). A proxy between the two, a program
  that passes the bytes on, then never sees bytes that the program chose, and can't be made to keep a forged response in
  its cache (§10.3).
- It answers each *ping*, a frame by which the server checks that the client is still there, with a *pong* of the same
  bytes (§5.5.2), and it joins the *fragments* of a message, the frames a server may cut it into, once, at its end
  (§5.4).
- It refuses what the RFC refuses, and closes with the *close code*, a number that says why: 1002, a protocol error, for
  a masked frame from the server, a reserved bit or opcode (the number of the kind of frame), or a control frame past
  125 bytes (§5.1, §5.2, §5.5); 1007 for a text that isn't UTF-8 (§8.1); 1009 for a message past `maxMessage` bytes,
  [websocket.DefaultMaxMessage] (64 MiB) unless `Dial` says otherwise, refused from the header of its frame, before its
  bytes are read (§10.4), each fragment counted 64 bytes more than it holds, so that empty ones can't fill the memory. [websocket.Close] then gives the code, as `1009: message too big`.
- [websocket.Close] sends the code 1000, a normal close, and waits at most a second for the close of the server and for
  the server to close the TCP connection first (§7.1.1); then it closes by itself.

`Messages` holds 64 messages. While it is full, the client reads nothing more from the network, and TCP makes the server
wait: the [backpressure](glossary.md#backpressure) of a channel of a size. The messages already in `Messages` still come
after [websocket.Close]; those that arrive after it are dropped, as a browser drops them.

Only `ws://` for now: `wss://`, WebSocket over TLS, gives an `Err` that says so. Text messages only: a binary message
received comes as a text, since a text of Cesia is made of bytes, but none can be sent yet. [websocket.Dial] needs the
`net` permission of the host, as [http.Fetch] does: `net=127.0.0.1:9222`, or `net=own` for a server of the program
itself. Each time the client changes, and once a week, the CI plays the cases of Autobahn|Testsuite, the reference suite of RFC 6455, against the client:
all of them but those of binary messages to send and of compression (RFC 7692), which it doesn't do.

Measured on one machine, against one echo server written in Go with gorilla/websocket 1.5.3, as the
[median](glossary.md#median) of 11 runs: a connection opens in 0.54 ms, a message of 100 bytes goes and comes back in
34 µs, and one of 1.4 MB, a page's screenshot in Base64, in 4.7 ms. Go's client, gorilla/websocket, is faster: 0.47 ms,
23 µs and 3.3 ms. The WebSocket of Node 26 takes 55 µs and 6.5 ms, and 56 ms for its first connection, as it loads its
client then. A program reads the client only when it names it: a server of [std/http] starts as it did.

## Live screens: std/live

A *live screen* is a page whose data changes by itself, as others change it, without the page asking again: the unpaid
invoices of a client, a dashboard, a chat. The usual way without it is *polling*: the page asks for the whole list every
few seconds, so a change shows up to that much later, and the server answers every page again even when nothing
changed. [std/live] does it with a [WebSocket](#websocket) per page instead, and in both directions:

- the app gives each page its *shows*: a name, and a channel of [std/fiber] whose messages are an answer and its
  changes. The page gets the answer, then each change, pushed as it comes.
- the page asks the app for *actions*: a name and the values of the page, run by a function of the app, whose reply
  goes back to the page. The page shows the effect of its own action at once, before the reply, and the reply confirms
  it or undoes it: an [optimistic update](glossary.md#optimistic-update).

In both examples below, the app holds its data behind functions of its own: `clientOf(r)`, the client a request comes
from; `unpaid(c)`, the unpaid invoices of a client; `addInvoice(c, a)`, which adds one; and, for the live screen,
`watchUnpaid(c, ended)`, a channel of the answer then of its changes until `ended` closes. With Cepheus, the last is
`cepheus.Watch(1, unpaidOf(c), db, until = ended)?.Changes`: a watch of Cepheus gives exactly these messages.

```cesia norun hide=code
clientOf(r) = 1
unpaid(c) = []
addInvoice(c, a) = result.Ok(1)
watchUnpaid(c, ended) = fiber.Channel()
```

Before, a page that polls:

```cesia norun
app = http.App()
  then http.Get("/unpaid", r -> http.Json(unpaid(clientOf(r))))
  then http.Post("/invoice", r -> http.Json(addInvoice(clientOf(r), http.BodyJson(r)?)))
```
```js
setInterval(async () => draw(await (await fetch("/unpaid")).json()), 2000)   // all again, every 2 s
```

After, a live screen: [live.Route] serves the screens of a path, and the page's side, `live.js`, at the path and
`/live.js`:

```cesia norun
use std/live
screen(s) = [live.Show("unpaid", watchUnpaid(clientOf(s.Request), s.Ended))]
app = http.App() then live.Route("/live", screen, actions = {AddInvoice: (s, a) -> addInvoice(clientOf(s.Request), a)})
```
```js
import { connect } from "/live/live.js"
const live = await connect("/live")
live.show("unpaid", rows => draw(rows))          // at once, then at each change
add.onclick = () => live.act("AddInvoice", {Total: 90},
  {unpaid: rows => [...rows, {Invoice: null, Total: 90}]})   // drawn at once; the reply confirms or undoes it
```

`a then live.Route(pattern, screen)` is `live.Route(pattern, screen, a)`, as for [http.Get]: `then` passes its left side
as the last argument.

### A screen

`screen(s)` runs when a page connects. `s` is `{Request, Ended}`: the HTTP request of the page, with its headers and
cookies, to tell who it is, as a route does; and a channel that closes when the page leaves. It gives a list of
[live.Show], each a name and a channel, or an `Err`, which the page gets as an error. Each message of a show's channel
is, first, the answer, `{Group, Rows}`: its rows at the group `Group`, a number that grows with each change; then each
change, `{Group, Added, Removed}`: the rows that came and the rows that went with that group; or the answer again. A
watch of Cepheus gives exactly these, and `until = s.Ended` ends it with the page. A channel of your own works too:

```cesia allow=net=own
use std/live
use std/websocket
use std/json
use std/net
use std/fiber
defn counter(s)
  ch = fiber.Channel()
  fiber.Send({Group: 0, Rows: [{N: 0}]}, ch)
  fiber.Send({Group: 1, Added: [{N: 1}], Removed: [{N: 0}]}, ch)
  [live.Show("count", ch)]
end
listener = net.Listen(0).Value
fiber.Spawn(() -> http.Serve(http.App() then live.Route("/live", counter), listener = listener))
page = websocket.Dial("ws://127.0.0.1:$(net.Port(listener))/live").Value
websocket.Send(json.Text({Hello: 1}), page) -->
answer = json.Parse(fiber.Receive(page.Messages, timeout = 1).Value).Value[1]
[answer.Show, answer.Group, answer.Rows] -->
change = json.Parse(fiber.Receive(page.Messages, timeout = 1).Value).Value[1]
[change.Group, change.Added, change.Removed] -->
websocket.Close(page) -->
```

The page is `live.js` in a browser; here it is the client of [std/websocket], which shows what goes on the wire: the
page says `{"Hello": 1}`, then each frame of the app is a JSON list of messages, each with `At`, the app's clock in
microseconds when it read the message from its show.

Each screen has a [fiber](fibers.md) of its own, which reads its shows and writes to its page alone: a page that reads
nothing holds no other back. While its page is slow, a screen waits on its connection, and reads nothing more; so the
source of a show never waits for the screen either: it gives each screen a channel of its own, and when one holds too
much, it drops what it holds and sends the answer again. A watch of Cepheus does that by itself, with its `size`
(64 messages unless said otherwise): a page too far behind gets the whole answer again rather than every change it
missed, and the memory of a screen never grows with a slow page.

### Actions

`actions` maps names to functions `(s, args)`, `args` the values the page sent. An action's value goes back to the page
as its reply: the value of an `Ok`, or any value that isn't an `Err`, confirms the action, and an `Err` undoes it. Each
page's actions run one after the other, in the order it asked for them, each in a fiber of its own: a panic in one is
written in [std/log], and the page learns only that the action failed. An action that the screen doesn't have, a page
that sends something else than `live.js` sends, are refused. The values a page sends are the page's: an action checks
them, as a route checks a form.

On the page, `live.act(name, args, effects)` sends the action and gives a `Promise` of its reply. `effects` maps the
names of shows to functions that give the rows with the action's effect: the page draws each show as the app's rows with
the effect of each action not yet answered, in the order they were asked for, again at each change. This is how games
show a player's own moves at once and Replicache a page's own writes: *client-side prediction*, then *reconciliation*
when the server's state arrives. A reply drops the effect: at once on an `Err`; on an `Ok`, on each show that got a
message since the action was asked for, and on the others at their next message, at most 100 ms later, so that the
action's row is drawn neither twice nor not at all, whichever of its change and its reply comes first. While an action
runs, the screen holds the changes of its shows, at most 0.1 s, and sends them with the reply in one frame. A page draws
each show at most once a frame of the display, at `requestAnimationFrame`.

### The page's side

`live.js` is served at the path of the route and `/live.js`, a module of 383 lines with nothing to install:

| | |
|---|---|
| `connect(url, options)` | opens the screen: a `Promise` of it, or a refusal when no screen opens at `url`; `options` are the page's own settings of the connection (below), over the app's |
| `live.show(name, draw)` | `draw(rows)` with the rows of a show, at once if they are there, then at each change |
| `live.act(name, args, effects, base)` | an action: a `Promise` of its reply, its effects drawn at once; kept while the page is away, sent once it is back |
| `live.onStatus(f)` | `f(status)` now and at each change of the connection: `{State, Waiting, Retry, Last, Offline, Error}` |
| `live.onError(f)` | `f(error)` for an error of the screen, as an `Err` of `screen` or a show that ended |
| `live.now()`, `live.again()` | try at once while down; come back after an error that ended the screen, as a sign-in again |
| `live.close()` | closes the screen, and tells the app, which lets it go at once |

### When the connection drops

A break of the connection is no end: a wifi lost, a phone that goes from wifi to 4G with another address, a laptop
asleep, the app restarted or deployed, a proxy that cuts idle connections. For a drop of seconds to minutes the page
comes back by itself and goes on where it stopped, once, as Socket.IO's *connection state recovery* and SignalR's
*stateful reconnect* do; nothing to write, on either side.

- **The page comes back by itself**, after a wait drawn at random between 0 and a bound that doubles at each failure,
  from `ReconnectFirst` (500 ms) to `ReconnectMax` (30 s): *full jitter* (Marc Brooker, "Exponential Backoff And
  Jitter", AWS Architecture Blog, 2015), so that a thousand pages cut together by a restart don't all come back in the
  same instant. It tries at once when the browser says it is online again, and when its tab is shown again.
- **A silent network is a break too**: a router gone or a cable pulled closes nothing, and TCP takes minutes to give
  up. The page pings every `PingEvery` seconds (15), and no frame for `DeadAfter` seconds (30) is a break: the values
  of SignalR's `KeepAliveInterval` and `ServerTimeout`. The browser's `offline` is a break at once.
- **The app keeps the screen**: a page that says `{"Hello": 2}` gets a screen that outlives its connection, kept
  `resume` seconds (120, Socket.IO's `maxDisconnectionDuration`), its shows going on, the frames it sends numbered
  (`{"Seq": n}` first) and kept until the page says it has them (`{"Got": n}`, at most a second later), `buffer` bytes
  at most (1 MiB; SignalR keeps 100,000 bytes). The page comes back with its token and the last frame it has: the app
  sends it every frame after that one, once, and the page goes on. *Nothing missed, nothing twice.*
- **Past that** (the app restarted, another server, too long, too much missed), the page gets a new screen, whose first
  messages are the whole answers: its rows are replaced, its data reloaded, not the page, and `onStatus` says so
  (`Last: "reloaded"`).
- **Actions wait, in order, each with its key.** An action asked while the page is away is kept, in the order asked,
  with a key made when it was asked; one sent when the connection broke is kept too, with its key. Back on the screen
  the app kept, the page sends again only those the screen didn't hear (`Heard`); on a new screen, all of them, each with
  its key: `s.Key` in the action, which an app gives to its handler as an `Idempotency-Key`, so that it runs once
  (Centauri does). At most `OutboxCount` (100) and `OutboxBytes` (1 MiB) wait; past them the next is refused at once;
  one that waited `OutboxWait` seconds (an hour) fails, saying whether it was ever sent.
- **Another account's actions are never sent**: with `who`, the app gives each screen a tag of its account; the page
  stamps each action with it, and drops those of another account when it comes back signed in as someone else; the
  app refuses an action whose tag isn't the screen's.
- **What the page saw goes with its change**: `base`, the values the page saw of what an action changes, reaches it as
  `s.Base`, for the app to refuse a change of a thing that changed meanwhile rather than overwrite it.

```cesia norun hide=code
screen(s) = []
acts = {}
sameAccount(old, new) = true
accountTag(r) = "w"
```
```cesia norun
app = http.App() then live.Route("/live", screen, actions = acts,
  resume = 120, buffer = 1048576,                      (* the screen kept through a break, and its frames *)
  same = (old, new) -> sameAccount(old, new),          (* who may come back to it: by default the same cookies and query *)
  who = s -> accountTag(s.Request),                    (* the tag that stamps the page's actions *)
  client = {PingEvery: 15, DeadAfter: 30, OutboxCount: 100})   (* the page's settings, sent with its screen *)
```
```js
const live = await connect("/live")
live.onStatus(s => line.textContent = s.State === "down" ? `Offline — ${s.Waiting} waiting` : s.State)
```

The wire, version 2 (a page of version 1, `{"Hello": 1}`, gets the screen of before, which ends with its connection):

| from | message | what it says |
|---|---|---|
| page | `{"Hello": 2}`, or `{"Hello": 2, "Token": t, "Got": n}` | a new screen, or the screen `t` again after frame `n` |
| app | `[{"Token": t, "Resumed": r, "Heard": h, "Who": w, "Client": c}]` | not numbered: the screen's token, whether it is the one the page had, the last action it heard |
| app | `[{"Seq": n}, ...]` | a frame, numbered, kept until the page has it |
| page | `{"Got": n}`, `{"Ping": t, "Got": n}` | the frames the page has |
| page | `{"Act": a, "Id": i, "Args": x, "Key": k, "Base": b, "Who": w}` | an action, run once by its `Id` on its screen and by its `Key` at the app |
| page | `{"Bye": 1}` | the page goes away (sent as it closes): the screen ends at once |

A resume is the screen's own: the request of the page that comes back must be the screen's (Route's `same`); a token
of another account or of another query gets a new screen, and the screen of the token goes on.

A page of another origin than the app's gets a `403`, as [http.SameOrigin] decides: no other site opens a screen with the
cookies of its visitors, which a WebSocket would otherwise allow, since a browser doesn't hold it to the
[same-origin rule](glossary.md#same-origin-check) as it does `fetch` (RFC 6455 §10.2).

### What a page's changes take

`live.js` measures how long each change takes from the app to the page: from `At` to its arrival, with the difference
between the two clocks taken from the page's pings, every 30 s, the one of the shortest round trip, as NTP does. Each
minute, a page sends its p50 and p99, the times that half and 99 in 100 of its changes did not exceed, and the app keeps
them in [std/metrics] as two histograms, `live_delay_p50_seconds` and `live_delay_p99_seconds`, which a route shows to
Prometheus with `metrics.Text()`. The count of screens opened is `live_screens_total`.

### What it costs

Measured on one machine of 8 cores, the app on 4 of them and the pages on the 4 others (a load client that opens the
screens, then publishes changes of one row of 48 bytes at a steady rate, each timed from its publication to its
arrival at each page), 21 runs alternated with a hub written by hand on [std/websocket] in the version before: one
fiber that sends each change's text to every connection, with no answer again for a slow page. The median of the
runs' p50, with its 95 % interval:

| screens | changes a second | hub written by hand | std/live | std/live's p99 |
|---|---|---|---|---|
| 1 | 50 | 0.44 ms [0.43, 0.44] | 0.58 ms [0.56, 0.60] | 0.74 ms |
| 100 | 50 | 1.25 ms [1.17, 1.27] | 2.67 ms [2.40, 2.84] | 7.5 ms |
| 1,000 | 50 | 5.7 ms [5.6, 5.9] | 12.3 ms [11.8, 13.3] | 40 ms |
| 10,000 | 5 | 42 ms [42, 44] | 294 ms [285, 318] | 612 ms |

```cesia allow=read,write
screens = [1, 100, 1000, 10000]
delays = plot.Of([plot.Line(screens, [0.44, 1.25, 5.7, 42], label = "hub, p50", dash = "dashed"),
  plot.Line(screens, [0.58, 2.67, 12.3, 294], label = "std/live, p50", color = "#3a5ad9"),
  plot.Line(screens, [0.74, 7.5, 40, 612], label = "std/live, p99", color = "#3a5ad9", dash = "dotted")],
  title = "From a change to each screen: ms, median of 21 runs", x = "screens (log scale)", y = "milliseconds (log scale)",
  xscale = "log", yscale = "log", note = "50 changes a second, 5 at 10,000 screens", size = [640, 380])
plot.Save(delays, "http-live.svg") -->
```

A screen of std/live takes about twice the hub's time. It does more: each screen is a fiber of its own that writes its
page's messages itself, so a page that reads nothing holds no other back, where the hub waits for it.
At 10,000 screens and 50,000 changes a second to send, std/live sends 47,600 a second, the hub 51,200: std/live falls
behind and its times grow during the run. A held screen takes 29.2 KB of memory, the hub's connection 23.2 KB. A
program that doesn't use [std/live] starts as before: 2.92 ms [2.88, 2.97] against 2.90 [2.85, 2.94] for `io.Print(1)`,
21 runs alternated.

## TCP: std/net

Under [std/http] is [std/net], plain TCP: [net.Listen] opens a listener, [net.Accept] waits for a connection, [net.Connect]
opens one, [net.Read] and [net.Write] move text, [net.Close] closes, and [net.Port] tells the port the system chose for
`net.Listen(0)`. Each wait parks its fiber only. An empty text from [net.Read] means that the other side closed:

```cesia allow=net=own
use std/net
server = net.Listen(0).Value
client = net.Connect("127.0.0.1", net.Port(server)).Value
peer = net.Accept(server).Value
net.Write(client, "ping") -->
net.Read(peer) -->
net.Close(client)
net.Read(peer) -->
```

## The client

[http.Fetch] sends a request, a `GET` unless `method` says otherwise, with a `body` and `headers` if you give them. It
gives an `Ok` of the response, with its `Status`, its `Headers` and its `Body`, or an `Err` when the server can't be
reached. A `404` is a response, not an error: look at `Status`. A server that sends nothing for `timeout` seconds, 300
unless you say otherwise, gives an `Err` of the kind `"timeout"`: the time runs between two reads, so a long download
goes on as long as its bytes come. The head of a response holds at most 16 KiB, and `maxBody`, if you give it, bounds
its body in bytes: a server can't fill the memory of the program.

```cesia allow=net
http.Fetch("http://127.0.0.1:1/") -->
```

A program that asks an address it was given, as a server that calls back the address of a partner, must not reach
its own machine or its network for whoever gave it (*server-side request forgery*, SSRF): `peer`, a function of the
address the connection reached, as [net.Peer] gives it, runs once it is open and before any byte is sent, TLS's
included; an `Err` it gives closes the connection, and `Fetch` gives that `Err`. A host given by its name is thus
checked at the very address it was found at: a second lookup, which a server of names could answer otherwise (*DNS
rebinding*), never happens.

```cesia norun
use std/result
mine(address) = if address == "127.0.0.1" or address == "::1" result.Err({Kind: "http", Message: "This address is of this machine."}) else result.Ok(missing) end
http.Fetch("http://localhost:8080/", peer = mine)   (* Err: This address is of this machine. *)
```

### https

For `https`, [std/tls] gives the client its encryption, through OpenSSL. It needs the permission to load it, and to reach the
host:

```cesia norun
(* page.ce *)
use std/http
use std/io
use std/result
use std/tls
api = tls.Open()!
page = http.Fetch("https://example.com/", secure = tls.Client(api))
io.Print(page!.Status)
```

```bash
cesia run --allow net=example.com,ffi=ssl,ffi=crypto page.ce
```

The certificate of the server must be signed by an authority the system trusts, and name the host; `ca`, the path of
a PEM file of authorities, trusts those instead, as a company's own: `tls.Client(api, ca = "/etc/ssl/company.pem")`.

A server serves `https` the same way: `wrap = tls.Server(certificate, key, api)?` given to [http.Serve], with the paths of
its certificate and its key, from a *certificate authority* such as Let's Encrypt. [std/tls] keeps the sockets with
[std/net] and gives OpenSSL only memory buffers, so a handshake parks its fiber, never the whole server.

## HTTP/3

*HTTP/3* (RFC 9114) carries the same requests over *QUIC* (RFC 9000), a transport over UDP instead of TCP. Three things
change for a client far away or on a poor network:

- **The handshake is one round trip, not two.** TCP's handshake then TLS's take two round trips before the first
  request; QUIC's handshake *is* TLS 1.3's (RFC 9001), so the request leaves after one: 200 ms less on a link of
  100 ms each way.
- **A lost packet holds up only its own request.** Over TCP, the bytes of every request of a connection come in one
  order, and a packet lost stops them all until it comes again: *head-of-line blocking*. QUIC carries each request on
  a *stream* of its own, and a loss stops only that stream.
- **It is encrypted to the end**, its packet numbers and acknowledgements too: a box on the way can't read or change
  them.

[std/http3] serves the same application as HTTP/1.1, beside it: give [http.Serve] an `http3`, the listener that
[http3.Server] opens on a UDP port, the TCP port of HTTPS by default as browsers look for it. The routes don't change,
nor the middleware, nor the handlers: a request is the same `{Method, Path, Query, Headers, Body, Peer}`, and a route
that takes its body in pieces (`stream`) gets it in pieces over HTTP/3 too.

```cesia norun
(* site.ce *)
use std/http
use std/http3
use std/quic
use std/result
use std/tls
app = http.App() then http.Get("/", r -> http.Plain("hi"))
h3 = http3.Server("cert.pem", "key.pem", quic.Open()!, port = 8443)!
http.Serve(app, port = 8443, wrap = tls.Server("cert.pem", "key.pem", tls.Open()!)!, http3 = h3)!
```

```bash
cesia run --allow net,ffi=ssl,ffi=crypto site.ce
curl --http3-only https://localhost:8443/
```

![TCP, TLS and HTTP/1.1 against QUIC and HTTP/3: TCP's handshake, then TLS's, then the request, two round trips before it; QUIC's handshake carries TLS's, one round trip; over TCP a packet lost stops the three requests of the connection, over QUIC only the stream it belonged to.](images/http3-stack.svg)

### How a browser finds it

A browser asks over TCP first: it can't know that a server speaks HTTP/3 before it has asked. So every response of TCP
says it, `alt-svc: h3=":8443"; ma=86400` (*Alt-Svc*, RFC 7838): the next requests go over QUIC for a day. Where UDP
doesn't pass, as in some company networks, the browser stays on TCP by itself. A DNS record of type `HTTPS` (RFC 9460)
says it before the first request, `example.com. 3600 IN HTTPS 1 . alpn="h3,http/1.1"`, which saves that first trip
over TCP.

### The client

[http.Fetch] does as a browser does with `http3 = http3.Client(api)`: it remembers the `Alt-Svc` of each origin, asks
over HTTP/3 from then on on one connection kept open, and goes back to TCP at once when QUIC fails, that origin left
alone for 5 minutes; but a request that may have reached the server and that isn't idempotent (RFC 9110, section
9.2.2: any method but GET, HEAD, OPTIONS, PUT and DELETE) gives its error instead of going again over TCP, where a
payment would be paid twice. `peer` checks the address that QUIC reaches too.

```cesia norun
api = tls.Open()!
h3 = http3.Client(quic.Open()!)
first = http.Fetch("https://example.com/", secure = tls.Client(api), http3 = h3)   (* over TCP: it hears Alt-Svc *)
next = http.Fetch("https://example.com/", secure = tls.Client(api), http3 = h3)    (* over HTTP/3 *)
```

A client that comes back to a server it met within the hour skips a round trip, twice. The server gave it a *token*
(NEW_TOKEN, RFC 9000, section 8.1.3), which proves its address, so no Retry; and a *ticket* of TLS, which resumes the
handshake. With `early = true`, [quic.Dial] goes further: *0-RTT* (RFC 9001, section 4.6), the first bytes of its
streams leave with the handshake, before it ends, and the answer comes one round trip sooner. An attacker who saw those
packets could send them again, so each ticket serves once (OpenSSL keeps the tickets it gave and takes each back when it
is used), and a request in 0-RTT that would change something gets `425 Too Early` (RFC 8470), which the client sends
again after the handshake; a GET is answered at once. A server that takes no 0-RTT, as one restarted since, gets the same
bytes again after the handshake, and the program sees nothing of it (`tests/quic/early.ce`).

```cesia norun
conn = quic.Dial("example.com", 443, quic.Open()!, early = true)!   (* at once, with a ticket of before *)
```

### WebTransport

*WebTransport* (draft-ietf-webtrans-http3) gives a page what WebSocket gives, over HTTP/3: a *session* that a page opens
with `new WebTransport(url)`, whose streams go both ways. With `webtransport = true`, the routes of [std/live] take a
session on their own path, and the screen is the same, its frames, its actions and their resume: only the transport
changes. `live.js` and the glue of a page compiled to WebAssembly *race* the two, as browsers race IPv6 and IPv4 (*Happy
Eyeballs*, RFC 8305): they open both, take WebTransport when it is ready first or within 300 ms of the WebSocket, and
close the other. A session that fails marks the origin for 10 minutes, and only WebSocket goes there meanwhile: a page
never waits on a network that drops UDP. A session carries no cookie (the W3C's WebTransport makes its requests without
them), and a screen is often its user's by a cookie: so the page first asks `/live/ticket` (the route's path, then
`/ticket`) with its cookies, and opens its session with `?ticket=`; the screen gets the cookies of that request, once,
within 30 s, and a ticket used, forged or late gets 403. A page asks for WebTransport only when it says so, by
`<meta name="webtransport" content="on">`: a server without it is never asked. A server's certificate that no authority
signed, as one of tests or of a machine of one's own, is trusted by its hash:
`connect(url, {CertificateHashes: [base64 of its SHA-256]})`, for a certificate of 14 days at most, as browsers ask.

### QUIC on ngtcp2

[std/quic] runs on *ngtcp2* (1.26, MIT licence), the QUIC of curl and of Node: a library that does the protocol and
nothing else, its packets, their losses, its *congestion control* (how fast to send as the path allows) and its
*pacing* (the packets of a window spread over the round trip, not sent in one burst). The TLS of its handshake and
the encryption of its packets are OpenSSL's, through OpenSSL's own QUIC TLS API (OpenSSL 3.5 and later), by
`ngtcp2_crypto_ossl`; Cesia keeps the UDP socket, reads and sends its datagrams in batches (`recvmmsg` and `sendmmsg`
where the system has them), and keeps the timers on its own loop: one fiber drives each socket and waits for a
datagram, a call of a stream or the next timer, so no fiber waits on another. ngtcp2 calls back into Cesia for what
happens, bytes read, bytes acknowledged, a stream opened; each callback only tells the fiber, which acts once C has
returned. ngtcp2 reaches Cesia by [std/c], as OpenSSL does, without a line of C: `--allow ffi=ssl` opens it with
OpenSSL.

Cesia spoke OpenSSL's own QUIC before, and changed for what it measured: OpenSSL's congestion control, NewReno alone,
grows its window too slowly when acknowledgements come together, and it has no pacing, no migration, no 0-RTT ([What
it costs](#what-it-costs-1)). The routes, [std/http3] and every function of [std/quic] are the same; a stream has
`Last(bytes)` and `Early` more, `quic.Server` and `quic.Dial` take `congestion`, and `quic.Dial` takes `early`.

| | ngtcp2 1.26 in Cesia | What it means |
|---|---|---|
| Streams, flow control, loss recovery (RFC 9000, RFC 9002) | yes | |
| Congestion control | `congestion = "bbr"` (BBR, version 3 of draft-ietf-ccwg-bbr), `"cubic"` (RFC 9438), `"reno"` (RFC 9002): BBR by default in `http3.Server` and Centauri, by measure | [What it costs](#what-it-costs-1) |
| Pacing, and the size of a packet found by the path (PMTUD, RFC 8899) | yes: up to 1,452 bytes | |
| Retry (RFC 9000, section 8.1), and NEW_TOKEN, which spares it to a client that comes back | yes, on by default | `validate = false` saves a round trip, only for tests |
| Connection migration (section 9): a connection goes on when the client's address changes, wifi to 4G, a NAT that rebinds | yes, the new path validated first; a client that moves takes a new connection id, and the server answers with a new one of the client's | [When the connection drops](#when-the-connection-drops) carries over what a migration can't, a server restarted |
| 0-RTT (RFC 9001, section 4.6), on the server and on the client (`early = true`) | yes, each ticket once; a request in it that would change something gets 425 | |
| Datagrams (RFC 9221) | no | Chrome asks of a WebTransport server that it says it has them; it says so, and none ever comes |
| UDP GSO, ECN | no: both need `sendmsg` with its control data, which no library of Cesia gives | GSO measured in [What it costs](#what-it-costs-1) |

Behind a proxy that takes TLS's early data, as nginx with `ssl_early_data on` or a CDN, a request that would change
something gets `425 Too Early` too, on HTTP/1.1 and HTTP/3: the proxy marks such a request `Early-Data: 1`.

| System | QUIC |
|---|---|
| A release of Cesia, Linux or macOS | its own OpenSSL 3.5.9 and ngtcp2 1.26.0, carried beside its binary: 6.7 MB for libcrypto, 1.2 MB for libssl, 371 KB for libngtcp2, 52 KB for its crypto (Linux x86-64, without symbols) |
| Arch Linux (2026-11) | the system's ngtcp2 1.26, on its OpenSSL 4.1 |
| Ubuntu 22.04, 24.04 without a release | no ngtcp2 for OpenSSL: `quic.Open` gives an Err, and Serve serves TCP alone |
| Windows | not yet: Cesia's loop of sockets doesn't watch those of Windows |

The OpenSSL of a release looks for the system's authorities in `/etc/ssl`, where Debian, Ubuntu, Arch, Alpine, openSUSE
and macOS keep them; [std/tls] and [std/quic] also read the bundle of Fedora and RHEL, kept elsewhere.

### What an attacker tries

Each row is a case of `tests/quic/threats.ce`, measured (two runs, both given), but the last, of `tests/quic/early.ce`.

| Attack | What stops it | Measured |
|---|---|---|
| Amplification: packets in the name of another address, for the server to flood it (RFC 9000, section 8) | at most 3 times what came from an address before it proved it owns it (ngtcp2 counts); Retry first | 6 Initials of 1,200 bytes in 3 s: 5,633 and 7,483 bytes out without Retry (0.78 and 1.04 times); 870 with it (0.12 times) |
| A flood of handshakes | Retry keeps no state for an address not yet proved; 1,000 handshakes at once at most, one more dropped | 2,000 Initials (2.4 MB) from 2,000 ports: Retries back, 204 and 215 KB (0.09 times); 7 MB more memory, a real client served at once |
| Following a client by its connection ids | the server's ids are 16 random bytes, new for each connection, and spare ones go to the client for its new paths | 5 connections, 5 ids of 16 random bytes |
| A packet of a connection replayed from another address, to move it there | a packet seen before is dropped before any path changes; a new path is validated (PATH_CHALLENGE) before the server sends more than 3 times what came from it | 39 and 1,444 bytes sent from a new port: nothing back, the connection goes on |
| A NAT that gives the client another address in the middle of a connection | migration: the new path validated, the connection goes on | the next two requests answered 200 from the new address |
| 0-RTT replayed: the first flight of a client, sent again by an attacker once its connection ended | each ticket serves once: OpenSSL's server keeps the tickets it gave and takes each back at its use | 7 and 9 datagrams sent again (5.3 and 6.7 KB): a handshake back (3,649 bytes, within 3 times), the request in them not served again |
| QPACK's table filled to take the memory (RFC 9204, section 2.2.3) | the table is 0 bytes: no insertion, no reference to it | an insertion or a reference ends the connection; a head of 20 KiB gets 431 before any Huffman |
| Streams by the thousand | 100 at once each way (MAX_STREAMS), one more given as one ends; each head within the timeout | 1,000 at once: all 1,000 answered; a head never ended dropped after the timeout |
| A request in 0-RTT that would change something, a payment | `425 Too Early` (RFC 8470); a GET is answered | a POST in 0-RTT: 425; the same after the handshake: 200 |

### What it costs

Measured with `bench/http3` (`setup.sh` builds what it needs; `stacks.sh`, `rps.sh`, `migrate.sh`, `memory.sh`,
`download.sh` and `startup.sh` measure): one machine of 4 physical cores, each measure pinned to 2 of them, the server
on one and the client on the other, while another measure may run on the 2 others; every link in a network namespace of
its own where `netem` adds a path's delay and losses. Each number is the median of the rounds, then [the least, the
most]; 21 rounds, the cases in another order each round, and Mann-Whitney's test between two cases. The giants: quic-go
0.66, Caddy 2 (on quic-go), nginx 1.27 with HTTP/3, and ngtcp2 1.26's own example server. Cesia's server validates
addresses (Retry), one round trip more on each new connection that the others don't make; the clients of the measures
are always new.

![A download of 1 MB on a new connection over Cesia's HTTP/3 on ngtcp2 with each congestion control, beside Cesia on OpenSSL's QUIC as it was and quic-go: on a clean link 26, 24 and 24 ms against 17 and 8; over 25 ms each way and 1 % lost, BBR 0.54 s, CUBIC 1.13 s, Reno 1.81 s, OpenSSL's QUIC 4.21 s, quic-go 1.59 s; through a bottleneck of 20 Mbit/s, BBR 0.82 s, CUBIC 0.98 s, Reno 2.44 s, OpenSSL's QUIC 3.45 s, quic-go 1.77 s.](images/http3-congestion.svg)

**Over a link that loses packets, BBR wins, and by far.** A download of 1 MB on a new connection, 25 ms each way and
1 % lost (`stacks.sh d25l1`, 21 rounds, the load average of the machine 4.3 [3.1, 7.2]):

| 1 MB, 25 ms each way, 1 % lost | median | [least, most] |
|---|---|---|
| Cesia, HTTP/3 on ngtcp2, BBR (the default) | 0.54 s | [0.51, 0.59] |
| Cesia, HTTP/3 on ngtcp2, CUBIC | 1.13 s | [0.49, 3.13] |
| Cesia, HTTP/3 on ngtcp2, Reno | 1.81 s | [0.59, 3.37] |
| Cesia before, HTTP/3 on OpenSSL's QUIC | 4.21 s | [0.82, 6.17] |
| quic-go, HTTP/3 | 1.59 s | [0.39, 2.79] |
| ngtcp2's example server, BBR | 0.47 s | [0.42, 0.62] |
| Cesia, HTTP/1.1 over TCP (Linux's CUBIC) | 2.31 s | [0.92, 3.96] |

BBR takes 0.13 times the time of OpenSSL's QUIC (p = 2.9e-8), 0.34 times quic-go's (p = 5e-6) and 0.23 times TCP's (p =
2.9e-8); CUBIC 0.47 times BBR's speed (p = 3.1e-6). BBR (version 3, draft-ietf-ccwg-bbr) measures the path, its rate and
its round trip, and doesn't take a loss that comes alone for congestion; CUBIC and Reno halve or cut their window at
each loss, and their spread says it: from 0.49 to 3.13 s for CUBIC, as the losses fall early or late. Cesia's BBR is
1.14 times the time of ngtcp2's own server (p = 7.7e-5): the round trip of its Retry, 50 ms of 535.

![A download of 1 MB over 25 ms each way and 1 % lost, 21 rounds: Cesia over HTTP/3 on ngtcp2 with BBR 0.54 s, with CUBIC 1.13 s, with Reno 1.81 s, Cesia on OpenSSL's QUIC 4.21 s, quic-go 1.59 s, ngtcp2's example with CUBIC 1.67 s and with BBR 0.47 s, Cesia over TCP 2.31 s.](images/http3-lossy.svg)

A real path has a *bottleneck*, its slowest link, which spaces the packets: through 20 Mbit/s (`stacks.sh d25l1r20`, the
same 25 ms and 1 %, load average 3.9 [2.2, 5.6]), BBR takes 0.82 s [0.79, 0.95], CUBIC 0.98 s (BBR 0.84 times, p =
0.0031), Reno 2.44 s, OpenSSL's QUIC 3.45 s, quic-go 1.77 s, TCP 1.84 s: BBR 0.24 times OpenSSL's QUIC, 0.47 times
quic-go, 0.45 times TCP (p below 1e-5 for all three).

![A download of 1 MB over 25 ms each way, 1 % lost and 20 Mbit/s at most, 21 rounds: Cesia over HTTP/3 on ngtcp2 with BBR 0.82 s, with CUBIC 0.98 s, with Reno 2.44 s, Cesia on OpenSSL's QUIC 3.45 s, quic-go 1.77 s, ngtcp2's example with BBR 0.79 s, Cesia over TCP 1.84 s.](images/http3-bottleneck.svg)

Where BBR loses: nowhere in these measures, but on a clean link, where the three are the same within the noise (24 to 26
ms); BBR is known to take more than its share beside CUBIC flows when a bottleneck's buffer is shallow (version 3 makes
it less so: it now backs off when more than 2 % of its packets are lost), which a machine alone can't measure. So BBR is
the default, and CUBIC and Reno stay a setting.

**What OpenSSL's QUIC did wrong**: one burst each round trip, then nothing until its acknowledgements came back, a window
of 4 to 12 packets of 1,200 bytes, never more: its NewReno counted an acknowledged packet only while the bytes in flight
stayed within 3 packets of the window, and the acknowledgements of one burst come together, so that only the first three
of each round trip counted (`cc_newreno.c`, `newreno_on_data_acked`). The same NewReno in ngtcp2 decides at the sending of
each packet whether the window was full, and paces: 1.81 s against 4.21. The client's log of then:

![What the client receives each 50 ms (one round trip) of a lossy download, before ngtcp2: quic-go up to 70 packets, spread over the round trip; OpenSSL's QUIC alone and Cesia on it a burst of 4 to 12 packets, then nothing for a round trip, over 4 to 5 seconds.](images/http3-flights.svg)

**On a clean link, the giants win, and HTTP/3 costs more than HTTP/1.1 to all.** A request costs Cesia more over QUIC
than over TCP: QUIC encrypts and acknowledges each packet in user space, where TCP leaves this to the kernel, and Cesia
does the bookkeeping of ngtcp2's events in Cesia, where OpenSSL's QUIC did its timers and acknowledgements in C:

| clean link | Cesia HTTP/1.1 | Cesia HTTP/3 on ngtcp2 | Cesia before, OpenSSL's QUIC | quic-go, Caddy, nginx: HTTP/3 | their HTTP/1.1 |
|---|---|---|---|---|---|
| requests a second (GET /, 16 connections, server on 1 core, 21 rounds) | 8,074 [1,923, 16,375] | 2,291 [653, 3,494] | 2,930 [1,171, 6,114] | 4,858 (quic-go), 5,221 (Caddy), 7,229 (nginx) | 11,993 (quic-go), 11,812 (nginx) |
| a download of 1 MB on a new connection | 16 ms [13, 142] | 26 ms [21, 79] (BBR), 24 (CUBIC) | 17 ms [14, 48] | quic-go 8 ms, ngtcp2's example 6 to 7 | |
| memory of an idle connection (200 of them) | 119 KB | 73 KB [68, 73] | 93 KB | quic-go 57, nginx 99 KB | quic-go 25, nginx 23 KB |

Here Cesia is slower than before: by round, its HTTP/3 serves 0.73 times the requests of OpenSSL's QUIC [0.33, 1.58], and 0.28 times its own HTTP/1.1 (the machine was busy, its load average 7.6 [2.7, 26], hence the wide bounds). A small request is a few packets, and each packet costs ngtcp2's calls and their events: the work is per packet, and on a clean link nothing hides it. A download on a clean link is bound by the processor too: 1.55 times OpenSSL's QUIC (p = 4.4e-5, 21 rounds,
load average 2.2). This version paced its bursts a millisecond apart, the step of the loop of sockets; the timer of a
burst sooner than that no longer waits now, and the same measure, on a machine whose load average was 14.8, gives 1.26
times OpenSSL's QUIC, p = 0.35: no difference that this machine can tell. A connection's memory is less than over
OpenSSL's QUIC (73 KB against 93) and than over Cesia's TCP (119 KB).

UDP *GSO* (generic segmentation offload: the kernel cuts one large write into packets) is not in Cesia's QUIC: it needs
`sendmsg` and its control data, which no library of Cesia gives. What it would bring, measured with ngtcp2's own server
on a clean link, with and without it (`download.sh clean`, 7 rounds): 10 MB in 23.8 ms against 32.0 (1.34 times
faster), 1 MB in 7.9 ms against 6.3, none. In Cesia, whose cost is its bookkeeping rather than its calls to the system,
it would bring less.

When the client's address changes in the middle of a download of 10 MB (`migrate.sh`: quic-go's client moves its
connection to a new socket, or opens a new connection and asks for the rest), Cesia's server keeps the connection now:

| address change after 2 MB | to the next byte, clean link | 25 ms each way, 1 % lost |
|---|---|---|
| quic-go, migration | 1.3 ms [0.4, 20] | 102 ms [101, 104] |
| Cesia on ngtcp2, migration (every round migrated) | 46 ms [32, 105] | 155 ms [152, 361] |
| Cesia on ngtcp2, a new connection over QUIC | 60 ms [44, 1,068] | 222 ms [209, 536] |
| Cesia before, a new connection over OpenSSL's QUIC | 24 ms [15, 168] | 183 ms [171, 255] |
| Cesia, a new connection over TCP | 32 ms [15, 111] | 231 ms [217, 234] |

(The clean rows, 21 rounds, ran while the machine was busy, load average 12; the lossy ones, 7 rounds, at 4.1.)
Cesia's migration waits, on the server's side, for the first packet of the client from its new address that isn't a
probe (RFC 9000, section 9.3), then checks that address before it sends there more than three times what came from it,
one round trip: about one round trip more than quic-go's, still less than a new connection.

Start-up: a program that loads [std/http3] and calls `quic.Open()` starts in 9.0 ms [8.4, 13.4] against 4.3 ms for one
that loads [std/http] alone (21 runs each, alternated): 4.7 ms for ngtcp2's library, its 115 functions bound, 12 more found by address, and its
callbacks made, once; OpenSSL's QUIC took 2.4 (6.7 ms against 4.3). A program that serves HTTP/1.1 alone pays nothing.

The TCP path doesn't pay for this: [std/http]'s TCP is the same code as before; a client of HTTPS reads one file more
when it makes its context (Fedora's bundle of authorities, missing elsewhere).

So HTTP/3 is a setting, never a replacement: on for an application whose users are on phones, trains and poor
networks, and for large downloads over them, where it now goes several times faster than TCP; off where requests are
small, the link clean and the processor what counts (see [References](references.md#the-server-and-the-network) for
RFC 9002, RFC 9438, BBR and ngtcp2).

## Further reading

RFC 9110 and RFC 9112 for HTTP, RFC 9000, RFC 9001, RFC 9114 and RFC 9204 for QUIC and HTTP/3, draft-ietf-webtrans-http3
for WebTransport, RFC 6455 for WebSocket, RFC 9846 for TLS 1.3, the Prometheus exposition format, and
the Linux pages of `epoll`: see [References](references.md#the-server-and-the-network).

## Next

Your programs serve and ask the web. The next chapter, [Cryptography](crypto.md), keeps their secrets; then
[Fibers](fibers.md) runs many things at once: a server's requests, a crawler's pages, a slow task beside a fast one.
