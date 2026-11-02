use c

defn check()
  lib = c.Open("m", version = 6)?
  c.Fn("kepler_no_such_function", [], "void", lib)
end

Print(c.Open("kepler_no_such_library") then MapErr(it.Kind))
Print(c.Open("kepler_no_such_library") then MapErr(e -> e.Message then StartsWith("Can't load kepler_no_such_library: ")))
Print(check() then MapErr(it.Message))
