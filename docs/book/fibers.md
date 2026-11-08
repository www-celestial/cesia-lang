# Fibers

In this chapter you do several things at once: fetch pages while others load, serve many clients, keep a slow task from
holding up a fast one. A [fiber](glossary.md#fiber) is a function that runs beside the rest of the program, with its own
stack: what Go calls a goroutine, Java 21 a virtual thread, and others a *green thread*, a thread that the language runs
rather than the system. Fibers are light, about 2.5 KB each: a program can run a hundred thousand of them. They take turns
on one core: they run [concurrently](glossary.md#concurrency-and-parallelism), not in parallel, and the wait of one is
time for the others. Unlike `async` in Python or JavaScript, nothing is marked: any function can wait, and the code
that calls it doesn't change.

## Spawn and Wait

[fiber.Spawn] starts a function in a new fiber, and gives a task at once. [fiber.Wait] waits for the task to end, and gives an `Ok` of
what the function gave:

```cesia
use std/sys
use std/fiber
defn slow(name, seconds)
  sys.Sleep(seconds)
  "$name is ready"
end

start = sys.Now()
bread = fiber.Spawn(() -> slow("bread", 0.2))
cake = fiber.Spawn(() -> slow("cake", 0.1))
fiber.Wait(bread) -->
fiber.Wait(cake) -->
sys.Now() - start < 0.3 --> true
```

The two waits overlap: the whole takes the time of the longest, `0.2` seconds, not their sum, `0.3`.

## What waits

A fiber that waits lets the others run: [sys.Sleep], a read from the network, a call to [fiber.Wait], [fiber.Receive] or
[fiber.Select], a [fiber.Send] on a full channel, a database that is busy.

### A long computation

A long computation doesn't hold the others up either: every million steps, a call or a turn of a loop each, a fiber that
computes gives way to the others that are ready, which is called [preemptive scheduling](glossary.md#preemptive-scheduling):
nobody writes a yield, as Erlang counts its reductions. So a server keeps answering its other clients while one of them
asks for a large report. It is not the preemption of a system thread, which a timer can stop anywhere: a function of
`std/` written in OCaml, as a [list.Sort] of a million elements, runs to its end before another fiber gets its turn. The fiber here is a function without a name on several lines, from `defn ()` to `end`, as the chapter
[Functions](functions.md) showed:

```cesia
busy = fiber.Spawn(defn ()
  n = 0
  for k in 1..2000000
    n += k
  end
  n
end)
sys.Sleep(0.001)
"the program still runs" -->
fiber.Wait(busy) -->
```

## Waiting at most, and stopping a fiber

[fiber.Wait] can wait for a time at most: past it, it gives an `Err` of kind `"timeout"`, and the task runs on.
[fiber.Cancel] stops it: the fiber stops at its next wait, as a [sys.Sleep], a [fiber.Receive] or a call to the network, or
at the next checkpoint of a long computation, where it lets the others run. Then [fiber.Wait] gives an `Err` of kind
`"cancelled"`, which tells the file and the line where the fiber was. A server gives each request a time this way:

```cesia
stuck = fiber.Spawn(defn ()
  n = 0
  while true
    n += 1
  end
end)
fiber.Wait(stuck, timeout = 0.05).Error.Kind --> "timeout"
fiber.Cancel(stuck)
fiber.Wait(stuck).Error.Kind --> "cancelled"
```

The loop never waits, and it stops all the same. What the fiber had to do after its wait, it doesn't do, so code that
must finish runs in a fiber of its own, which nothing else can stop: a transaction of [sql.Transaction] does, and ends
as its function says even when the fiber that began it is stopped.

## Pmap

[fiber.Pmap] is [list.Map] with one fiber per element. It suits a function that waits, as one that fetches a page for each address:

```cesia
start = sys.Now()
fiber.Pmap(name -> slow(name, 0.1), ["bread", "cake", "tart"]) -->
sys.Now() - start < 0.3 --> true
```

Three waits of `0.1` seconds take about `0.1` seconds together, not `0.3`. The results come in the order of the list,
whatever the order in which the fibers end.

## A panic in a fiber

A bug in a fiber stops that fiber only. Its message is printed, and [fiber.Wait] gives an `Err` with the message, so the program
can go on, log it, or stop:

```cesia
use std/math
broken = fiber.Spawn(() -> math.Div(1, 0))
fiber.Wait(broken).Error.Message -->
```

A server works this way: a request whose handler has a bug gets a `500`, and the other requests go on.

## Channels

A channel carries values from one fiber to another, in the order they were sent: this is
[message passing](glossary.md#message-passing). [fiber.Channel] makes one, [fiber.Send] puts a value in it, and
[fiber.Receive] takes the oldest, waiting for one if it is empty. [fiber.Close] tells that nothing more will come, and a
`for` loop over a channel takes its values as they come, until it is closed:

```cesia
use std/list
use std/result
orders = fiber.Channel()
baker = fiber.Spawn(defn ()
  for product in ["bread", "cake", "tart"]
    fiber.Send(product, orders)
  end
  fiber.Close(orders)
end)

made = []
for product in orders
  made = list.Append(product, made)
end
made -->
```

The values sent before [fiber.Close] still come; a [fiber.Send] after it is a bug, and stops its fiber. The `for` loop is
[syntax sugar](glossary.md#syntax-sugar) for a loop of [fiber.Receive], which gives an `Err` of kind `"closed"` once the
channel is closed and empty:

```cesia
orders = fiber.Channel()
fiber.Spawn(defn ()
  fiber.Send("pie", orders)
  fiber.Close(orders)
end)

made = []
got = fiber.Receive(orders)
while result.IsOk(got)
  made = list.Append(got.Value, made)
  got = fiber.Receive(orders)
end
made -->
got.Error.Kind --> "closed"
```

### A time limit

[fiber.Receive] can also wait for a time at most, and gives an `Err` of the kind
`"timeout"` then:

```cesia
fiber.Receive(fiber.Channel(), timeout = 0.05) -->
```

### Several channels at once

[fiber.Select] waits on a list of channels and receives from the first one that has a value, as Go's `select`. It gives
an `Ok` of the `Channel` and the `Value`, an `Err` of kind `"closed"` for a channel closed and empty, or of kind
`"timeout"`. The channels are tried in the order of the list, so a worker can let a stop go before its work:

```cesia
jobs = fiber.Channel()
stop = fiber.Channel()
worker = fiber.Spawn(defn ()
  done = []
  got = fiber.Select([stop, jobs], timeout = 1)
  while result.IsOk(got)
    done = list.Append(got.Value.Value, done)
    got = fiber.Select([stop, jobs], timeout = 1)
  end
  done
end)
fiber.Send("wash", jobs)
fiber.Send("dry", jobs)
sys.Sleep(0)
fiber.Close(stop)
fiber.Wait(worker) -->
```

The worker took the two jobs as they came, then stopped when `stop` was closed: a closed channel has no value, so
[fiber.Select] gives its `Err` at once.

### A channel of a size

A channel holds as many values as are sent to it, and a fast sender can fill the memory before a slow receiver catches
up. With a size, [fiber.Channel] holds that many values at most, and [fiber.Send] waits while it is full: the sender goes at
the pace of its receiver. This is called [backpressure](glossary.md#backpressure):

```cesia
tray = fiber.Channel(size = 1)
start = sys.Now()
fiber.Spawn(defn ()
  for k in 1..3
    sys.Sleep(0.1)
    result.Unwrap(fiber.Receive(tray))
  end
end)
for k in 1..3
  fiber.Send(k, tray)
end
sys.Now() - start > 0.15 --> true
```

The first value fits; the second waits until the receiver takes the first, after `0.1` seconds, and the third until it
takes the second. A size of `0` holds none: [fiber.Send] waits for a receiver to take its value, so the two fibers meet.

### The stop signal

[sys.Stops] gives a channel that the first stop signal closes: TERM, INT or HUP. A fiber that waits on it hears of the
stop at once, and ends its work itself, as the requests of a server do; [fiber.Close] closes a channel of your own the
same way:

```cesia norun
use std/io
stops = sys.Stops()
defn worker(jobs)
  while true
    if fiber.Receive(stops, timeout = 0).Error.Kind == "closed"
      return "stopped"
    end
    match fiber.Receive(jobs, timeout = 1)
      result.Ok(job) -> io.Print("done", job)
      else -> missing
    end
  end
end
```

### When every fiber waits

When every fiber waits for another, and none waits for the clock, the network or a signal, nothing can ever wake them: a
*deadlock*. Cesia stops the program at once, with the line of the wait, rather than hang:

```cesia fails
lonely = fiber.Channel()
fiber.Receive(lonely)
```

### Shared values

Values in Cesia never change in place, they are [immutable](glossary.md#immutability), so two fibers can't break a value they share: a fiber that changes a list makes a new
one, and the other fiber keeps what it had. A channel is the way to pass the new one on. So there are no *data races*, two
threads writing one memory at the same time, and no locks to take: a fiber runs alone between two of its waits, on one
core.

## Further reading

- C. A. R. Hoare, *Communicating Sequential Processes*, 1978: the channels, and the meeting of a send and a receive that a
  channel of size 0 is.
- The Go Programming Language Specification: buffered channels, `close` and `select`, which Cesia follows, but for
  [fiber.Select], which tries its channels in the order of its list where Go picks at random among the ready ones.
- KC Sivaramakrishnan and others, *Retrofitting Effect Handlers onto OCaml*, 2021: what each fiber is inside.
- Joe Armstrong, *A History of Erlang*, 2007: processes switched by counted steps.

Each with its link in [References](references.md#fibers-and-channels); [How Cesia works](internals.md#fibers-and-the-scheduler)
shows the scheduler, and [Speed](speed.md#fibers-beside-goroutines-async-and-virtual-threads) fibers beside goroutines,
`async` and virtual threads.

## Next

Your programs do many things at once. The next chapter, [SQLite](sqlite.md), keeps their data in a database.
