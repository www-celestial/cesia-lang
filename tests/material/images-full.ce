use sdl

defn check()
  w = sdl.Open("test", 320, 200, "../../examples/fonts/JetBrainsMono-Regular.ttf")?
  for k in 1:4097
    made = sdl.Image(1, 1, w)?
    w = made.Window
  end
  Ok("filled")
end

Print(check())
