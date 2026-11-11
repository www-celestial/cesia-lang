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
order = result.Unwrap(sys.Read("order.json")) then json.Parse() then result.Unwrap()
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
result.Unwrap(sys.Read("user.json")) then json.Parse() then result.AndThen(User.From) -->
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
source = result.Unwrap(sys.Read("people.csv"))
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
io.Print(result.Unwrap(sys.Read("people.json")))
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

## Pour aller plus loin

La RFC 8259 pour JSON, la RFC 4180 pour CSV, la RFC 4648 pour Base64 et l'hexadécimal, la RFC 3986 pour les échappements
des URL, et la spécification CommonMark pour Markdown : voir [Références](references.md#textes-et-formats).

## La suite

Vous savez lire et écrire les données d'autres programmes. Le chapitre suivant, [HTTP](http.md), va chercher des données
sur le web, et en sert.
