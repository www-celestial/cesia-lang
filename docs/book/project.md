# A real program

In this chapter you build a small web service from nothing: it keeps notes in SQLite, and serves them as JSON. A client can
list the notes, add one, and mark one done. You make the project, write its package, test it without the network, and serve
it. Every chapter before this one is at work here.

## The project

`cesia new` makes the folder, with `src/main.ce`, `cesia.toml`, `std/` and `cesia.lock`:

```bash
cesia new notes
cd notes
mkdir -p src/notes data
```

The project will hold one package, `src/notes`, for the notes and their routes, and `src/main.ce`, which serves them:

```text
notes/
  cesia.toml
  data/                 the database, made at the first run
  src/
    main.ce             serves the notes on port 8080
    notes/
      store.ce          the notes in SQLite
      routes.ce         the web service
      routes.test.ce    its tests
```

Its `cesia.toml` becomes this one: the task `serve` replaces the `[tasks.run]` that `cesia new` wrote. It has the
permissions the server needs: the folder of the database, and the port.

```toml
[project]
name = "notes"
cesia = "1.0"

[tasks.serve]
file = "src/main.ce"
allow = ["read=data", "write=data", "net=:8080"]
```

## The store

`src/notes/store.ce` keeps the notes in a table. A struct says what a note is, and another what a client sends. `?` passes each
error of SQLite on to the caller:

```cesia
(* src/notes/store.ce *)
use std/sql
use std/result

struct Note
  (** A note, as the service gives it. *)
  Id Int
  Text Text
  Done Bool
end

struct NewNote
  (** What a client sends to add a note. *)
  Text Text
end

schema = "
  create table if not exists notes (
    id integer primary key,
    text text not null check (length(text) > 0),
    done boolean not null default false
  )"

defn Open(url)
  (** The database at a URL, with its table made if needed. *)
  db = sql.Open(url)?
  sql.Script(schema, db)?
  result.Ok(db)
end

defn Save(words, db)
  (** Adds a note, and gives it. *)
  added = sql.Exec("insert into notes (text) values (?)", [words], db)?
  result.Ok(Note(added.LastId, words, false))
end

List(db) = sql.Query("select id, text, done from notes order by id", [], db, as = Note.From)   (** Every note, the oldest first. *)

defn Finish(id, db)
  (** Marks a note done: missing if there is none with this id. *)
  changed = sql.Exec("update notes set done = true where id = ?", [id], db)?
  if changed.Changed == 0
    return result.Ok(missing)
  end
  sql.One("select id, text, done from notes where id = ?", [id], db, as = Note.From)
end
```

The store works on its own, before any web. A database in memory is enough to try it:

```cesia
db = result.Unwrap(Open("sqlite::memory:"))
Save("buy bread", db) -->
Save("", db) -->
Finish(1, db) -->
Finish(9, db) -->
List(db) -->
```

The table refuses an empty note by itself: its `check` turns it into an `Err`.

## The routes

`src/notes/routes.ce` turns requests into calls of the store, and results into responses. A [route](glossary.md#route)
sends each request to its [handler](glossary.md#handler).

### From an Err to a status

Each `Err` becomes a status: `400` for what the client sent, a body that doesn't fit `NewNote` or a text that breaks the
`check` of the table (the SQL code `23514`); `404` for a note that isn't there; and `500` for the rest, which is the
server's fault. A file of a package keeps its own uses:

```cesia
(* src/notes/routes.ce *)
use std/http
use std/text
use std/value

refused(e) = http.Json({Error: e.Message}, status = 400)
failed(e) = http.Json({Error: e.Message}, status = 500)

defn listed(db)
  match List(db)
    result.Ok(notes) -> http.Json(notes)
    result.Err(e) -> failed(e)
  end
end

defn added(request, db)
  match http.BodyJson(request) then result.AndThen(NewNote.From)
    result.Err(e) -> refused(e)
    result.Ok(n) -> match Save(n.Text, db)
      result.Ok(note) -> http.Json(note, status = 201)
      result.Err(e) -> if e.Code == "23514" refused(e) else failed(e) end
    end
  end
end

defn finished(request, db)
  id = text.Number(request.Params.id)
  if not value.IsInt(id)
    return refused({Message: "The id is a whole number."})
  end
  match Finish(id, db)
    result.Ok(note) -> if value.IsMissing(note) http.Json({Error: "No note $id."}, status = 404) else http.Json(note) end
    result.Err(e) -> failed(e)
  end
end

defn App(db)
  (** The web service of the notes in a database: GET /notes, POST /notes, POST /notes/:id/done. *)
  http.App()
    then http.Get("/notes", r -> listed(db))
    then http.Post("/notes", r -> added(r, db))
    then http.Post("/notes/:id/done", r -> finished(r, db))
end
```

## The tests

`src/notes/routes.test.ce` asks the service without the network, through [http.Handler], each test on a fresh database in
memory:

```cesia
(* src/notes/routes.test.ce *)
use std/http

defn ask(method, path, body = "")
  db = result.Unwrap(Open("sqlite::memory:"))
  handle = http.Handler(App(db))
  handle({Method: method, Path: path, Query: "", Headers: [], Body: body})
end

isEmptyAtFirst() = ask("GET", "/notes").Body == "[]"
isAdded() = ask("POST", "/notes", "{\"Text\": \"buy bread\"}").Status == 201
isEmptyTextRefused() = ask("POST", "/notes", "{\"Text\": \"\"}").Status == 400
isUnknownNote() = ask("POST", "/notes/7/done").Status == 404
```

Each test gives `true`:

```cesia
[isEmptyAtFirst(), isAdded(), isEmptyTextRefused(), isUnknownNote()] --> [true, true, true, true]
```

`cesia test` runs them, with the examples of the documentation, and says `4 passed, 0 failed`. Run it after each change.

```bash
cesia test
```

## Serving

`src/main.ce` opens the database in `data/`, and serves the routes behind [http.Logger]:

```text
use std/result
use std/http
use src/notes

db = result.Unwrap(notes.Open("sqlite:data/notes.db"))
http.Serve(http.Wrap(http.Logger, notes.App(db)), port = 8080)
```

`cesia do serve` runs it with the permissions of its task, and a client can talk to it:

```bash
cesia do serve
curl -d '{"Text": "buy bread"}' localhost:8080/notes
curl -X POST localhost:8080/notes/1/done
curl localhost:8080/notes
```

### In one program

The block below does the same in one program: it serves the routes on a port of this machine, and asks them with
[http.Fetch]:

```cesia allow=net=own
use std/sys
use std/http
use std/fiber
use std/io
served = result.Unwrap(Open("sqlite::memory:"))
fiber.Spawn(() -> http.Serve(http.Wrap(http.Logger, App(served)), port = 18781))
sys.Sleep(0)
base = "http://127.0.0.1:18781/notes"
io.Print(http.Fetch(base, method = "POST", body = "{\"Text\": \"buy bread\"}").Value.Body)
io.Print(http.Fetch(base, method = "POST", body = "{\"Txt\": \"typo\"}").Value.Body)
io.Print(http.Fetch("$base/1/done", method = "POST", body = "").Value.Body)
io.Print(http.Fetch(base).Value.Body)
```

## Where to go from here

- Add a route: `DELETE /notes/:id` with [http.Delete], a `delete` in the store, and its test first.
- Add `watch = true` to the task `serve`: each save then gives the running server its new code, a
  [hot reload](glossary.md#hot-reload).
- In production, add `workers = "cores"` to the task `serve` in place of `watch`: the server then runs on every core,
  and `kill -HUP` gives it a new version without a pause, as [Every core](http.md#every-core) says.
- Keep `cesia test` green and `cesia check` quiet as the code grows.
- Read the reference: every name of Cesia has its page, with its examples, under [Reference](ref/index.html). Press `/` to
  search it.
- Read [How Cesia works](internals.md), the next chapter, to know what makes a program fast or slow, and why each
  guarantee holds.
