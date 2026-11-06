# HTTP

In this chapter you write a web server: routes, parameters in the path, JSON in and out, and a log of each request. You test
it without the network, then serve it and ask it from the same program. [std/web] builds the application, on [std/http],
which also has the client.

## An application

[web.App] starts an application with no route. Each [route](glossary.md#route) adds one: a method, a path, and a
[handler](glossary.md#handler), the function of the request that gives the response. [web.Plain] makes a plain text response, and [web.SendJson] a JSON one:

```cesia
use std/web
app = web.App()
  then web.Get("/", r -> web.Plain("Welcome"))
  then web.Get("/hello/:name", r -> web.Plain("Hello, $(r.Params.name)!"))
  then web.Get("/stock", r -> web.SendJson({bread: 40, cake: 6}))
```

### Words in the path

A part of a path that starts with `:` takes any word, and the handler finds it in `r.Params`. The application is a value: each
route gives a new one, and [then] chains them.

## Trying it without the network

[web.Handler] gives the function that the server calls for each request. You can call it yourself, with a request as a
dictionary, which is how you test a server:

```cesia
handle = web.Handler(app)
ask(path) = handle({Method: "GET", Path: path, Query: "", Headers: [], Body: ""})
ask("/hello/Ana").Body -->
ask("/stock").Status -->
Print(ask("/stock").Body)
ask("/nowhere").Status -->
```

A path that no route takes gets a `404`.

## JSON in

[web.BodyJson] reads the body of a request as JSON. With `From`, the body is checked before your code uses it, and a wrong one
gets a `400` that says what is wrong:

```cesia
struct Purchase
  Product Text
  Units Int
end

defn addPurchase(request)
  match web.BodyJson(request) then AndThen(Purchase.From)
    Ok(order) -> web.SendJson({Product: order.Product, Units: order.Units, Total: order.Units * 1.25}, status = 201)
    Err(e) -> web.SendJson({Error: e.Message}, status = 400)
  end
end

shop = app then web.Post("/orders", addPurchase)
post(body) = web.Handler(shop)({Method: "POST", Path: "/orders", Query: "", Headers: [], Body: body})
Print(post("{\"Product\": \"bread\", \"Units\": 4}").Body)
Print(post("{\"Product\": \"bread\", \"Units\": \"four\"}").Body)
Print(post("not json").Body)
```

## Middleware

A [middleware](glossary.md#middleware) sits in front of the routes: it sees each request, and the response that comes back. [web.Logger] prints one line
per request. [web.Wrap] puts a middleware in front of an application:

```cesia
logged = web.Wrap(web.Logger, shop)
web.Handler(logged)({Method: "GET", Path: "/stock", Query: "", Headers: [], Body: ""}).Status -->
```

### A middleware of your own

A middleware of your own is a function of `next` and the request, which calls `next(request)` to go on. `servedBy` adds a
header to each response, which says what served it:

```cesia
defn servedBy(next, request)
  response = next(request)
  web.WithHeader("x-served-by", "cesia", response)
end
web.Handler(web.Wrap(servedBy, shop))({Method: "GET", Path: "/", Query: "", Headers: [], Body: ""}).Headers -->
```

## Serving

[web.Serve] serves an application until the program gets a stop signal, as Ctrl-C. It listens on port 8080 unless `port`
says otherwise, and on `127.0.0.1`, this machine only, unless `host` does. It needs the permission to listen on its port.
Here is a small `shop.ce`:

```cesia norun
(* shop.ce: one route, served on port 8080 *)
use std/web

hello = web.App()
  then web.Get("/hello/:name", r -> web.Plain("Hello, $(r.Params.name)!"))
web.Serve(web.Wrap(web.Logger, hello))
```

Run it, and ask it from another terminal:

```bash
cesia run --allow net=:8080 shop.ce
curl localhost:8080/hello/Ana
```

### Serving and asking in one program

The block below serves the shop on a port and asks it with the client, in one program. [Spawn] runs the server beside the
rest of the program, as the chapter [Fibers](fibers.md) explains, and [sys.Sleep] lets it start:

```cesia allow=net,net=:18761
use std/sys
use std/http
Spawn(() -> web.Serve(logged, port = 18761))
sys.Sleep(0)
r = http.Get("http://127.0.0.1:18761/hello/Bo")
r.Value.Status -->
r.Value.Body -->
sent = http.Post("http://127.0.0.1:18761/orders", "{\"Product\": \"cake\", \"Units\": 2}")
Print(sent.Value.Body)
```

The program ends when its last line is done, and the server with it.

## The client

[http.Get] and [http.Post] send a request, and give an `Ok` of the response, with its `Status`, its `Headers` and its
`Body`, or an `Err` when the server can't be reached. A `404` is a response, not an error: look at `Status`.

```cesia allow=net
http.Get("http://127.0.0.1:1/") -->
```

### https

For `https`, [std/tls] gives the client its encryption, through OpenSSL. It needs the permission to load it, and to reach the
host:

```cesia norun
use std/tls
api = Unwrap(tls.Open())
page = http.Get("https://example.com/", secure = tls.Client(api))
```

```bash
cesia run --allow net=example.com,ffi=ssl,ffi=crypto page.ce
```

## Next

Your programs serve and ask the web. The next chapter, [Fibers](fibers.md), runs many things at once: a server's requests, a
crawler's pages, a slow task beside a fast one.
