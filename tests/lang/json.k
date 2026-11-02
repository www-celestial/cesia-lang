use json

defn fails(f, kind)
  (Wait(Spawn(f)) then MapErr(it.Kind)) == Err(kind)
end
ok(s) = Unwrap(json.Parse(s))
isNull() = IsMissing(ok("null"))
isBools() = ok("true") == true and ok("false") == false
isWhole() = ok("42") == 42 and IsInt(ok("-7"))
isDecimal() = ok("1.5") == 1.5 and ok("1e3") == 1000.0 and IsFloat(ok("2.0"))
isBigInt() = IsFloat(ok("123456789012345678901234567890"))
isText() = ok("""a""") == "a"
isEscapes() = ok("\"\\n\\t\\\"\\\\\\/\"") == "\n\t\"\\/"
isUnicode() = ok("""\u00e9""") == "é" and ok("""\ud83d\ude00""") == "😀"
isArray() = Equal(ok("[1, ""a"", null, [2]]"), [1, "a", missing, [2]])
isEmptyArray() = Equal(ok("[]"), [])
isObject() = Equal(ok("{""a"": 1, ""b"": [true]}"), {"a": 1, "b": [true]})
isEmptyObject() = Equal(ok("{}"), Dict())
isSpaces() = Equal(ok(" \n { ""a"" : 1 } \t"), {"a": 1})
isLaterKey() = ok("{""a"": 1, ""a"": 2}")["a"] == 2
isNested() = ok("{""a"": {""b"": [{""c"": 1}]}}")["a"]["b"][1]["c"] == 1
bad(s) = IsErr(json.Parse(s))
isBadInputs() = All([bad(s) for s in ["", "{", "[1,", "tru", "01", "1.", "[1 2]", "{1: 2}", """a", """\x""", "nul", "[1]]", "-", """\ud83d"""]])
isErrorShape() = (json.Parse("{") then MapErr(it.Kind)) == Err("json")
isTooDeep() = bad(Repeat(5000, "["))
isDeepEnough() = IsOk(json.Parse("$(Repeat(200, "["))$(Repeat(200, "]"))"))
isWriteScalars() = json.Text(1) == "1" and json.Text(1.5) == "1.5" and json.Text(true) == "true" and json.Text(missing) == "null"
isWriteControl() = json.Text(Char(1)) == "\"\\u0001\""
isWriteArray() = json.Text([1, "a", [true]]) == "[1,""a"",[true]]"
isWriteStruct() = json.Text({A: 1, B: "x"}) == "{""A"":1,""B"":""x""}"
isWriteDict() = json.Text({"z": 1, 2: 3}) == "{""2"":3,""z"":1}"
isWriteWholeFloat() = json.Text(2.0) == "2.0"
isWriteNan() = fails(() -> json.Text(0.0 / 0.0), "type")
isWriteFunction() = fails(() -> json.Text(Print), "type")
isRoundTrip() = Equal(ok(json.Text({"a": [1, 2.5, "x", missing, {"b": true}]})), {"a": [1, 2.5, "x", missing, {"b": true}]})
isPretty() = json.Pretty({"a": [1]}) == "{\n  ""a"": [\n    1\n  ]\n}"
isPrettyEmpty() = json.Pretty([]) == "[]"
isWriteText() = json.Text("a\"\n\\é") == "\"a\\\"\\n\\\\é\""
isNestingStaysInItsFiber() = IsErr(Wait(Spawn(() -> Text(deep(700))))) and Text(1) == "1"
isHugeExponent() = bad("1e999")

defn deep(n)
  x = 1
  for k in 1:n
    x = {A: x}
  end
  x
end
