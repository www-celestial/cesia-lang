# Cryptographie

Dans ce chapitre, vous gardez des secrets : vous rangez un mot de passe de façon que personne ne puisse le relire, vous
vérifiez qu'un message n'a pas été modifié, vous le chiffrez pour une clé ou pour une personne, et vous le signez, comme
signent une passkey et la connexion de Google. [std/crypto] le fait par libsodium, une bibliothèque que des experts ont
écrite et vérifiée, par OpenSSL pour les signatures du web, et son BLAKE2b par celui du runtime d'OCaml (ce qui
accompagne un programme pendant qu'il tourne) ; rien n'en est écrit à la main en Cesia, sauf la comparaison de deux
secrets, dix lignes, et quelques octets de DER autour des nombres d'une clé, puisqu'une primitive de cryptographie (une
brique de base, comme un chiffrement ou un hash) écrite par quelqu'un d'autre est le premier endroit que regarde une
attaque. Il lui faut `--allow ffi=sodium`, et `ffi=crypto` pour OpenSSL, et les bibliothèques d'une release (une version
publiée de Cesia), que Cesia apporte avec lui : [Ce qui tourne où](#ce-qui-tourne-où) dit quel appel tourne dans
quoi.

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
s = crypto.Open()!
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

[crypto.HmacSha1] est HMAC avec SHA-1, par OpenSSL, pour un seul usage : TOTP (RFC 6238), les codes de six chiffres
qu'affiche une application d'authentification, que toutes les applications calculent avec lui. SHA-1 est cassé pour les
signatures, où deux textes d'un même hash font une contrefaçon ; HMAC demande moins à son hash, que sa fonction de
compression soit une fonction pseudo-aléatoire, pas que les collisions soient difficiles (Bellare, 2006), et aucune
attaque contre HMAC-SHA-1 n'est connue. Pour tout ce qui est nouveau, [crypto.HmacSha256].

## Les mots de passe

Un mot de passe ne se garde jamais, ni son simple hash : un attaquant qui prend la table essaie des milliards de mots par
seconde contre un hash rapide. [crypto.HashPassword] utilise Argon2id, un hash rendu lent exprès et qui demande de la
mémoire, avec un *salt*, des octets au hasard rangés avec le hash pour que deux mots de passe égaux donnent deux hashes
différents. Le résultat contient son salt et ses réglages : [crypto.CheckPassword] n'a donc besoin de rien d'autre.

```cesia norun
use std/crypto
use std/result
s = crypto.Open()!
stored = crypto.HashPassword("correct horse", s)
crypto.CheckPassword("correct horse", stored, s)    (* true *)
crypto.CheckPassword("wrong", stored, s)            (* false *)
```

Chacun prend environ 70 ms et 64 Mio, sur un thread à lui : les autres fibers tournent pendant ce temps, si bien qu'un
serveur continue de répondre pendant que quelqu'un se connecte. 50 connexions à la fois prennent 1 518 ms en tout, là
où l'une après l'autre prenaient 3 645 ms ; voir [C et C++](c.md#un-appel-qui-prend-du-temps).

![Ce que crypto.HashPassword garde pour correct horse, partie par partie : argon2id, l'algorithme ; v=19, sa version ; la mémoire, les passes et les voies qu'il a pris ; le sel, des octets au hasard ; le hash. Le même mot de passe haché de nouveau donne un autre sel et un autre hash, et crypto.CheckPassword lit tout ce qu'il lui faut dans le texte.](../../book/images/crypto-password-fr.svg)

## Comparer des secrets

`==` s'arrête au premier octet qui diffère : le temps qu'il prend dit donc à un attaquant combien d'octets étaient justes,
un essai après l'autre. C'est une *timing attack* (une attaque par la mesure du temps). [crypto.IsSame] compare deux textes
en un temps qui ne dépend que de leur longueur : servez-vous-en pour tous les secrets, un token (la suite d'octets secrète
qu'un programme présente pour prouver ses droits), un HMAC, un hash. Il lit chaque octet des deux et rassemble leurs
différences par un `or`, sans branche sur elles, comme le fait en OCaml eqaf, la comparaison de MirageOS ; deux textes de
longueurs différentes diffèrent tout de suite, puisqu'une longueur n'est pas un secret. Ses réponses sont celles de
`sodium_memcmp` de libsodium, ce que vérifie `tests/crypto/crypto.ce`.

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
s = crypto.Open()!
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
s = crypto.Open()!
pair = crypto.SignPair(s)
sig = crypto.Sign("release 1.0", pair.Secret, s)
crypto.Verify(sig, "release 1.0", pair.Public, s)     (* true *)
```

## Les signatures du web : RS256, PS256 et ES256

La connexion de Google, de Microsoft ou d'Apple envoie un *ID token* (un jeton d'identité), un JWT (un JSON signé) que
le fournisseur signe avec RSA, et une passkey signe avec ECDSA sur la courbe P-256, ou avec RSA pour Windows Hello.
libsodium n'a ni l'un ni l'autre, donc [crypto.OpenSsl] charge libcrypto, la bibliothèque d'OpenSSL 3, et donne l'`api`
que [crypto.KeyPair], [crypto.SignWith], [crypto.VerifyWith] et [crypto.HmacSha1] prennent en dernier. Il lui faut
`--allow ffi=crypto` ; [crypto.Open], et un programme qui n'a que `ffi=sodium`, restent comme ils étaient. Ed25519 reste
à libsodium, [crypto.Sign] et [crypto.Verify] : une seule façon pour chaque algorithme.

Un algorithme porte le nom que lui donne JOSE, le JSON signé des JWT, l'un de [crypto.Algorithms] : `"RS256"`,
RSASSA-PKCS1-v1_5 avec SHA-256 (RFC 8017) ; `"PS256"`, RSASSA-PSS avec SHA-256, MGF1 avec SHA-256 et un salt (des
octets au hasard mêlés à la signature) de 32 octets, comme le demandent la RFC 7518 et la RFC 8230 ; `"ES256"`, ECDSA sur
P-256 avec SHA-256 (FIPS 186-5). Une clé publique est le DER (la forme binaire des structures d'ASN.1) d'une
*SubjectPublicKeyInfo*, la forme que lisent OpenSSL, Java et Go ; une clé secrète le DER d'une PrivateKeyInfo de *PKCS #8*,
ce qu'écrit `openssl pkey -outform DER`. [crypto.KeyPair] fait une paire, RSA de 2048 bits ou un point de P-256 :

```cesia norun
use std/crypto
use std/result
o = crypto.OpenSsl()!
pair = crypto.KeyPair("ES256", o)!
signature = crypto.SignWith("pay 10", pair.Secret, "ES256", o)!
crypto.VerifyWith(signature, "pay 10", pair.Public, "ES256", o)    (* true *)
crypto.VerifyWith(signature, "pay 99", pair.Public, "ES256", o)    (* false *)
crypto.VerifyWith(signature, "pay 10", pair.Public, "RS256", o)    (* false *)
```

[crypto.VerifyWith] n'arrête jamais le programme, quels que soient les octets qu'il reçoit : tout ce qui n'est pas une
signature du message sous la clé est `false`. Une clé d'un autre type que celui de l'algorithme l'est aussi, une clé EC
donnée avec `"RS256"` : qui écrit l'algorithme d'un token ne peut pas faire lire une clé comme une autre sorte, l'attaque
qu'on appelle *algorithm confusion* (la confusion d'algorithme). Une clé RSA de moins de 2048 bits est `false`, une clé
EC hors de P-256 aussi, et une clé avec des octets après son DER. [crypto.SignWith] donne une `Err` pour une clé secrète
qui n'est pas de l'algorithme, jamais une signature que personne n'accepterait.

Un fournisseur publie ses clés en JWK (une clé en JSON), et une passkey envoie une COSE key, en [CBOR](json.md#cbor) :
chacune contient les nombres de la clé, pas son DER. [crypto.RsaKey] fait le DER à partir du modulus `n` et de
l'exposant `e`, et [crypto.EcKey] à partir des coordonnées `x` et `y` d'un point de P-256, chacun en octets big-endian
(l'octet de poids fort d'abord), en Cesia lui-même. Un JWT contient une signature ES256 sous la forme des 64 octets de
`r` et de `s` côte à côte (RFC 7518), là où OpenSSL et WebAuthn l'écrivent en DER : [crypto.EcdsaDer] passe de la
première à la seconde, et [crypto.EcdsaRaw] revient. Un ID token vérifié par la clé de son fournisseur, dans le JWKS
(le jeu de clés) qu'il publie :

```cesia norun
use std/crypto
use std/encode
use std/result
use std/text
use std/value

defn signedBy(token, jwk, o)
  (** Is the ID token signed by this key of the provider's JWKS, {"kty": "RSA", "n": "...", "e": "AQAB"}? *)
  parts = text.Split(".", token)
  if value.Len(parts) != 3
    return result.Ok(false)
  end
  key = crypto.RsaKey(encode.Unbase64(jwk.n)?, encode.Unbase64(jwk.e)?)?
  signature = encode.Unbase64(parts[3])?
  result.Ok(crypto.VerifyWith(signature, "$(parts[1]).$(parts[2])", key, "RS256", o))
end
```

L'algorithme vient du code, ici `"RS256"`, jamais du header (l'en-tête) du token lui-même : un token dit ce qu'il veut.
`tests/crypto/openssl.ce` vérifie les vecteurs exacts de la RFC 7515, un JWS signé avec RS256 et un avec ES256, et les
clés et les signatures qu'a faites la commande d'OpenSSL elle-même, une ligne pour chaque refus.

## Des octets au hasard

[crypto.Random] donne des octets au hasard venus du système, pour une clé, un token ou un salt. [std/random] ne sert
qu'aux jeux et aux échantillons : ses nombres viennent d'un seed (le nombre dont part le générateur), et quiconque apprend
le seed peut les refaire.

## Les tailles

[crypto.SecretKeySize], 32 ; [crypto.NonceSize], 24 ; [crypto.MacSize], 16 ; [crypto.PublicKeySize], 32 ;
[crypto.SignPublicSize], 32 ; [crypto.SignSecretSize], 64 ; [crypto.SignatureSize], 64 ; [crypto.PasswordSize], la place
que peut prendre un résultat de [crypto.HashPassword], 128.

## Ce qui tourne où

[crypto.Blake2b] tourne dans le runtime d'OCaml, dont le BLAKE2b est le code de référence de la RFC 7693 : les mêmes
octets que celui de libsodium à toutes les tailles de 16 à 64 et toutes les longueurs de texte de 0 à 260, ce que
`tests/crypto/crypto.ce` vérifie avec le vecteur de la RFC, le BLAKE2b-512 de `"abc"`. [crypto.IsSame] tourne dans Cesia
lui-même, comme [encode.Hex], qui donne à un hash sa forme imprimable, et de même [crypto.RsaKey], [crypto.EcKey],
[crypto.EcdsaDer] et [crypto.EcdsaRaw], qui ne font qu'écrire ou lire quelques octets de DER autour des nombres, relus
par OpenSSL. [crypto.KeyPair], [crypto.SignWith], [crypto.VerifyWith] et [crypto.HmacSha1] tournent dans la libcrypto
d'OpenSSL : chaque clé et chaque contexte qu'elle fabrique est libéré sur tous les chemins, réussite ou refus, et les
octets qu'elle écrit vont dans des blocs de Cesia dont la taille est demandée d'abord, jamais dans une mémoire
qu'OpenSSL devrait libérer. Une clé RSA prend quelque 50 ms à fabriquer, sur un thread à elle, comme un hash de mot de
passe. Tout le reste tourne dans libsodium :
[crypto.Sha256], [crypto.Sha512] et [crypto.HmacSha256], puisqu'OCaml n'a pas de SHA-2 à lui et qu'un SHA-2 écrit ici
serait une primitive écrite à la main ; [crypto.Random], du générateur du système ; le chiffrement de [crypto.Seal] et
de [crypto.BoxSeal], les signatures de [crypto.Sign], et l'Argon2 de [crypto.HashPassword].

Ce que cela change, mesuré le 2026-11-25 sur la machine de [Vitesse](speed.md#à-côté-des-géants), en microsecondes, les
médianes de 5 lancements alternés avec la version d'avant, qui appelait le BLAKE2b et le `sodium_memcmp` de libsodium
par [std/c] et écrivait l'hexadécimal en Cesia, et à côté de `hashlib.blake2b` et `hmac.compare_digest` de Python
3.14.10 :

| Appel | Avant | Maintenant | Python |
|---|---:|---:|---:|
| [crypto.Blake2b] d'un secret de 64 octets, 32 en sortie | 3,56 | 0,47 | 0,67 |
| le même, puis [encode.Hex] | 19,2 | 0,87 | 0,62 |
| [crypto.IsSame] de 32 octets | 3,38 | 0,16 | 0,12 |
| la vérification d'une session : le hash de son secret, en hexadécimal, comparé à celui gardé | 23,5 | 1,18 | 0,84 |
| la même vérification derrière une route de [std/http], le secret lu dans un cookie | 30,8 | 4,7 | |

Python reste plus rapide là où il appelle son C tout de suite, de 0,1 à 0,3 µs : les appels de Cesia passent par
l'interpréteur.

Les signatures, mesurées le 2026-11-26 sur la même machine, un Intel Core i7-4720HQ, par `bench/signatures.ce` et
`bench/signatures.js` : des microsecondes par appel, la moyenne de 2 000 appels après 200, puis la médiane de 21
lancements alternés avec Node 26.13 et le plus bas et le plus haut, la charge moyenne (load average) entre 1,0 et 1,6.
Le message a 400 octets, comme l'entrée signée d'un JWT ; les clés sont RSA de 2048 bits et P-256. Cesia appelle la
libcrypto 3.5.9 du système, Node se lie à OpenSSL 4.1.0. La première colonne de Node lit sa clé une fois, dans un
KeyObject (un objet de clé) ; la seconde prend le DER à chaque appel, comme le font [crypto.VerifyWith] et
[crypto.SignWith] :

| Appel | Cesia | Node, un KeyObject | Node, le DER à chaque appel |
|---|---:|---:|---:|
| [crypto.VerifyWith] RS256 | 76,1 [74,4, 81,5] | 36,9 [35,1, 38,3] | 64,0 [61,5, 74,5] |
| [crypto.VerifyWith] ES256 | 145,0 [142,7, 184,9] | 102,7 [100,5, 106,8] | 128,3 [127,0, 138,0] |
| [crypto.SignWith] ES256 | 98,1 [96,0, 151,2] | 41,7 [40,4, 44,3] | 92,2 [90,4, 95,2] |
| [crypto.HmacSha1] de 8 octets, le compte de TOTP | 6,25 [5,95, 6,76] | 5,93 [5,62, 7,57] | |

**Là où Node gagne, et pourquoi :** un KeyObject est lu une fois et garde ce qu'OpenSSL calcule pour une clé à sa
première utilisation, la forme de Montgomery d'un modulus RSA, les tables d'un point ; [crypto.VerifyWith] prend sa clé
en DER, un texte, la lit et la prépare à chaque appel, quelque 30 µs pour RSA. Face à Node à qui l'on donne le DER à
chaque fois, Cesia est de 6 à 19 % plus lent : il copie la clé, la signature et le message dans des blocs de mémoire
avant chaque appel, quelques µs pour ces 950 octets. Pour une connexion, une vérification de quelques dizaines de µs
n'est rien à côté de l'aller-retour vers le fournisseur, ou des 70 ms de l'Argon2 d'un mot de passe.

## Pour aller plus loin

Bernstein sur Salsa20 et Poly1305, Bernstein et al. sur Ed25519, Aumasson et al. sur BLAKE2, Biryukov et al. sur Argon2,
le FIPS 180-4 du NIST pour SHA-2, la RFC 2104 pour HMAC et Bellare sur sa preuve, la RFC 8017 pour RSA, le FIPS 186-5
pour ECDSA, les RFC 7515 et 7518 pour JWS, les RFC 8230 et 9053 pour COSE, et la RFC 6238 pour TOTP : voir
[Références](references.md#cryptographie).

## La suite

Vous savez garder des secrets. Le chapitre suivant, [Fibers](fibers.md), fait plusieurs choses à la fois.
