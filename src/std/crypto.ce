-- Cryptography through libsodium: never written by hand here. Run with --allow ffi=sodium.
-- Texts hold bytes: encode.Hex and encode.Base64 give them a printable form.
use c

SecretKeySize = 32
NonceSize = 24
MacSize = 16
PublicKeySize = 32
SignPublicSize = 32
SignSecretSize = 64
SignatureSize = 64
PasswordSize = 128

defn block(s)
  b = c.Alloc(Max(ByteLength(s), 1))
  c.Store(s, 0, b)
  b
end

ints() = ["ptr", "ptr", "u64"]

-- Loads libsodium: an Ok of the api that the other functions take as their last argument s, or an Err.
defn Open()
  lib = c.Open("sodium", version = 26)?
  init = c.Fn("sodium_init", [], "i32", lib)?
  if init() < 0
    return Err({Kind: "crypto", Message: "libsodium couldn't start."})
  end
  Ok({
    Random: c.Fn("randombytes_buf", ["ptr", "u64"], "void", lib)?,
    Sha256: c.Fn("crypto_hash_sha256", ints(), "i32", lib)?,
    Sha512: c.Fn("crypto_hash_sha512", ints(), "i32", lib)?,
    Blake2b: c.Fn("crypto_generichash", ["ptr", "u64", "ptr", "u64", "ptr", "u64"], "i32", lib)?,
    HmacSize: c.Fn("crypto_auth_hmacsha256_statebytes", [], "u64", lib)?,
    HmacInit: c.Fn("crypto_auth_hmacsha256_init", ["ptr", "ptr", "u64"], "i32", lib)?,
    HmacUpdate: c.Fn("crypto_auth_hmacsha256_update", ints(), "i32", lib)?,
    HmacFinal: c.Fn("crypto_auth_hmacsha256_final", ["ptr", "ptr"], "i32", lib)?,
    SecretSeal: c.Fn("crypto_secretbox_easy", ["ptr", "ptr", "u64", "ptr", "ptr"], "i32", lib)?,
    SecretOpen: c.Fn("crypto_secretbox_open_easy", ["ptr", "ptr", "u64", "ptr", "ptr"], "i32", lib)?,
    BoxPair: c.Fn("crypto_box_keypair", ["ptr", "ptr"], "i32", lib)?,
    BoxSeal: c.Fn("crypto_box_easy", ["ptr", "ptr", "u64", "ptr", "ptr", "ptr"], "i32", lib)?,
    BoxOpen: c.Fn("crypto_box_open_easy", ["ptr", "ptr", "u64", "ptr", "ptr", "ptr"], "i32", lib)?,
    SignPair: c.Fn("crypto_sign_keypair", ["ptr", "ptr"], "i32", lib)?,
    Sign: c.Fn("crypto_sign_detached", ["ptr", "ptr", "ptr", "u64", "ptr"], "i32", lib)?,
    Verify: c.Fn("crypto_sign_verify_detached", ["ptr", "ptr", "u64", "ptr"], "i32", lib)?,
    HashPassword: c.Fn("crypto_pwhash_str", ["ptr", "ptr", "u64", "u64", "u64"], "i32", lib)?,
    CheckPassword: c.Fn("crypto_pwhash_str_verify", ["ptr", "ptr", "u64"], "i32", lib)?,
    PasswordOps: c.Fn("crypto_pwhash_opslimit_interactive", [], "u64", lib)?,
    PasswordMemory: c.Fn("crypto_pwhash_memlimit_interactive", [], "u64", lib)?,
    Compare: c.Fn("sodium_memcmp", ["ptr", "ptr", "u64"], "i32", lib)?
  })
end

sized(value, size, name) = Assert(ByteLength(value) == size, "$name has $size bytes.")

-- Runs f on a fresh output block and the blocks of the inputs, then gives the output bytes.
defn out(size, inputs, f)
  out = c.Alloc(Max(size, 1))
  blocks = Map(block, inputs)
  status = f(out, blocks)
  result = c.Load(0, size, out)
  c.Free(out)
  Map(c.Free, blocks)
  {Status: status, Bytes: result}
end

-- n random bytes from the system, as a text.
defn Random(n, s)
  out(n, [], (out, blocks) -> s.Random(out, n)).Bytes
end

-- A status other than 0 is a bug here: the zeros of a failed call must never pass for a result.
defn done(r)
  Assert(r.Status == 0, "libsodium refused this call.")
  r.Bytes
end

-- The SHA-256 hash of a text, as 32 bytes.
Sha256(textValue, s) = done(out(32, [textValue], (out, b) -> s.Sha256(out, b[1], ByteLength(textValue))))
-- The SHA-512 hash of a text, as 64 bytes.
Sha512(textValue, s) = done(out(64, [textValue], (out, b) -> s.Sha512(out, b[1], ByteLength(textValue))))

-- The BLAKE2b hash of a text, as a number of bytes from 16 to 64 (32 by default).
defn Blake2b(textValue, s, size = 32)
  Assert(size >= 16 and size <= 64, "blake2b needs a size from 16 to 64.")
  done(out(size, [textValue], (out, b) -> s.Blake2b(out, size, b[1], ByteLength(textValue), missing, 0)))
end

-- The HMAC-SHA-256 of a text under a key, as 32 bytes.
defn HmacSha256(key, textValue, s)
  state = c.Alloc(s.HmacSize())
  r = out(32, [key, textValue], (out, b) -> hmac(s, state, out, b, ByteLength(key), ByteLength(textValue)))
  c.Free(state)
  done(r)
end

defn hmac(s, state, out, b, keySize, size)
  BitOr(BitOr(s.HmacInit(state, b[1], keySize), s.HmacUpdate(state, b[2], size)), s.HmacFinal(state, out))
end

-- The same inputs can't tell where they differ by the time they take.
defn Same(a, b, s)
  if ByteLength(a) != ByteLength(b)
    return false
  end
  out(0, [a, b], (out, blocks) -> s.Compare(blocks[1], blocks[2], ByteLength(a))).Status == 0
end

refused() = Err({Kind: "crypto", Message: "This message was changed, or the key is wrong."})

-- Symmetric encryption. A nonce is never used twice with a key: the default takes a random one, kept in front.
SecretKey(s) = Random(SecretKeySize, s)

-- f(out, blocks, size) gets the message or the body, then the nonce, then the keys, in blocks.
defn sealed(message, keys, s, f)
  nonce = Random(NonceSize, s)
  size = ByteLength(message)
  r = out(size + MacSize, Concat([message, nonce], keys), (out, b) -> f(out, b, size))
  "$nonce$(done(r))"
end

defn opened(sealed, keys, f)
  total = ByteLength(sealed)
  if total < NonceSize + MacSize
    return refused()
  end
  nonce = ByteSlice(1, NonceSize, sealed)
  body = ByteSlice(NonceSize + 1, total, sealed)
  size = ByteLength(body)
  r = out(size - MacSize, Concat([body, nonce], keys), (out, b) -> f(out, b, size))
  if r.Status == 0 Ok(r.Bytes) else refused() end
end

-- A message encrypted and authenticated under a 32-byte key. The random nonce is kept in front of the result.
defn Seal(message, key, s)
  sized(key, SecretKeySize, "A key")
  sealed(message, [key], s, (out, b, size) -> s.SecretSeal(out, b[1], size, b[2], b[3]))
end

-- The message of a result of seal, in an Ok, or an Err if it was changed or the key is wrong.
defn Unseal(sealed, key, s)
  sized(key, SecretKeySize, "A key")
  opened(sealed, [key], (out, b, size) -> s.SecretOpen(out, b[1], size, b[2], b[3]))
end

-- Public keys: a pair gives {Public, Secret}.
defn pair(publicSize, secretSize, f)
  public = c.Alloc(publicSize)
  secret = c.Alloc(secretSize)
  f(public, secret)
  out = {Public: c.Load(0, publicSize, public), Secret: c.Load(0, secretSize, secret)}
  c.Free(public)
  c.Free(secret)
  out
end

-- A new key pair for BoxSeal, as a struct with public and secret.
BoxPair(s) = pair(PublicKeySize, SecretKeySize, s.BoxPair)

-- A message encrypted for the owner of a public key, and authenticated by the sender's secret key. The nonce is kept in front.
defn BoxSeal(message, toPublic, fromSecret, s)
  sized(toPublic, PublicKeySize, "A public key")
  sized(fromSecret, SecretKeySize, "A secret key")
  sealed(message, [toPublic, fromSecret], s, (out, b, size) -> s.BoxSeal(out, b[1], size, b[2], b[3], b[4]))
end

-- The message of a result of BoxSeal, in an Ok, or an Err if it was changed or the keys are wrong.
defn BoxOpen(sealed, fromPublic, toSecret, s)
  sized(fromPublic, PublicKeySize, "A public key")
  sized(toSecret, SecretKeySize, "A secret key")
  opened(sealed, [fromPublic, toSecret], (out, b, size) -> s.BoxOpen(out, b[1], size, b[2], b[3], b[4]))
end

-- A new key pair for sign, as a struct with public and secret.
SignPair(s) = pair(SignPublicSize, SignSecretSize, s.SignPair)

-- The 64-byte signature of a message under a secret signing key.
defn Sign(message, secret, s)
  sized(secret, SignSecretSize, "A secret key")
  size = ByteLength(message)
  done(out(SignatureSize, [message, secret], (out, b) -> s.Sign(out, missing, b[1], size, b[2])))
end

-- Is this signature the one of the message under the public signing key?
defn Verify(signature, message, public, s)
  if ByteLength(signature) != SignatureSize or ByteLength(public) != SignPublicSize
    return false
  end
  size = ByteLength(message)
  out(0, [signature, message, public], (out, b) -> s.Verify(b[1], b[2], size, b[3])).Status == 0
end

-- Passwords: the result holds its own salt and settings, and is safe to store.
defn HashPassword(password, s)
  size = ByteLength(password)
  r = done(out(PasswordSize, [password], (out, b) -> s.HashPassword(out, b[1], size, s.PasswordOps(), s.PasswordMemory())))
  ByteSlice(1, ByteFind(Char(0), 1, r) - 1, r)
end

-- Does the password match a result of HashPassword?
defn CheckPassword(password, stored, s)
  if ByteLength(stored) >= PasswordSize
    return false
  end
  size = ByteLength(password)
  padded = "$stored$(Repeat(PasswordSize - ByteLength(stored), Char(0)))"
  out(0, [padded, password], (out, b) -> s.CheckPassword(b[1], b[2], size)).Status == 0
end
