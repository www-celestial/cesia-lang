use encode

isHex() = encode.Hex("é!") == "c3a921"
isUnhex() = Unwrap(encode.Unhex("c3A921")) == "é!" and IsErr(encode.Unhex("0")) and IsErr(encode.Unhex("zz"))
isBase64() = encode.Base64("hello") == "aGVsbG8=" and encode.Base64("hi") == "aGk=" and encode.Base64("abc") == "YWJj" and encode.Base64("") == ""
isUnbase64() = Unwrap(encode.Unbase64("aGVsbG8=")) == "hello" and Unwrap(encode.Unbase64("aGk")) == "hi" and IsErr(encode.Unbase64("a")) and IsErr(encode.Unbase64("a!bc"))
isBase64RoundTrip() = Unwrap(encode.Unbase64(encode.Base64(FromBytes([0, 255, 128, 7])))) == FromBytes([0, 255, 128, 7])
isUrlEncode() = encode.UrlEncode("a b&é") == "a%20b%26%C3%A9"
isUrlDecode() = encode.UrlDecode("a%20b+c%26%C3%A9") == "a b c&é" and encode.UrlDecode("100%") == "100%"
isQuery() = Equal(encode.ParseQuery("a=1&b=two+words&c=&d"), {"a": "1", "b": "two words", "c": "", "d": ""})
isQueryEmpty() = Equal(encode.ParseQuery(""), Dict())
isSha1() = encode.Hex(encode.Sha1("abc")) == "a9993e364706816aba3e25717850c26c9cd0d89d" and encode.Hex(encode.Sha1("")) == "da39a3ee5e6b4b0d3255bfef95601890afd80709"
isSha1Long() = encode.Hex(encode.Sha1(Repeat(1000, "a"))) == "291e9a6c66994949b57ba5e650361e98fc36b1ba"
isWebsocketAccept() = encode.Base64(encode.Sha1("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11")) == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
