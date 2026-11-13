# Cryptography

In this chapter you keep secrets: you store a password so that nobody can read it back, check that a message wasn't
changed, encrypt it for one key or for one person, and sign it. [std/crypto] does all of it through libsodium, a library
that experts wrote and checked; nothing of it is written by hand in Cesia, since a primitive of cryptography written by
anyone else is the first place an attack looks. It needs `--allow ffi=sodium`, and the libsodium of a release, which
Cesia brings with it.

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
s = result.Unwrap(crypto.Open())
encode.Hex(crypto.Sha256("abc", s))
```

## Hashes

A *hash function* turns a text of any length into a short one, the *digest*, so that two texts never give the same one in
practice, and nothing of the text can be found back from it. [crypto.Sha256] and [crypto.Sha512] are SHA-2, the NIST
standard, of 32 and 64 bytes; [crypto.Blake2b] is BLAKE2b, faster, of 16 to 64 bytes. A hash tells that a file is the one
expected, as the fingerprints of `cesia.lock` do with BLAKE2b.

An *HMAC*, [crypto.HmacSha256], is a hash under a secret key: only who has the key can make it, so it proves that a
message comes from them and wasn't changed, as the signature of a webhook does.

## Passwords

A password is never stored, nor its plain hash: an attacker who takes the table tries billions of words a second against a
fast hash. [crypto.HashPassword] uses Argon2id, a hash made slow on purpose and needing memory, with a *salt*, random
bytes stored with the hash so that two equal passwords give two different hashes. The result holds its salt and its
settings, so [crypto.CheckPassword] needs nothing else:

```cesia norun
use std/crypto
use std/result
s = result.Unwrap(crypto.Open())
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
every secret, a token, an HMAC, a hash.

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
s = result.Unwrap(crypto.Open())
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
s = result.Unwrap(crypto.Open())
pair = crypto.SignPair(s)
sig = crypto.Sign("release 1.0", pair.secret, s)
crypto.Verify(sig, "release 1.0", pair.public, s)     (* true *)
```

## Random bytes

[crypto.Random] gives random bytes from the system, for a key, a token or a salt. [std/random] is for games and samples
only: its numbers come from a seed, and anyone who learns the seed can make them again.

## The sizes

[crypto.SecretKeySize], 32; [crypto.NonceSize], 24; [crypto.MacSize], 16; [crypto.PublicKeySize], 32;
[crypto.SignPublicSize], 32; [crypto.SignSecretSize], 64; [crypto.SignatureSize], 64; [crypto.PasswordSize], the room a
result of [crypto.HashPassword] may take, 128.

## Further reading

Bernstein on Salsa20 and Poly1305, Bernstein and others on Ed25519, Aumasson and others on BLAKE2, Biryukov and others on
Argon2, NIST's FIPS 180-4 for SHA-2, and RFC 2104 for HMAC: see [References](references.md#cryptography).

## Next

You can keep secrets. The next chapter, [Fibers](fibers.md), runs many things at once.
