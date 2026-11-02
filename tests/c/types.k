use c

lib = Unwrap(c.Open(Args[1]))
bound(name, inputs, output) = Unwrap(c.Fn(name, inputs, output, lib))
echo(type) = bound("echo_$type", [type], type)

largest = 4611686018427387903
limits = [
  ["i8", -128, 127], ["u8", 0, 255], ["i16", -32768, 32767], ["u16", 0, 65535],
  ["i32", -2147483648, 2147483647], ["u32", 0, 4294967295], ["i64", -largest - 1, largest], ["u64", 0, largest]
]

for limit in limits
  f = echo(limit[1])
  Print(limit[1], f(limit[2]), f(limit[3]))
end

Print(echo("i32")(-1))
Print(echo("f32")(0.1))
Print(echo("f32")(2))
Print(echo("f64")(0.1))
Print(bound("float_mix", ["f32", "f64", "f32", "i32", "f64", "f32"], "f32")(0.5, 0.25, 1.5, 2, 3.0, 0.25))
Print(bound("text_constant", [], "text")())
Print(IsMissing(bound("text_null", [], "text")()))
Print(IsMissing(bound("ptr_null", [], "ptr")()))
Print(IsMissing(bound("nothing", [], "void")()))
Print(echo("bool")(true), echo("bool")(false))
Print(IsMissing(echo("ptr")(missing)))
