# Cryptographie

Dans ce chapitre, vous gardez des secrets : vous rangez un mot de passe de façon que personne ne puisse le relire, vous
vérifiez qu'un message n'a pas été modifié, vous le chiffrez pour une clé ou pour une personne, et vous le signez.
[std/crypto] fait tout cela par libsodium, une bibliothèque que des experts ont écrite et vérifiée ; rien n'en est écrit à
la main en Cesia, puisqu'une primitive de cryptographie (une brique de base, comme un chiffrement ou un hash) écrite par
quelqu'un d'autre est le premier endroit que regarde une attaque. Il lui faut `--allow ffi=sodium`, et la libsodium d'une
release (une version publiée de Cesia), que Cesia apporte avec lui.

Les exemples de ce chapitre ne tournent pas quand le livre est construit, puisque ses pages ne peuvent appeler que la
bibliothèque mathématique du C ; les mêmes exemples tournent dans la référence de chaque fonction, sous `cesia test`.

## Des octets dans un texte

Une clé, un hash (une empreinte courte, voir plus bas) ou un message chiffré sont des octets, de n'importe quelle valeur
de 0 à 255, et un texte de Cesia les contient tels qu'ils sont : [text.ByteLength] les compte. [encode.Hex] et
[encode.Base64] leur donnent une forme qui peut être affichée ou rangée dans du JSON.

[crypto.Open] charge libsodium, et donne l'`api` que toutes les autres fonctions prennent en dernier :

```cesia norun
use std/crypto
use std/encode
use std/result
s = result.Unwrap(crypto.Open())
encode.Hex(crypto.Sha256("abc", s))
```

## Les hashes

Une *hash function* (une fonction de hash) transforme un texte de n'importe quelle longueur en un texte court, le
*digest* (l'empreinte), de façon qu'en pratique deux textes ne donnent jamais le même, et que rien du texte ne puisse être
retrouvé à partir de lui. [crypto.Sha256] et [crypto.Sha512] sont SHA-2, le standard du NIST, de 32 et 64 octets ;
[crypto.Blake2b] est BLAKE2b, plus rapide, de 16 à 64 octets. Un hash dit qu'un fichier est bien celui qu'on attend, comme
le font avec BLAKE2b les fingerprints (les empreintes) de `cesia.lock`.

Un *HMAC*, [crypto.HmacSha256], est un hash sous une clé secrète : seul celui qui a la clé peut le fabriquer, si bien qu'il
prouve qu'un message vient de lui et n'a pas été modifié, comme le fait la signature d'un webhook (un appel HTTP qu'un
service envoie à votre serveur quand un événement arrive).

## Les mots de passe

Un mot de passe ne se garde jamais, ni son simple hash : un attaquant qui prend la table essaie des milliards de mots par
seconde contre un hash rapide. [crypto.HashPassword] utilise Argon2id, un hash rendu lent exprès et qui demande de la
mémoire, avec un *salt*, des octets au hasard rangés avec le hash pour que deux mots de passe égaux donnent deux hashes
différents. Le résultat contient son salt et ses réglages : [crypto.CheckPassword] n'a donc besoin de rien d'autre.

```cesia norun
use std/crypto
use std/result
s = result.Unwrap(crypto.Open())
stored = crypto.HashPassword("correct horse", s)
crypto.CheckPassword("correct horse", stored, s)    (* true *)
crypto.CheckPassword("wrong", stored, s)            (* false *)
```

Chacun prend environ 70 ms et 64 Mio, sur un thread à lui : les autres fibers tournent pendant ce temps, si bien qu'un
serveur continue de répondre pendant que quelqu'un se connecte. 50 connexions à la fois prennent 1 518 ms en tout, là
où l'une après l'autre prenaient 3 645 ms ; voir [C et C++](c.md#un-appel-qui-prend-du-temps).

## Comparer des secrets

`==` s'arrête au premier octet qui diffère : le temps qu'il prend dit donc à un attaquant combien d'octets étaient justes,
un essai après l'autre. C'est une *timing attack* (une attaque par la mesure du temps). [crypto.IsSame] compare deux textes
en un temps qui ne dépend que de leur longueur : servez-vous-en pour tous les secrets, un token (la suite d'octets secrète
qu'un programme présente pour prouver ses droits), un HMAC, un hash.

## Chiffrer avec une clé

[crypto.Seal] chiffre un message sous une clé secrète de 32 octets venue de [crypto.SecretKey], et [crypto.Unseal] le rend
dans un `Ok`, ou un `Err` quand le message a été modifié ou que la clé est fausse. C'est de l'*authenticated encryption*
(un chiffrement qui prouve aussi que le message n'a pas été modifié) : XSalsa20 cache le message, et Poly1305 ajoute un
*tag* (une étiquette) de [crypto.MacSize] octets, que personne ne peut fabriquer sans la clé ; un changement d'un seul bit
est donc refusé, jamais déchiffré en données sans sens. Chaque message prend un *nonce*, un nombre utilisé une seule fois,
qui ne doit jamais servir deux fois avec une même clé ; [crypto.Seal] en tire un au hasard, de [crypto.NonceSize] octets,
et le garde devant le résultat : il n'y a rien à gérer.

```cesia norun
use std/crypto
use std/result
s = result.Unwrap(crypto.Open())
key = crypto.SecretKey(s)
box = crypto.Seal("meet at noon", key, s)
crypto.Unseal(box, key, s)            (* Ok("meet at noon") *)
```

## Chiffrer pour quelqu'un

Avec la *public-key cryptography* (la cryptographie à clé publique), chaque personne a une paire de clés : une publique,
donnée à tous, et une secrète, qu'elle garde. [crypto.BoxPair] fait une paire ; [crypto.BoxSeal] chiffre un message avec la
clé publique du destinataire et la clé secrète de l'expéditeur, et [crypto.BoxOpen] l'ouvre avec la clé secrète du
destinataire et la clé publique de l'expéditeur. Seul le destinataire peut le lire, et il sait qui l'a envoyé. Les clés
sont des clés X25519, les messages XSalsa20 et Poly1305, comme pour [crypto.Seal].

## Les signatures

Une *signature* prouve à quiconque a la clé publique que le propriétaire de la clé secrète a écrit un message, et que ce
message n'a pas été modifié. [crypto.SignPair] fait une paire de clés Ed25519, [crypto.Sign] donne les
[crypto.SignatureSize] octets d'une signature, et [crypto.Verify] la vérifie :

```cesia norun
use std/crypto
use std/result
s = result.Unwrap(crypto.Open())
pair = crypto.SignPair(s)
sig = crypto.Sign("release 1.0", pair.secret, s)
crypto.Verify(sig, "release 1.0", pair.public, s)     (* true *)
```

## Des octets au hasard

[crypto.Random] donne des octets au hasard venus du système, pour une clé, un token ou un salt. [std/random] ne sert
qu'aux jeux et aux échantillons : ses nombres viennent d'un seed (le nombre dont part le générateur), et quiconque apprend
le seed peut les refaire.

## Les tailles

[crypto.SecretKeySize], 32 ; [crypto.NonceSize], 24 ; [crypto.MacSize], 16 ; [crypto.PublicKeySize], 32 ;
[crypto.SignPublicSize], 32 ; [crypto.SignSecretSize], 64 ; [crypto.SignatureSize], 64 ; [crypto.PasswordSize], la place
que peut prendre un résultat de [crypto.HashPassword], 128.

## Pour aller plus loin

Bernstein sur Salsa20 et Poly1305, Bernstein et al. sur Ed25519, Aumasson et al. sur BLAKE2, Biryukov et al. sur Argon2,
le FIPS 180-4 du NIST pour SHA-2, et la RFC 2104 pour HMAC : voir [Références](references.md#cryptographie).

## La suite

Vous savez garder des secrets. Le chapitre suivant, [Fibers](fibers.md), fait plusieurs choses à la fois.
