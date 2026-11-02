use regex

defn fails(f, kind)
  (Wait(Spawn(f)) then MapErr(it.Kind)) == Err(kind)
end
isTest() = regex.Test("h.llo", "say hello") and not regex.Test("h.llo", "hllo")
isAnchors() = regex.Test("^ab$", "ab") and not regex.Test("^b", "ab") and not regex.Test("a$", "ab")
isStar() = regex.Test("^ab*c$", "ac") and regex.Test("^ab*c$", "abbbc")
isPlus() = regex.Test("^ab+$", "abb") and not regex.Test("^ab+$", "a")
isOptional() = regex.Test("^colou?r$", "color") and regex.Test("^colou?r$", "colour")
isAlternation() = regex.Test("^(cat|dog)$", "dog") and not regex.Test("^(cat|dog)$", "cow")
isClass() = regex.Test("^[a-c]+$", "abcab") and not regex.Test("^[a-c]+$", "abd")
isNegatedClass() = regex.Test("^[^0-9]+$", "abc") and not regex.Test("^[^0-9]+$", "a1")
isEscapes() = regex.Test("^\d+$", "123") and regex.Test("^\w+$", "a_1") and regex.Test("^\s$", " ") and not regex.Test("^\D$", "1")
isEscapedDot() = regex.Test("^a\.b$", "a.b") and not regex.Test("^a\.b$", "axb")
isCounts() = regex.Test("^a{2,3}$", "aa") and regex.Test("^a{2,3}$", "aaa") and not regex.Test("^a{2,3}$", "aaaa") and regex.Test("^a{2}$", "aa") and regex.Test("^a{2,}$", "aaaaa")
isWordBoundary() = regex.Test("\bcat\b", "a cat b") and not regex.Test("\bcat\b", "concat")
isAccents() = regex.Test("^.$", "é") and regex.Test("^[é]$", "é") and regex.Test("^[à-ÿ]+$", "éè")
isIgnoreCase() = regex.Test("(?i)^hello$", "HeLLo")
isFind() = regex.Find("b+", "aabbbc").Text == "bbb"
isFindPosition() = Equal([regex.Find("b+", "éabbc").Start, regex.Find("b+", "éabbc").Stop], [3, 4])
isFindNone() = IsMissing(regex.Find("z", "abc"))
isGroups() = Equal(regex.Find("(\d+)-(\d+)", "tel 12-34").Groups, ["12", "34"])
isGroupUnused() = Equal(regex.Find("(a)|(b)", "b").Groups, [missing, "b"])
isLazy() = regex.Find("a.*?b", "axbxb").Text == "axb"
isGreedy() = regex.Find("a.*b", "axbxb").Text == "axbxb"
isLeftmost() = regex.Find("b|abc", "abc").Text == "abc"
isNonCapturing() = Equal(regex.Find("(?:a)(b)", "ab").Groups, ["b"])
isFindAll() = Equal(Map(it.Text, regex.FindAll("\d+", "a1 b22 c333")), ["1", "22", "333"])
isFindAllEmpty() = Len(regex.FindAll("x*", "ab")) == 3
isReplace() = regex.Replace("\d+", "#", "a1 b22") == "a# b#"
isReplaceGroups() = regex.Replace("(\w+)@(\w+)", "$2 at $1", "me@home") == "home at me"
isReplaceWhole() = regex.Replace("a", "[$0]", "bab") == "b[a]b"
isSplit() = Equal(regex.Split(",\s*", "a, b,c"), ["a", "b", "c"])
isBadPattern() = All([fails(() -> regex.Test(p, "a"), "type") for p in ["(", ")", "[a", "a{2", "*", "\\", "a{3,2}"]])
isNoBlowup() = regex.Test("^(a+)+$", "$(Repeat(5000, "a"))!") == false
isManyCounts() = fails(() -> regex.Test("(a{1000}){1000}", "a"), "type")
isEmptyRepeatBomb() = fails(() -> regex.Test("(?:){1000}{1000}{1000}", "a"), "type") and fails(() -> regex.Test("a{0}{1000}{1000}{1000}", "a"), "type")
isTooManyGroups() = fails(() -> regex.Test("$(Repeat(2000, "()"))x", "a"), "type")
isClassTooLarge() = fails(() -> regex.Test("[$(Repeat(100000, "a"))]", "a"), "type")
