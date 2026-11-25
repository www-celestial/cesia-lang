# JSON et CSV

Dans ce chapitre, vous lisez des données que d'autres programmes ont écrites, et vous en écrivez pour eux. Le JSON vient
des services web et des fichiers de configuration, le CSV des tableurs. Vous vérifiez aussi ce qui arrive, pour qu'un champ
faux s'arrête à la porte au lieu d'aller loin dans votre code. Les exemples lisent trois fichiers : `order.json`,
`user.json` et `people.csv`.

## Lire du JSON

[json.Parse] lit un texte JSON, tel que la RFC 8259 le définit. Un objet devient un dictionnaire, un array (la liste entre
crochets de JSON) une liste, et `null` devient `missing`, le [null](glossary.md#null) de Cesia (la valeur qui dit qu'il
n'y a pas de valeur). Il donne un `Ok`, ou un `Err` qui dit où le texte devient faux. Voici `order.json` :

```text
{
  "id": 17,
  "customer": "Ana",
  "items": [
    {"product": "bread", "units": 2, "price": 1.25},
    {"product": "cake", "units": 1, "price": 8.0}
  ],
  "note": null
}
```

```cesia allow=read
use std/sys
use std/json
use std/result
order = sys.Read("order.json")! then json.Parse()!
order.customer -->
order.items[2].product -->
order.note -->
json.Parse("{\"id\": ") -->
```

Un nombre sans point ni exposant qui tient sur 63 bits devient un entier, et tout autre nombre un float (un nombre à
virgule) : `12345678901234567890` est donc lu comme un float, proche de lui. Une clé donnée deux fois garde sa dernière
valeur, comme le font la plupart des lecteurs de JSON. Un texte peut contenir n'importe quelle séquence d'échappement de
JSON, `\u00e9` compris. Un JSON imbriqué plus profond que la moitié de la limite `nesting`, 300 niveaux par défaut, est une
`Err`, `Too deep` (trop profond), si bien qu'une entrée hostile de dix mille `[` ne peut pas faire déborder le lecteur.

```cesia
json.Parse("12345678901234567890") -->
json.Parse("{\"a\": 1, \"a\": 2}") -->
json.Parse("\"caf\\u00e9\"") -->
```

À partir de là, les données sont des valeurs ordinaires, et tous les chapitres qui précèdent celui-ci s'appliquent :

```cesia allow=read
use std/list
list.Sum([i.units * i.price for i in order.items]) -->
[i.product for i in order.items if i.units > 1] -->
```

## Écrire du JSON

[json.Text] écrit une valeur en JSON sur une ligne, et [json.Pretty] sur plusieurs lignes, indentées. Un dictionnaire garde
ses clés telles qu'elles sont, `missing` devient `null`, et une struct (une forme déclarée, aux champs nommés) écrit ses
champs publics :

```cesia
use std/io
io.Print(json.Text({Name: "Ana", Tags: ["admin"], Phone: missing}))
io.Print(json.Pretty({Name: "Ana", Tags: ["admin", "ops"]}))
```

### Les champs privés restent dehors

Un champ de struct dont le nom commence par une minuscule est privé, et n'est jamais écrit. Un hash de mot de passe
(l'empreinte calculée à partir du mot de passe) gardé dans un tel champ ne peut pas fuir dans une réponse :

```cesia
struct Account { Name, hash }
io.Print(json.Text(Account("ana", "8f2c...")))
```

## Vérifier ce qui arrive

Des données venues de l'extérieur peuvent contenir n'importe quoi : un champ manquant, un nombre écrit comme un texte, une
clé avec une faute de frappe. `From`, que toute struct possède, transforme un dictionnaire en struct, et le vérifie d'après
les champs et leurs types. Avec [result.AndThen], lire et vérifier forment une seule chaîne. `user.json` contient une
ligne :

```text
{"Name": "Bo", "Age": 20, "Admin": true}
```

```cesia allow=read
struct User
  Name Text
  Age Int
  Admin Bool = false
end
sys.Read("user.json")! then json.Parse() then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Age\": \"twenty\"}") then result.AndThen(User.From) -->
json.Parse("{\"name\": \"Bo\", \"age\": 20}") then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"name\": \"Ana\", \"Age\": 20}") then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Agee\": 20}") then result.AndThen(User.From) -->
```

### Les clés comme JSON les écrit

Une clé est le nom d'un champ, ou ce nom tel que JSON et SQL l'écrivent souvent : `name` donne `Name`, et `created_at`
donne `CreatedAt`, la règle que le chapitre [SQLite](sqlite.md) applique aux colonnes. Deux clés pour un même champ sont
refusées, et une clé qui ne nomme aucun champ aussi : chaque message nomme la clé. Un champ qui a une valeur par défaut,
comme `Admin`, peut être omis.

### Les formes (*shapes*) : des bornes et un message pour chaque champ

`From` vérifie les types. Ce qu'envoie un visiteur demande aussi des bornes : un nom de 120 octets au plus, une quantité
de 1 à 1 000 000, une adresse e-mail, une liste de 50 lignes au plus. [std/check] le dit par une *forme* (*shape*), une
map qui décrit une valeur, et [check.Read] donne un `Ok` de la valeur nettoyée, ou un `Err` d'une map de chaque champ
faux, par son chemin, vers un message qu'un formulaire peut montrer à côté :

```cesia
use std/check
Line = check.Record({Label: check.Text(1, 200), Qty: check.Int(1, 1000000), Price: check.Money(2)})
Order = check.Record({Email: check.Email(), Due: check.Date(), Lines: check.List(Line, 1, 50)})
check.Read(Order, {Email: " Bo@Example.com", Due: "2026-12-01", Lines: [{Label: "Bread", Qty: 4, Price: 1.25}]}) --> result.Ok({Email: "bo@example.com", Due: 1796083200, Lines: [{Label: "Bread", Qty: 4, Price: 1.25}]})
check.Read(Order, {Email: "bo", Due: "2026-12-01", Lines: [{Label: "", Qty: 0, Price: 1}]}) then result.IsErr() --> true
```

- Chaque texte est de l'UTF-8 valide sans caractère de contrôle, sans espaces aux bouts, borné en octets ; chaque nombre a
  son intervalle (un `Int` de -(2^30 - 1) à 2^30 - 1 s'il ne dit rien, ce que tient aussi une page en WebAssembly) ;
  chaque liste, son nombre d'éléments au plus.
- Un jour est un `check.Date()`, `"2026-12-01"`, et un instant un `check.Time()`, `"2026-12-01T08:30:00Z"` ou avec son
  décalage : les deux sont lus en secondes depuis 1970, comme Cepheus les garde, et réécrits en texte par `check.Out`.
- Un champ que la forme ne déclare pas est ôté par `Read` : qui ajoute `Admin: true` n'ajoute rien. Un champ facultatif
  qu'il omet est là, avec sa valeur par défaut ou `missing`, pour que `x.Note` n'échoue jamais.
- `check.Read(shape, query, texts = true)` lit des valeurs écrites en texte, comme les donnent une *query string* ou
  l'environnement : `"42"` pour un `Int`, `""` pour un champ absent.
- [check.Out] rend une valeur au-dehors par sa forme : les champs déclarés seuls, les dates en texte, jamais un
  `check.Secret()` ; [check.Masked] écrit chaque secret `(secret)`, pour un log ; [check.Schema] donne le *JSON Schema*
  d'une forme, comme OpenAPI décrit un corps.
- C'est du Cesia pur : la page vérifie un formulaire pendant qu'on tape, avec la même forme que le serveur vérifie de
  nouveau.

## Lire du CSV

[std/csv] lit le CSV comme les tableurs l'écrivent : un champ qui contient une virgule ou une fin de ligne est entre
guillemets. [csv.Parse] donne chaque ligne comme une liste de textes, et [csv.Records] chaque ligne après la première comme
un dictionnaire, sous les noms de la première. Voici `people.csv` :

```text
name,city,age
Ana,"Lyon, France",31
Bo,Paris,20
Cyril,,45
```

```cesia allow=read
use std/csv
source = sys.Read("people.csv")!
csv.Parse(source) -->
people = csv.Records(source)
people[1].city -->
```

### Chaque champ est un texte

Chaque champ d'un CSV est un texte, puisque le format n'en dit pas plus. [text.Number] en fait un nombre, et un champ vide
est le texte vide :

```cesia allow=read
use std/text
[text.Number(p.age) for p in people] -->
[p.name for p in people if p.city == ""] -->
```

Pour une table sur laquelle calculer, [frame.FromCsv], du chapitre [Données](data.md), lit les nombres comme des nombres,
et les champs vides comme `missing`.

## Écrire du CSV

[csv.Text] écrit des lignes de valeurs, et met des guillemets là où il en faut :

```cesia
io.Print(csv.Text([["name", "note"], ["Ana", "says \"hi\""], ["Bo", "a,b"]]))
```

Une liste de listes s'écrit en un seul passage, en natif (du code OCaml compilé). Mesuré le 2026-11-13, 100 000 lignes
de 7 cellules, la médiane de 5 lancements du meilleur de 5 (`bench/csv.ce`, `bench/csv.py`) : Cesia 0,81 µs par ligne,
3,89 µs avant ; `csv.writer` de Python 3.14 1,12 µs. Pour les dates, Python gagne : [date.FormatDate] prend 0,61 µs,
`date.isoformat` 0,34 µs.

## Un petit convertisseur

Les morceaux s'assemblent en quelques lignes. Ce programme lit le CSV des personnes, vérifie chaque ligne, et écrit le
résultat en JSON, prêt pour un autre programme :

```cesia allow=read,write
use std/value
struct Person
  Name Text
  City Text?
  Age Int
end

defn person(row)
  age = text.Number(row.age)
  if not value.IsInt(age)
    return result.Err("$(row.name): the age must be a whole number")
  end
  city = if row.city == "" missing else row.city end
  Person.From({Name: row.name, City: city, Age: age})
end

checked = result.Collect(list.Map(person, people))
match checked
  result.Ok(all) -> sys.Write("people.json", json.Text(all))
  result.Err(e) -> io.Print("refused:", e)
end
io.Print(sys.Read("people.json")!)
```

## Des octets en texte : hexadécimal, Base64 et URL

[std/encode] écrit des octets sous la forme d'un texte que n'importe quel canal transporte. [encode.Hex] écrit chaque
octet en deux chiffres hexadécimaux, et [encode.Unhex] les relit ; [encode.Base64] écrit trois octets en quatre caractères
d'un alphabet de 64, comme le dit la RFC 4648, et [encode.Unbase64] lit ses deux alphabets, le standard et celui des URL,
avec ou sans le `=` de padding (les caractères ajoutés pour compléter la fin). [encode.UrlEncode] écrit chaque octet d'un
texte qu'une URL ne peut pas contenir sous la forme d'un `%` et de deux chiffres, le *percent-encoding*, et
[encode.UrlDecode] le relit, avec un `+` pour une espace, comme l'écrivent les formulaires ; [encode.ParseQuery] lit les
champs d'une query (la partie d'une URL après le point d'interrogation) ou d'un formulaire. [encode.Sha1] est le hash
SHA-1 que demande le handshake de WebSocket (l'échange qui ouvre une connexion WebSocket, laquelle reste ouverte dans les
deux sens), et rien d'autre : SHA-1 est cassé pour les signatures, et [std/crypto] a les hashes pour la sécurité.

```cesia
use std/encode
encode.Hex("hi") -->
encode.Unhex("6869") -->
encode.Base64("hi") -->
encode.Unbase64("aGk") -->
encode.UrlEncode("a b&c") -->
encode.UrlDecode("a+b%26c") -->
encode.ParseQuery("product=bread&units=2") -->
```

## Markdown

[std/markdown] transforme du Markdown, le format de texte des README, en HTML : la partie de CommonMark que GitHub montre
de la même façon, et ses tables. [markdown.Parse] donne les blocs, chacun un dictionnaire avec son `Kind` et sa `Line` ;
[markdown.Html] les écrit, et demande à ses hooks (des fonctions que vous lui passez et qu'il appelle en route) les
couleurs du code, la cible d'un nom entre crochets et l'ancre d'un titre ; [markdown.Plain] est un jeu de hooks qui
n'ajoutent rien. Tout ce qu'une page montre est échappé (ses caractères spéciaux sont écrits pour s'afficher tels quels,
sans agir), le HTML brut compris, et un lien ne mène qu'à `http`, `https`, `mailto` ou à une page du site : un texte venu
de n'importe qui y est sans danger. Les pages de ce livre sont faites ainsi.

```cesia
use std/markdown
markdown.Html(markdown.Parse("# Prices\n\nBread is *cheap*."), markdown.Plain) -->
markdown.Html(markdown.Parse("<script>alert(1)</script>"), markdown.Plain) -->
markdown.Parse("# Prices")[1].Kind -->
```

## Vitesse

[json.Parse] lit la scène d'une surface de 100 sur 100 quads, 192 KB de JSON faits surtout de nombres, telle qu'une
session de [cells](cells.md) l'envoie à un éditeur : la moyenne de 20 lectures après une première, à l'intérieur de
chaque programme, la médiane de 101 lancements alternés et l'intervalle à 95 % de cette médiane, sur la machine de
[Vitesse](speed.md#à-côté-des-géants), le 2026-11-19 :

| | 192 KB |
|---|---:|
| **Cesia**, [json.Parse] | **3,36 ms** (3,34 à 3,36) |
| Python 3.14.10, `json.loads` | 3,34 ms (3,34 à 3,35) |
| Node 26.13, `JSON.parse` | 1,06 ms (1,05 à 1,06) |

```cesia allow=read,write
use std/plot
parsers = plot.Bars(["Cesia", "Python", "Node"], [3.36, 3.34, 1.06])
parsing = plot.Of([parsers], title = "Parsing 192 KB of JSON: milliseconds, median of 101 runs", y = "milliseconds",
  size = [640, 300])
plot.Save(parsing, "json-parse.svg") -->
```

Le parser (le code qui lit le texte et en fait des valeurs) de Cesia est en OCaml, dans son binaire : il cherche la fin
d'un texte huit octets à la fois, et lit un décimal de 15 chiffres ou moins, avec une puissance de dix de $10^{-22}$ à
$10^{22}$, par un seul produit ou un seul quotient de deux doubles qui les tiennent exactement, qu'IEEE 754 arrondit
correctement : le *fast path* (le chemin rapide) de Clinger (1990). Les lignes d'un document qui ont les mêmes clés les
partagent. Le `json.loads` de Python fait tourner le scanner de son module `_json`, écrit en C : les deux prennent le
même temps, à un demi pour cent près. **Là où Node gagne, et pourquoi :** le `JSON.parse` de V8 est du C++ dans le
moteur lui-même, qui fait les objets et les nombres de JavaScript au fil de sa lecture, 3,2 fois plus vite que les deux.

## Pour aller plus loin

La RFC 8259 pour JSON, la RFC 4180 pour CSV, la RFC 4648 pour Base64 et l'hexadécimal, la RFC 3986 pour les échappements
des URL, et la spécification CommonMark pour Markdown : voir [Références](references.md#textes-et-formats).

## La suite

Vous savez lire et écrire les données d'autres programmes. Le chapitre suivant, [HTTP](http.md), va chercher des données
sur le web, et en sert.
