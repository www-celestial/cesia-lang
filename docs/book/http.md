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

## Trying it without the network

[http.Handler] gives the function that the server calls for each request. You can call it yourself, with a request as a
dictionary, which is how you test a server:

```cesia
use std/io
handle = http.Handler(app)
ask(path) = handle({Method: "GET", Path: path, Query: "", Headers: [], Body: ""})
ask("/hello/Ana").Body -->
ask("/stock").Status -->
io.Print(ask("/stock").Body)
ask("/nowhere").Status -->
```

A path that no route takes gets a `404`.

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
cesia run --workers cores --allow net=0.0.0.0:8080 shop.ce
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
[websocket.Accept], a silent connection closed after [websocket.DefaultIdle] seconds, and a frame larger than
[websocket.MaxFrame] refused:

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
  bytes are read (§10.4). [websocket.Close] then gives the code, as `1009: message too big`.
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

`live.js` is served at the path of the route and `/live.js`, a module of 211 lines with nothing to install:

| | |
|---|---|
| `connect(url)` | opens the screen: a `Promise` of it, or a refusal when no screen opens at `url` |
| `live.show(name, draw)` | `draw(rows)` with the rows of a show, at once if they are there, then at each change |
| `live.act(name, args, effects)` | an action: a `Promise` of its reply, its effects drawn at once |
| `live.onError(f)` | `f(error)` for an error of the screen, as an `Err` of `screen` or a show that ended |
| `live.close()` | closes the screen |

When the connection breaks, the page connects again by itself, after 0.25 s, then twice as long each time, up to 8 s;
the new screen starts with the answers. An action asked before the break and not yet answered gets an error that says
so: it may have run or not, and the new answers show which.

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
reached. A `404` is a response, not an error: look at `Status`.

```cesia allow=net
http.Fetch("http://127.0.0.1:1/") -->
```

### https

For `https`, [std/tls] gives the client its encryption, through OpenSSL. It needs the permission to load it, and to reach the
host:

```cesia norun
use std/tls
use std/result
api = result.Unwrap(tls.Open())
page = http.Fetch("https://example.com/", secure = tls.Client(api))
```

```bash
cesia run --allow net=example.com,ffi=ssl,ffi=crypto page.ce
```

A server serves `https` the same way: `wrap = tls.Server(certificate, key, api)?` given to [http.Serve], with the paths of
its certificate and its key, from a *certificate authority* such as Let's Encrypt. [std/tls] keeps the sockets with
[std/net] and gives OpenSSL only memory buffers, so a handshake parks its fiber, never the whole server.

## Further reading

RFC 9110 and RFC 9112 for HTTP, RFC 6455 for WebSocket, RFC 9846 for TLS 1.3, the Prometheus exposition format, and
the Linux pages of `epoll`: see [References](references.md#the-server-and-the-network).

## Next

Your programs serve and ask the web. The next chapter, [Cryptography](crypto.md), keeps their secrets; then
[Fibers](fibers.md) runs many things at once: a server's requests, a crawler's pages, a slow task beside a fast one.
