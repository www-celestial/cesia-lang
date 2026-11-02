-- The documentation of the language, from the language: what an editor shows.
use num
use sys

-- Twice x, for the test of a function of this file.
--
--   Twice(2) --> 4
Twice(x) = 2 * x

defn Undocumented(a, b = 1)
  a + b
end

(** Two lines
    of documentation.
      Documented(1) --> 2 **)
Documented(x) = x + 1

(** On one line. *)
Short(x) = x

(* Not documentation.
hidden(x) = x *)
Plain(x) = x

isDocBlock() = StartsWith("Documented(x)", Doc(Documented)) and Contains("Two lines", Doc(Documented)) and Contains("of documentation.", Doc(Documented))
isDocBlockOnOneLine() = Contains("On one line.", Doc(Short))
isDocBlockKeepsNoMarks() = not Contains("(*", Doc(Documented)) and not Contains("*)", Doc(Documented)) and not Contains("*)", Doc(Short))
isDocPlainCommentIsNoDoc() = not Contains("Not documentation", Doc(Plain))

isDocOfAKeplerFunction() = Contains("One more", Doc("Inc")) and StartsWith("Inc(x)", Doc("Inc"))
isDocKeepsTheExamples() = Contains("Inc(1) --> 2", Doc("Inc"))
isDocOfADefn() = StartsWith("FindFirst(f, xs)", Doc("FindFirst"))
isDocOfAModuleFunction() = StartsWith("Solve(m, b)", Doc("num.Solve"))
isDocOfANative() = StartsWith("Sort(xs)", Doc("Sort"))
isDocOfAModuleNative() = StartsWith("sys.Now()", Doc("sys.Now"))
isDocOfAConstant() = StartsWith("Pi", Doc("Pi"))
isDocOfAValue() = Doc(Inc) == Doc("Inc") and Doc(Sort) == Doc("Sort") and Doc(num.Solve) == Doc("num.Solve")
isDocOfALocalFunction() = Contains("Twice x", Doc(Twice))
isDocWithoutAComment() = StartsWith("Undocumented(a, b = 1)", Doc(Undocumented)) and not Contains("\n", Doc(Undocumented))
isDocOfNothing() = IsMissing(Doc("NoSuchName")) and IsMissing(Doc("num.NoSuchName")) and IsMissing(Doc("no_such_module.X"))
isDocHidesPrivateNames() = IsMissing(Doc("runLength"))
isDocOfALambda() = IsMissing(Doc(x -> x))

isDocNamesOfTheModules() = "num" in DocNames() and "sys" in DocNames() and "prelude" in DocNames() and not ("natives" in DocNames())
isDocNamesOfThePrelude() = "Inc" in DocNames("prelude") and "Sort" in DocNames("prelude") and not ("runLength" in DocNames("prelude"))
isDocNamesOfAModule() = "num.Solve" in DocNames("num") and "sys.Now" in DocNames("sys")
isDocNamesOfNothing() = Equal(DocNames("no_such_module"), [])

-- A name without a comment shows only its signature, on one line.
defn undocumentedNames()
  out = []
  for m in DocNames()
    for name in DocNames(m)
      text = Doc(name)
      if IsMissing(text) or not Contains("\n", text)
        out = Append(name, out)
      end
    end
  end
  out
end

isEverythingPublicHasAComment() = Equal(undocumentedNames(), [])
