# Un vrai programme

Dans ce chapitre, vous construisez un petit service web à partir de rien : il garde des notes dans SQLite, et les sert en
JSON. Un client peut lister les notes, en ajouter une, et en marquer une comme faite. Vous créez le projet, écrivez son
package, le testez sans le réseau, et le servez. Tous les chapitres d'avant servent ici.

## Le projet

`cesia new` crée le dossier, avec `src/main.ce`, `cesia.toml`, `std/` et `cesia.lock` :

```bash
cesia new notes
cd notes
mkdir -p src/notes data
```

Le projet tiendra un package (du code groupé sous un nom ; en Cesia, un dossier de fichiers .ce), `src/notes`, pour les
notes et leurs routes (chacune envoie les requêtes d'une méthode et d'un chemin à leur fonction), et `src/main.ce`, qui
les sert :

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

Son `cesia.toml` devient celui-ci : la tâche `serve` remplace le `[tasks.run]` qu'a écrit `cesia new`. Elle a les
permissions dont le serveur a besoin : le dossier de la base de données, et le port.

```toml
[project]
name = "notes"
cesia = "1.0"

[tasks.serve]
file = "src/main.ce"
allow = ["read=data", "write=data", "net=:8080"]
```

## Le stockage

`src/notes/store.ce` garde les notes dans une table. Une struct (une forme déclarée, aux champs nommés) dit ce qu'est une
note, et une autre ce qu'envoie un client. `?` transmet à l'appelant chaque erreur de SQLite :

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

Le stockage marche seul, avant tout web. Une base de données en mémoire suffit pour l'essayer :

```cesia
db = result.Unwrap(Open("sqlite::memory:"))
Save("buy bread", db) -->
Save("", db) -->
Finish(1, db) -->
Finish(9, db) -->
List(db) -->
```

La table refuse d'elle-même une note vide : son `check` la change en `Err`.

## Les routes

`src/notes/routes.ce` change les requêtes en appels au stockage, et les résultats en réponses. Une
[route](glossary.md#route) envoie chaque requête à son [handler](glossary.md#handler) (la fonction qui y répond).

### D'un Err à un statut

Chaque `Err` devient un statut (le nombre de trois chiffres qui ouvre une réponse HTTP) : `400` pour ce qu'a envoyé le
client, un corps qui ne correspond pas à `NewNote` ou un texte qui enfreint le `check` de la table (le code SQL
`23514`) ; `404` pour une note qui n'existe pas ; et `500` pour le reste, qui est la faute du serveur. Chaque fichier
d'un package a ses propres lignes use :

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

## Les tests

`src/notes/routes.test.ce` interroge le service sans le réseau, par [http.Handler], chaque test sur une nouvelle base de
données en mémoire :

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

Chaque test donne `true` :

```cesia
[isEmptyAtFirst(), isAdded(), isEmptyTextRefused(), isUnknownNote()] --> [true, true, true, true]
```

`cesia test` les lance, avec les exemples de la documentation, et affiche `4 passed, 0 failed` (4 réussis, 0 en échec).
Lancez-le après chaque changement.

```bash
cesia test
```

## Servir

`src/main.ce` ouvre la base de données dans `data/`, et sert les routes derrière [http.Logger] :

```text
use std/result
use std/http
use src/notes

db = result.Unwrap(notes.Open("sqlite:data/notes.db"))
http.Serve(http.Wrap(http.Logger, notes.App(db)), port = 8080)
```

`cesia do serve` le lance avec les permissions de sa tâche, et un client peut lui parler :

```bash
cesia do serve
curl -d '{"Text": "buy bread"}' localhost:8080/notes
curl -X POST localhost:8080/notes/1/done
curl localhost:8080/notes
```

### Dans un seul programme

Le bloc ci-dessous fait la même chose dans un seul programme : il sert les routes sur un port de cette machine, et les
interroge avec [http.Fetch] :

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

## Et ensuite

- Ajoutez une route : `DELETE /notes/:id` avec [http.Delete], un `delete` dans le stockage, et d'abord son test.
- Ajoutez `watch = true` à la tâche `serve` : chaque enregistrement donne alors au serveur qui tourne son nouveau code,
  un [hot reload](glossary.md#hot-reload) (du nouveau code chargé sans arrêter le programme).
- En production, ajoutez `workers = "cores"` à la tâche `serve` à la place de `watch` : le serveur tourne alors sur tous
  les cœurs, et `kill -HUP` lui donne une nouvelle version sans pause, comme le dit [Tous les cœurs](http.md#tous-les-cœurs).
- Gardez `cesia test` au vert (tous les tests réussis) et `cesia check` silencieux à mesure que le code grandit.
- Lisez la référence : chaque nom de Cesia a sa page, avec ses exemples, dans la [Référence](ref/index.html). Appuyez
  sur `/` pour y chercher.
- Lisez [Résoudre un vrai problème](duplicates.md), le chapitre suivant, pour aller d'un problème à la preuve qu'il est
  résolu, et [Comment Cesia fonctionne](internals.md), pour savoir ce qui rend un programme rapide ou lent, et pourquoi
  chaque garantie tient.
