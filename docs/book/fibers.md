# Fibers

In this chapter you do several things at once: fetch pages while others load, serve many clients, keep a slow task from
holding up a fast one. A [fiber](glossary.md#fiber) is a function that runs beside the rest of the program, with its own
stack: what Go calls a goroutine, Java 21 a virtual thread, and others a *green thread*, a thread that the language runs
rather than the system. Fibers are light, about 2.1 KB each: a program can run a hundred thousand of them. They take turns
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

![A timeline: the main program spawns bread and cake and waits for bread; bread sleeps 0.2 s and cake 0.1 s, each parked on a timer, at the same time; cake ends at 0.1 s, bread at 0.2 s and wakes the main program, which gets both results at once: 0.2 s in all.](images/fibers-timeline.svg)

## What waits

A fiber that waits lets the others run: [sys.Sleep], a read from the network, a call to [fiber.Wait], [fiber.Receive] or
[fiber.Select], a [fiber.Send] on a full channel, a database that is busy.

### A long computation

A long computation doesn't hold the others up either: every million steps, a call or a turn of a loop each, a fiber that
computes gives way to the others that are ready, which is called [preemptive scheduling](glossary.md#preemptive-scheduling):
nobody writes a yield, as Erlang counts its reductions. So a server keeps answering its other clients while one of them
asks for a large report. It is not the preemption of a system thread, which a timer can stop anywhere: a function of
`std/` written in OCaml, as a [list.Sort] of a million elements, runs to its end before another fiber gets its turn. The fiber here is a function without a name on several lines,
written as a [do block](functions.md#do-blocks) after [fiber.Spawn]: `do` alone, as it takes no parameter, its lines,
and `end`:

```cesia
busy = fiber.Spawn() do
  n = 0
  for k in 1..2000000
    n += k
  end
  n
end
sys.Sleep(0.001)
"the program still runs" -->
fiber.Wait(busy) -->
```

## Waiting at most, and stopping a fiber

[fiber.Wait] can wait for a time at most: past it, it gives an `Err` of kind `"timeout"`, and the task runs on.
[fiber.Cancel] stops it: the fiber stops at its next wait, as a [sys.Sleep], a [fiber.Receive] or a call to the network, or
at the next checkpoint of a long computation, where it lets the others run. Then [fiber.Wait] gives an `Err` of kind
`"cancelled"`, which tells the file and the line where the fiber was. A server gives each request a time this way. The
fiber is written here the older way, as `defn ()` up to `end` inside the parentheses, which makes the same function:

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
baker = fiber.Spawn() do
  for product in ["bread", "cake", "tart"]
    fiber.Send(product, orders)
  end
  fiber.Close(orders)
end

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
fiber.Spawn() do
  fiber.Send("pie", orders)
  fiber.Close(orders)
end

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
worker = fiber.Spawn() do
  done = []
  got = fiber.Select([stop, jobs], timeout = 1)
  while result.IsOk(got)
    done = list.Append(got.Value.Value, done)
    got = fiber.Select([stop, jobs], timeout = 1)
  end
  done
end
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
fiber.Spawn() do
  for k in 1..3
    sys.Sleep(0.1)
    fiber.Receive(tray)!
  end
end
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

### A table that every fiber reads

A fiber that owns a state answers one message at a time: what it holds is never lost, and no two fibers change it at
once. But each question is a round trip, a message there and its answer back, and a server that asks for a session and
its rate limits at each request pays one at each request. [fiber.Table] holds what is read that often: values that every
fiber reads and writes at once, without a message. Each key, a text, holds a value until a time, and the table holds at
most so many keys: past them, a new key first drops those whose time passed, then those due soonest, the oldest written
first, down to three quarters. What a table holds may thus go at any time. It is a *cache*, a copy kept close because
the original is far or slow, and the truth still lives in a fiber that owns it, or in a database.

A server's sessions and its limit of 600 requests a minute for each address, with a burst of 150:

```cesia
use std/fiber
use std/value
sessions = fiber.Table(100000)
limits = fiber.Table(100000)
perAddress = {Per: 600, Period: 60, Burst: 150}
defn handle(ip, cookie, now)
  pass = fiber.Admit(["ip:$ip"], [perAddress], now, limits)
  if not pass.Ok
    return "429, wait $(pass.Retry) seconds"
  end
  user = fiber.Recall(cookie, now, sessions)
  if value.IsMissing(user)
    epoch = fiber.Epoch(sessions)
    user = "ana"   (* what the database says: the fiber waits for it, and others run *)
    fiber.Remember(cookie, user, now + 2, sessions, epoch = epoch)
  end
  "200, hello $user"
end
handle("203.0.113.7", "c0ffee", 1000) -->
fiber.Recall("c0ffee", 1001, sessions) -->
fiber.Recall("c0ffee", 1002, sessions) -->
```

[fiber.Recall] gives the value of a key, or missing once its time is not after now, a number of seconds that you give:
`sys.Now()`, or the clock of a test. [fiber.Remember] keeps a value until a time, [fiber.Forget] drops a key and
[fiber.Empty] all of them. A session read from the database before a sign-out emptied the table must not come back
after it: [fiber.Epoch] counts the times a table was emptied, and Remember with `epoch` keeps a value only if that count
hasn't moved since it was taken.

[fiber.Admit] counts a request in rate limits with GCRA, the *generic cell rate algorithm* of ATM networks (ITU-T
I.371): a key keeps one number, the time its next request is due, and a request passes when it comes no earlier than
that time minus the burst it may take at once, `(Burst - 1) * Period / Per` seconds. A request of several limits, as an
address, a user and his tenant, passes all of them or none: a request refused by one counts in none.

Each call on a table runs to its end before another fiber runs, as every fiber runs on the program's main thread: none
sees a key half written, and a limit counts each request once, whatever the fibers do around it. The keys are spread by
a hash of random seed, so that no one can choose keys that all fall in one place and make each look slow, an
*algorithmic complexity attack* (Crosby and Wallach, 2003). Each process of `cesia run --workers` has its own tables.

In Go, the same is a map behind a lock, its times checked by hand, and a limiter of `golang.org/x/time/rate`, a token
bucket, for each key, in another map that nothing prunes unless you do:

```go
var mu sync.Mutex
var limiters = map[string]*rate.Limiter{}
func allow(ip string) bool {
	mu.Lock()
	l, ok := limiters[ip]
	if !ok {
		l = rate.NewLimiter(rate.Every(time.Minute/600), 150)
		limiters[ip] = l
	}
	mu.Unlock()
	return l.Allow()
}
```

There each goroutine may run on its own core, so the lock is needed, and forgetting it is a data race that the race
detector finds only when it happens. Python's `cachetools.TTLCache` needs one too as soon as threads share it.

## Further reading

- C. A. R. Hoare, *Communicating Sequential Processes*, 1978: the channels, and the meeting of a send and a receive that a
  channel of size 0 is.
- The Go Programming Language Specification: buffered channels, `close` and `select`, which Cesia follows, but for
  [fiber.Select], which tries its channels in the order of its list where Go picks at random among the ready ones.
- KC Sivaramakrishnan and others, *Retrofitting Effect Handlers onto OCaml*, 2021: what each fiber is inside.
- Joe Armstrong, *A History of Erlang*, 2007: processes switched by counted steps.
- ITU-T Recommendation I.371, *Traffic control and congestion control in B-ISDN*: GCRA, the rate limits of [fiber.Admit].
- Scott A. Crosby, Dan S. Wallach, *Denial of Service via Algorithmic Complexity Attacks*, 2003: why the keys of a table
  are spread by a hash of random seed.

Each with its link in [References](references.md#fibers-and-channels); [How Cesia works](internals.md#fibers-and-the-scheduler)
shows the scheduler, and [Speed](speed.md#fibers-beside-goroutines-async-and-virtual-threads) fibers beside goroutines,
`async` and virtual threads.

## Next

Your programs do many things at once. The next chapter, [SQLite](sqlite.md), keeps their data in a database.
