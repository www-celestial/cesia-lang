# SQLite

Dans ce chapitre, vous gardez des données dans une base de données : vous faites une table, vous ajoutez des lignes, vous
les demandez, vous les modifiez dans une transaction, et vous les lisez comme des structs (des formes déclarées, aux champs
nommés). [std/sql] parle SQL à SQLite, une base de données dans un seul fichier, ou en mémoire, sans serveur à faire
tourner.

## Ouvrir une base de données

[sql.Open] prend une URL : `sqlite:PATH` pour un fichier, `sqlite::memory:` pour une base qui vit aussi longtemps que le
programme. Un fichier demande les permissions `read` et `write` de son dossier ; une base en mémoire n'en demande aucune :

```cesia
use std/sql
use std/result
db = result.Unwrap(sql.Open("sqlite::memory:"))
```

[sql.Script] exécute plusieurs instructions, pour un schéma (la déclaration des tables) :

```cesia
schema = "
  create table notes (
    id integer primary key,
    title text not null unique,
    done boolean not null default false,
    created_at text not null default '2026-11-06 10:00:00'
  )"
sql.Script(schema, db) -->
```

## Ajouter des lignes

[sql.Exec] exécute une instruction qui change des lignes. Chaque `?` du texte prend la valeur suivante de la liste. Il
donne `Changed`, le nombre de lignes changées, et `LastId`, l'id de la dernière ligne ajoutée.

```cesia
sql.Exec("insert into notes (title) values (?)", ["buy bread"], db) -->
sql.Exec("insert into notes (title) values (?)", ["call Bo"], db) -->
```

### Des règles enfreintes

Une règle de la table qu'une ligne enfreint donne un `Err` avec un code, celui que lui donne SQL : `23505` pour une valeur
qui doit être unique, `23502` pour une valeur manquante, `23514` pour un `check` qui échoue.

```cesia
sql.Exec("insert into notes (title) values (?)", ["buy bread"], db) -->
sql.Exec("insert into notes (title) values (?)", [missing], db) -->
```

## Les valeurs n'entrent jamais dans le texte

Écrivez chaque valeur sous la forme d'un `?`, jamais dans le texte avec `$`. Une valeur mise dans le texte est lue comme du
SQL : un nom tapé par un utilisateur peut donc changer la query (la requête SQL), ce qu'on appelle une injection. Par `?`,
une valeur n'est jamais qu'une valeur, dans une [parameterized query](glossary.md#parameterized-query) :

```cesia
name = "x' or '1'='1"
sql.Query("select * from notes where title = ?", [name], db) -->
```

### Une instruction par appel

Un appel exécute une seule instruction : un texte qui en cache une seconde est donc refusé.

```cesia
sql.Exec("select 1; drop table notes", [], db) -->
```

## Interroger

[sql.Query] donne toutes les lignes, chacune sous forme de dictionnaire. Les noms des colonnes deviennent des noms
publics : `created_at` se lit `CreatedAt`. NULL donne `missing`, et une colonne déclarée `boolean` donne un Bool :

```cesia
rows = result.Unwrap(sql.Query("select * from notes", [], db))
rows -->
rows[1].CreatedAt -->
```

### Une seule ligne

[sql.One] donne la première ligne, ou `missing` quand il n'y en a pas :

```cesia
sql.One("select title from notes where id = ?", [2], db) -->
sql.One("select title from notes where id = ?", [9], db) -->
```

## Des lignes en structs

Avec `as`, chaque ligne passe par une fonction, et le `From` d'une struct la vérifie. Une ligne qui ne convient pas donne
un `Err` qui dit laquelle :

```cesia
struct Note
  Id Int
  Title Text
  Done Bool
  CreatedAt Text
end
sql.Query("select * from notes where not done", [], db, as = Note.From) -->
```

## Transactions

Une [transaction](glossary.md#transaction) fait plusieurs changements comme un seul : tous, ou aucun. [sql.Transaction]
exécute une fonction avec `tx`, qui sert de `db` dans chaque appel. Un `Ok` de la fonction garde tous ses changements ;
un `Err`, ou une panic (l'arrêt net du programme sur un bug), les défait tous :

```cesia
sql.Transaction(tx -> sql.Exec("update notes set done = true where id = ?", [1], tx), db) -->
defn clearAll(tx)
  sql.Exec("delete from notes", [], tx)?
  result.Err("changed my mind")
end
sql.Transaction(clearAll, db) -->
sql.Query("select id, done from notes", [], db) -->
```

Le `delete` a été défait : les deux notes sont toujours là.

### Dans une transaction

Une [sql.Transaction] dans une autre, sur son `tx`, est un *savepoint* (un point de retour à l'intérieur d'une
transaction) : elle est défaite seule quand sa fonction donne un `Err`, pendant que la transaction extérieure continue.
`read = true` ouvre une transaction qui ne fait que lire. Une transaction tourne dans une fiber à elle (une fonction qui
tourne à côté du reste du programme), pour qu'un [fiber.Cancel] de la fiber qui l'a commencée ne puisse pas la laisser
ouverte : elle se termine comme le dit sa fonction.

### Ce que garantit une transaction

Les transactions de SQLite sont *ACID* : *atomiques*, tous leurs changements ou aucun ; *cohérentes*, chaque règle des
tables tient après chacune ; *isolées*, comme ci-dessous ; et *durables*, un changement confirmé reste, même après un crash
ou une coupure de courant. La durabilité demande que le journal atteigne le disque à chaque commit (la confirmation d'une
transaction) : le réglage `synchronous` de SQLite vaut `FULL`, 2, sur les bases que Cesia ouvre, ce que la documentation
de SQLite appelle ACID en mode WAL, là où `NORMAL` pourrait perdre les derniers commits lors d'une coupure de courant.
Cesia ouvre chaque fichier de base en mode *WAL*, un [write-ahead log](glossary.md#write-ahead-log) : chaque changement
est d'abord écrit dans le fichier `-wal` à côté de la base, puis recopié dans la base plus tard, si bien qu'après un crash
SQLite relit le journal et ne perd rien de confirmé. Avec lui, les lecteurs n'attendent pas le writer (celui qui écrit),
ni le writer les lecteurs.

L'isolation est exacte. Chaque transaction qui lit voit la base telle qu'elle était quand sa première lecture a commencé,
quoi que les autres confirment entre-temps : c'est la *snapshot isolation*. Et SQLite ne laisse écrire qu'un writer à la
fois : les transactions qui écrivent passent donc l'une après l'autre. Le résultat est toujours celui d'un certain ordre
des transactions, ce qui est l'isolation *serializable*, la plus forte du standard SQL. Une transaction de
[sql.Transaction] qui écrit prend le lock d'écriture (ce qui réserve l'écriture à elle seule) dès son début, avec
`BEGIN IMMEDIATE` : deux d'entre elles ne lisent donc jamais toutes les deux pour découvrir ensuite qu'une seule peut
écrire ; la seconde attend à son début.

Cesia active aussi les *foreign keys* (les clés étrangères) : une colonne déclarée avec `references` vers une autre table
refuse une ligne qui ne pointe nulle part. Et il ouvre chaque fichier avec les réglages défensifs de SQLite : aucune
extension chargée, rien d'attaché, aucun texte ni BLOB au-delà de 100 MB.

### L'attente et les fibers

Un pool de connexions (un groupe de connexions ouvertes d'avance), 8 par défaut, le `max` de [sql.Open], sert les fibers :
chaque appel en prend une, et la rend. Quand la base est occupée, tenue par un writer d'un autre programme, un appel attend
dans sa fiber, 1 ms, puis deux fois plus longtemps chaque fois jusqu'à 50 ms, pendant au plus `wait` secondes, 5 par
défaut : les autres fibers tournent donc pendant ce temps. Une query qui tourne, en revanche, va jusqu'à sa fin dans SQLite
avant qu'une autre fiber ait son tour, comme toute fonction de `std/` écrite en OCaml ou en C : une query de plusieurs
secondes retient un serveur pendant autant de secondes, et a sa place dans une tâche de fond, ou derrière un index qui la
rend courte.

## Beaucoup de lignes

[sql.Each] appelle une fonction sur chaque ligne, avec seulement un batch (un lot) de lignes en mémoire à la fois, quelle
que soit la taille du résultat. La fonction donne un `Ok` pour continuer :

```cesia
use std/io
sql.Each(r -> result.Ok(io.Print(r.Title)), "select title from notes order by id", [], db) -->
```

### En colonnes

[sql.Table] donne le résultat en colonnes : les `Names` des colonnes, et les `Columns` de valeurs, la forme sur laquelle
travaille [std/frame] :

```cesia
sql.Table("select id, title from notes", [], db) -->
```

## Une base de données dans un fichier

Un fichier garde ses données d'une exécution à l'autre. Ici, le programme garde la base dans le dossier `data`, la crée,
y écrit, et la relit :

```cesia allow=read,write
use std/sys

defn count(path)
  db = sql.Open("sqlite:$path")?
  sql.Script("create table if not exists visits (at text)", db)?
  sql.Exec("insert into visits values (?)", ["now"], db)?
  n = sql.One("select count(*) as total from visits", [], db)?
  sql.Close(db)
  result.Ok(n.Total)
end
sys.Mkdir("data")
count("data/visits.db") -->
count("data/visits.db") -->
```

```bash
cesia run --allow read=data,write=data visits.ce
```

SQLite écrit deux autres fichiers à côté de la base pendant qu'il tourne, `visits.db-wal` et `visits.db-shm`. Les
permissions portent donc sur le dossier qui les contient tous, `data` : une permission sur `data/visits.db` seul est
refusée, avec le nom du fichier qui lui manque. Une base utilisée par une autre fiber ou un autre programme est attendue,
dans cette fiber seulement : les autres continuent.

## Pour aller plus loin

- Kevin P. Gaffney et al., *SQLite: Past, Present, and Future*, 2022 : comment SQLite est construit.
- Les pages de SQLite sur le write-ahead logging et l'isolation, <https://www.sqlite.org/wal.html> et
  <https://www.sqlite.org/isolation.html> : ce sur quoi reposent les garanties de ce chapitre.
- Hal Berenson et al., *A Critique of ANSI SQL Isolation Levels*, 1995 : où sont définies la snapshot isolation et la
  serializability.

Chacun avec son lien dans [Références](references.md#bases-de-données).

## La suite

Vos programmes gardent leurs données. Le chapitre suivant, [Tests](tests.md), vérifie qu'ils continuent de faire ce
qu'ils doivent.
