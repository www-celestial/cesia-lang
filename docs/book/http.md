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

A [middleware](glossary.md#middleware) sits in front of the routes: it sees each request, and the response that comes back. [http.Logger] prints one line
per request. [http.Wrap] puts a middleware in front of an application:

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
too, as the chapter [Files](files.md#programs-that-keep-running) says.

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
Linux or macOS: on Windows, a program serves on one core.

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

## Next

Your programs serve and ask the web. The next chapter, [Fibers](fibers.md), runs many things at once: a server's requests, a
crawler's pages, a slow task beside a fast one.
