use sdl

defn check()
  w = sdl.Open("test", 320, 200, "../../examples/fonts/JetBrainsMono-Regular.ttf")?
  sdl.Draw([{Kind: "text", X: 0, Y: 0, Text: "a", Color: 0, Font: "nope"}], w)
  Ok("drawn")
end

Print(check())
