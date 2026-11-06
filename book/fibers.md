# Fibers

In this chapter you do several things at once: fetch pages while others load, serve many clients, keep a slow task from
holding up a fast one. A fiber is a function that runs beside the rest of the program. Fibers are light: a program can run
thousands of them.

## Spawn and Wait

[Spawn] starts a function in a new fiber, and gives a task at once. [Wait] waits for the task to end, and gives an `Ok` of
what the function gave:

```cesia
use std/sys
defn slow(name, seconds)
  sys.Sleep(seconds)
  "$name is ready"
end

start = sys.Now()
bread = Spawn(() -> slow("bread", 0.2))
cake = Spawn(() -> slow("cake", 0.1))
Wait(bread) -->
Wait(cake) -->
sys.Now() - start < 0.3 -->
```

The two waits overlap: the whole takes the time of the longest, `0.2` seconds, not their sum, `0.3`.

## What waits

A fiber that waits lets the others run: [sys.Sleep], a read from the network, a call to [Wait] or [Receive], a database that
is busy. A long computation doesn't hold the others up either: Cesia moves between fibers as they run. So a server keeps
answering its other clients while one of them asks for a large report.

```cesia
busy = Spawn(defn ()
  n = 0
  for k in 1..2000000
    n += k
  end
  n
end)
sys.Sleep(0.001)
"the program still runs" -->
Wait(busy) -->
```

## Pmap

[Pmap] is [Map] with one fiber per element. It suits a function that waits, as one that fetches a page for each address:

```cesia
start = sys.Now()
Pmap(name -> slow(name, 0.1), ["bread", "cake", "tart"]) -->
sys.Now() - start < 0.3 -->
```

Three waits of `0.1` seconds take about `0.1` seconds together, not `0.3`. The results come in the order of the list,
whatever the order in which the fibers end.

## A panic in a fiber

A bug in a fiber stops that fiber only. Its message is printed, and [Wait] gives an `Err` with the message, so the program
can go on, log it, or stop:

```cesia
broken = Spawn(() -> Div(1, 0))
Wait(broken).Error.Message -->
```

A server works this way: a request whose handler has a bug gets a `500`, and the other requests go on.

## Channels

A channel carries values from one fiber to another, in the order they were sent. [Channel] makes one, [Send] puts a value in
it and never waits, and [Receive] takes the oldest, waiting for one if it is empty:

```cesia
orders = Channel()
baker = Spawn(defn ()
  for product in ["bread", "cake", "tart"]
    Send(product, orders)
  end
  Send(missing, orders)
end)

made = []
next = Unwrap(Receive(orders))
while IsSome(next)
  made = Append(next, made)
  next = Unwrap(Receive(orders))
end
made -->
```

Here `missing` tells that nothing more will come. [Receive] can also wait for a time at most, and gives an `Err` of the kind
`"timeout"` then:

```cesia
Receive(Channel(), timeout = 0.05) -->
```

Values in Cesia never change in place, so two fibers can't break a value they share: a fiber that changes a list makes a new
one, and the other fiber keeps what it had. A channel is the way to pass the new one on.

## Next

Your programs do many things at once. The next chapter, [SQLite](sqlite.md), keeps their data in a database.
