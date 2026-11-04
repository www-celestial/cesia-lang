use crypto
use encode

defn main()
  s = crypto.Open()?
  Print(encode.Hex(crypto.Sha256("abc", s)))
  Print(Take(1, [encode.Hex(crypto.Sha512("abc", s))]))
  Print(encode.Hex(crypto.HmacSha256("key", "The quick brown fox jumps over the lazy dog", s)))
  Print(encode.Hex(crypto.Blake2b("abc", s, size = 64)))
  Print(ByteLength(crypto.Random(16, s)), crypto.Random(16, s) != crypto.Random(16, s))
  Print(crypto.Same("abc", "abc", s), crypto.Same("abc", "abd", s), crypto.Same("a", "ab", s))

  key = crypto.SecretKey(s)
  box = crypto.Seal("zero$(Char(0))byte", key, s)
  Print(ByteLength(box), crypto.Unseal(box, key, s) then MapOk(ByteLength))
  Print(crypto.Unseal(box, crypto.SecretKey(s), s) then MapErr(it.Message))
  Print(IsErr(crypto.Unseal("short", key, s)))
  other = if Byte(1, box) == 120 "y" else "x" end
  Print(crypto.Unseal("$other$(ByteSlice(2, ByteLength(box), box))", key, s) then IsErr)
  Print(crypto.Seal("same", key, s) != crypto.Seal("same", key, s))

  alice = crypto.BoxPair(s)
  bob = crypto.BoxPair(s)
  sent = crypto.BoxSeal("hello bob", bob.Public, alice.Secret, s)
  Print(crypto.BoxOpen(sent, alice.Public, bob.Secret, s))
  Print(IsErr(crypto.BoxOpen(sent, bob.Public, bob.Secret, s)))

  pair = crypto.SignPair(s)
  signature = crypto.Sign("message", pair.Secret, s)
  Print(ByteLength(signature), crypto.Verify(signature, "message", pair.Public, s), crypto.Verify(signature, "other", pair.Public, s))

  stored = crypto.HashPassword("secret", s)
  Print(StartsWith("$$argon2id$$", stored), crypto.CheckPassword("secret", stored, s), crypto.CheckPassword("wrong", stored, s))
  Print(fails(() -> crypto.Blake2b("abc", s, size = 100)))
  Print(fails(() -> crypto.Seal("m", "short", s)))
  Print(fails(() -> crypto.Sign("m", "short", s)))
  Print(fails(() -> crypto.BoxSeal("m", "a", "b", s)))
  Print(crypto.Verify("x", "m", "y", s))
  Print(crypto.CheckPassword("p", Repeat(200, "x"), s))
  Ok(missing)
end

defn fails(f)
  match Wait(Spawn(f))
    Ok(v) -> "no failure"
    Err(e) -> e.Message
  end
end

Print(main())
