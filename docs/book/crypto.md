# Cryptography

In this chapter you keep secrets: you store a password so that nobody can read it back, check that a message wasn't
changed, encrypt it for one key or for one person, and sign it, as a passkey and the sign-in of Google sign. [std/crypto]
does it through libsodium, a library that experts wrote and checked, through OpenSSL for the signatures of the web, and
its BLAKE2b with the one of OCaml's runtime; nothing of it is written by hand in Cesia but the comparison of two secrets,
ten lines, and a few bytes of DER around the numbers of a key, since a primitive of cryptography written by anyone else
is the first place an attack looks. It needs `--allow ffi=sodium`, and `ffi=crypto` for OpenSSL, and the libraries of
a release, which Cesia brings with it: [What runs where](#what-runs-where) says which call runs in which.

The examples of this chapter don't run when the book is built, since its pages may only call the C maths library; the
same examples run in the reference of each function, under `cesia test`.

## Bytes in a text

A key, a hash or a message encrypted is bytes, of any value from 0 to 255, and a Cesia text holds them as they are:
[text.ByteLength] counts them. [encode.Hex] and [encode.Base64] give them a form that can be printed or stored in JSON.

[crypto.Open] loads libsodium, and gives the `api` that every other function takes last:

```cesia norun
use std/crypto
use std/encode
use std/result
s = crypto.Open()!
encode.Hex(crypto.Sha256("abc", s))
```

## Hashes

A *hash function* turns a text of any length into a short one, the *digest*, so that two texts never give the same one in
practice, and nothing of the text can be found back from it. [crypto.Sha256] and [crypto.Sha512] are SHA-2, the NIST
standard, of 32 and 64 bytes; [crypto.Blake2b] is BLAKE2b, faster, of 16 to 64 bytes. A hash tells that a file is the one
expected, as the fingerprints of `cesia.lock` do with BLAKE2b.

An *HMAC*, [crypto.HmacSha256], is a hash under a secret key: only who has the key can make it, so it proves that a
message comes from them and wasn't changed, as the signature of a webhook does.

[crypto.HmacSha1] is HMAC with SHA-1, through OpenSSL, for one use: TOTP (RFC 6238), the codes of six digits that an
authenticator app shows, which every app computes with it. SHA-1 is broken for signatures, where two texts with one hash
make a forgery; HMAC asks less of its hash, that its compression function be a pseudorandom function, not that
collisions be hard (Bellare, 2006), and no attack on HMAC-SHA-1 is known. For anything new, [crypto.HmacSha256].

## Passwords

A password is never stored, nor its plain hash: an attacker who takes the table tries billions of words a second against a
fast hash. [crypto.HashPassword] uses Argon2id, a hash made slow on purpose and needing memory, with a *salt*, random
bytes stored with the hash so that two equal passwords give two different hashes. The result holds its salt and its
settings, so [crypto.CheckPassword] needs nothing else:

```cesia norun
use std/crypto
use std/result
s = crypto.Open()!
stored = crypto.HashPassword("correct horse", s)
crypto.CheckPassword("correct horse", stored, s)    (* true *)
crypto.CheckPassword("wrong", stored, s)            (* false *)
```

Each takes about 70 ms and 64 MiB, on a thread of its own: the other fibers run meanwhile, so a server goes on answering
while someone signs in. 50 sign-ins at once take 1,518 ms in all, where one after the other took 3,645 ms;
see [C and C++](c.md#a-call-that-takes-long).

## Comparing secrets

`==` stops at the first byte that differs, so the time it takes tells an attacker how many bytes were right, one guess
at a time: a *timing attack*. [crypto.IsSame] compares two texts in a time that depends only on their length: use it for
every secret, a token, an HMAC, a hash. It reads every byte of both and gathers their differences with an `or`, with no
branch on them, as eqaf, the comparison of MirageOS, does in OCaml; two texts of different lengths differ at once, since
a length is no secret. Its answers are those of libsodium's `sodium_memcmp`, which `tests/crypto/crypto.ce` checks.

## Encrypting with a key

[crypto.Seal] encrypts a message under a secret key of 32 bytes from [crypto.SecretKey], and [crypto.Unseal] gives it back
in an `Ok`, or an `Err` when the message was changed or the key is wrong. This is *authenticated encryption*: XSalsa20
hides the message, and Poly1305 adds a *tag*, [crypto.MacSize] bytes, that no one without the key can make, so a change of
one bit is refused, never decrypted into garbage. Each message takes a *nonce*, a number used once, which must never be
used twice with one key; [crypto.Seal] draws a random one of [crypto.NonceSize] bytes and keeps it in front of the result,
so there is nothing to manage:

```cesia norun
use std/crypto
use std/result
s = crypto.Open()!
key = crypto.SecretKey(s)
box = crypto.Seal("meet at noon", key, s)
crypto.Unseal(box, key, s)            (* Ok("meet at noon") *)
```

## Encrypting for someone

With *public-key cryptography*, each person has a pair of keys: a public one, given to everyone, and a secret one, kept.
[crypto.BoxPair] makes a pair; [crypto.BoxSeal] encrypts a message with the receiver's public key and the sender's secret
key, and [crypto.BoxOpen] opens it with the receiver's secret key and the sender's public key. Only the receiver can read
it, and the receiver knows who sent it. The keys are X25519, the messages XSalsa20 and Poly1305, as for [crypto.Seal].

## Signatures

A *signature* proves to anyone who has the public key that the owner of the secret key wrote a message, and that it
wasn't changed. [crypto.SignPair] makes a pair of Ed25519 keys, [crypto.Sign] gives the [crypto.SignatureSize] bytes of a
signature, and [crypto.Verify] checks it:

```cesia norun
use std/crypto
use std/result
s = crypto.Open()!
pair = crypto.SignPair(s)
sig = crypto.Sign("release 1.0", pair.Secret, s)
crypto.Verify(sig, "release 1.0", pair.Public, s)     (* true *)
```

## Signatures of the web: RS256, PS256 and ES256

The sign-in of Google, Microsoft or Apple sends an *ID token*, a JWT that the provider signs with RSA, and a passkey
signs with ECDSA on the curve P-256, or with RSA for Windows Hello. libsodium has neither, so [crypto.OpenSsl] loads
libcrypto, the library of OpenSSL 3, and gives the `api` that [crypto.KeyPair], [crypto.SignWith], [crypto.VerifyWith]
and [crypto.HmacSha1] take last. It needs `--allow ffi=crypto`; [crypto.Open], and a program with `ffi=sodium` alone,
stay as they were. Ed25519 stays libsodium's, [crypto.Sign] and [crypto.Verify]: one way for each algorithm.

An algorithm has the name that JOSE, the signed JSON of JWTs, gives it, one of [crypto.Algorithms]: `"RS256"`,
RSASSA-PKCS1-v1_5 with SHA-256 (RFC 8017); `"PS256"`, RSASSA-PSS with SHA-256, MGF1 with SHA-256 and a salt of 32
bytes, as RFC 7518 and RFC 8230 ask; `"ES256"`, ECDSA on P-256 with SHA-256 (FIPS 186-5). A public key is the DER of a
*SubjectPublicKeyInfo*, the binary form that OpenSSL, Java and Go read; a secret key the DER of a *PKCS #8*
PrivateKeyInfo, what `openssl pkey -outform DER` writes. [crypto.KeyPair] makes a pair, RSA of 2048 bits or a point of
P-256:

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

[crypto.VerifyWith] never stops the program, whatever bytes it gets: anything that isn't a signature of the message
under the key is `false`. So is a key of another type than the algorithm's, an EC key given with `"RS256"`: whoever
writes the algorithm of a token can't make a key be read as another kind, the attack called *algorithm confusion*. An
RSA key under 2048 bits is `false`, an EC key off P-256 too, and a key with bytes after its DER. [crypto.SignWith]
gives an `Err` for a secret key that isn't of the algorithm, never a signature that nobody would accept.

A provider publishes its keys as JWKs, in JSON, and a passkey sends a COSE key, in [CBOR](json.md#cbor): each holds the
numbers of the key, not its DER. [crypto.RsaKey] makes the DER from the modulus `n` and the exponent `e`, and
[crypto.EcKey] from the coordinates `x` and `y` of a point of P-256, each in big-endian bytes, in Cesia itself. A JWT
holds an ES256 signature as the 64 bytes of `r` and `s` side by side (RFC 7518), where OpenSSL and WebAuthn write it in
DER: [crypto.EcdsaDer] goes from the first to the second, and [crypto.EcdsaRaw] back. An ID token checked by its
provider's key, in the JWKS that it publishes:

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

The algorithm comes from the code, here `"RS256"`, never from the token's own header: a token says what it likes.
`tests/crypto/openssl.ce` checks the exact vectors of RFC 7515, a JWS signed with RS256 and one with ES256, and the
keys and signatures that OpenSSL's own command made, one line for each refusal.

## Random bytes

[crypto.Random] gives random bytes from the system, for a key, a token or a salt. [std/random] is for games and samples
only: its numbers come from a seed, and anyone who learns the seed can make them again.

## The sizes

[crypto.SecretKeySize], 32; [crypto.NonceSize], 24; [crypto.MacSize], 16; [crypto.PublicKeySize], 32;
[crypto.SignPublicSize], 32; [crypto.SignSecretSize], 64; [crypto.SignatureSize], 64; [crypto.PasswordSize], the room a
result of [crypto.HashPassword] may take, 128.

## What runs where

[crypto.Blake2b] runs in OCaml's runtime, whose BLAKE2b is the reference code of RFC 7693: the same bytes as libsodium's
at every size from 16 to 64 and every length of text from 0 to 260, which `tests/crypto/crypto.ce` checks with the
vector of the RFC, the BLAKE2b-512 of `"abc"`. [crypto.IsSame] runs in Cesia itself, as [encode.Hex] does, which gives a
hash its printable form, and so do [crypto.RsaKey], [crypto.EcKey], [crypto.EcdsaDer] and [crypto.EcdsaRaw], which only
write or read a few bytes of DER around the numbers, read back by OpenSSL. [crypto.KeyPair], [crypto.SignWith],
[crypto.VerifyWith] and [crypto.HmacSha1] run in OpenSSL's libcrypto: each key and each context it makes is freed on
every path, success or refusal, and the bytes it writes go into blocks of Cesia sized first, never into memory that
OpenSSL would have to free. A key of RSA takes some 50 ms to make, on a thread of its own, as a password hash does. All
the rest runs in libsodium: [crypto.Sha256], [crypto.Sha512] and [crypto.HmacSha256], as OCaml has no SHA-2 of its own
and one written here would be a primitive written by hand; [crypto.Random], from the system's generator; the
encryption of [crypto.Seal] and [crypto.BoxSeal], the signatures of [crypto.Sign], and the Argon2 of
[crypto.HashPassword].

What it changes, measured on 2026-11-25 on the machine of [Speed](speed.md#beside-the-giants), in microseconds, the
medians of 5 runs alternated with the version before, which called libsodium's BLAKE2b and `sodium_memcmp` through
[std/c] and wrote the hex in Cesia, and beside Python 3.14.10's `hashlib.blake2b` and `hmac.compare_digest`:

| Call | Before | Now | Python |
|---|---:|---:|---:|
| [crypto.Blake2b] of a secret of 64 bytes, 32 out | 3.56 | 0.47 | 0.67 |
| the same, then [encode.Hex] | 19.2 | 0.87 | 0.62 |
| [crypto.IsSame] of 32 bytes | 3.38 | 0.16 | 0.12 |
| the check of a session: the hash of its secret, in hex, compared with the one kept | 23.5 | 1.18 | 0.84 |
| the same check behind a route of [std/http], the secret read from a cookie | 30.8 | 4.7 | |

Python is still faster where it calls its C at once, by 0.1 to 0.3 µs: Cesia's calls go through the interpreter.

The signatures, measured on 2026-11-26 on the same machine, an Intel Core i7-4720HQ, by `bench/signatures.ce` and
`bench/signatures.js`: microseconds per call, the mean of 2,000 calls after 200, then the median of 21 runs alternated
with Node 26.13 and the lowest and highest, the load average between 1.0 and 1.6. The message has 400 bytes, as the
signing input of a JWT; the keys are RSA of 2048 bits and P-256. Cesia calls the libcrypto 3.5.9 of the system, Node
links OpenSSL 4.1.0. Node's first column parses its key once, into a KeyObject; its second takes the DER at each call,
as [crypto.VerifyWith] and [crypto.SignWith] do:

| Call | Cesia | Node, a KeyObject | Node, DER at each call |
|---|---:|---:|---:|
| [crypto.VerifyWith] RS256 | 76.1 [74.4, 81.5] | 36.9 [35.1, 38.3] | 64.0 [61.5, 74.5] |
| [crypto.VerifyWith] ES256 | 145.0 [142.7, 184.9] | 102.7 [100.5, 106.8] | 128.3 [127.0, 138.0] |
| [crypto.SignWith] ES256 | 98.1 [96.0, 151.2] | 41.7 [40.4, 44.3] | 92.2 [90.4, 95.2] |
| [crypto.HmacSha1] of 8 bytes, the count of TOTP | 6.25 [5.95, 6.76] | 5.93 [5.62, 7.57] | |

**Where Node wins, and why:** a KeyObject is parsed once and keeps what OpenSSL computes for a key at its first use,
the Montgomery form of an RSA modulus, the tables of a point; [crypto.VerifyWith] takes its key as DER, a text, parses
it and sets it up at each call, some 30 µs of RSA. Against Node given the DER each time, Cesia is 6 to 19 % slower: it
copies the key, the signature and the message into blocks of memory before each call, a few µs for these 950 bytes.
For a sign-in, one check of a few dozen µs is nothing beside the round trip to the provider, or the 70 ms of a
password's Argon2.

## Further reading

Bernstein on Salsa20 and Poly1305, Bernstein and others on Ed25519, Aumasson and others on BLAKE2, Biryukov and others on
Argon2, NIST's FIPS 180-4 for SHA-2, RFC 2104 for HMAC and Bellare on its proof, RFC 8017 for RSA, FIPS 186-5 for ECDSA,
RFC 7515 and 7518 for JWS, RFC 8230 and 9053 for COSE, and RFC 6238 for TOTP: see
[References](references.md#cryptography).

## Next

You can keep secrets. The next chapter, [Fibers](fibers.md), runs many things at once.
