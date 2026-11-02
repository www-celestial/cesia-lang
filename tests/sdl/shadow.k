use tests/sdl/probe
use sdl

white = 0xFFFFFF

defn check()
  w = sdl.Open("test", 320, 200, "../../examples/fonts/JetBrainsMono-Regular.ttf")?
  a = sdl.Draw([{Kind: "clear", Color: white}, {Kind: "shadow", X: 100, Y: 60, Width: 120, Height: 60, Alpha: 200}], w)
  image = probe.Pixels(a, 320, 200)
  Print(Mod(probe.Pixel(160, 124, image), 256) < 200)
  Print(probe.Pixel(20, 20, image) == white)
  Print(probe.Pixel(300, 180, image) == white)
  b = sdl.Draw([{Kind: "clear", Color: white}, {Kind: "shadow", X: 140, Y: 80, Width: 40, Height: 20, Alpha: 200}], a)
  small = probe.Pixels(b, 320, 200)
  Print(Abs(Mod(probe.Pixel(135, 90, small), 256) - Mod(probe.Pixel(184, 90, small), 256)) <= 8)
  Print(Mod(probe.Pixel(135, 90, small), 256) < 250)
  Print(Abs(Mod(probe.Pixel(160, 90, small), 256) - Mod(probe.Pixel(150, 90, small), 256)) <= 8)
  Print(Mod(probe.Pixel(160, 74, small), 256) >= Mod(probe.Pixel(160, 90, small), 256))
  Print(Abs(Mod(probe.Pixel(150, 90, small), 256) - Mod(probe.Pixel(170, 90, small), 256)) <= 4)
  c1 = sdl.Draw([{Kind: "clear", Color: white}, {Kind: "shadow", X: 140, Y: 80, Width: 0, Height: 20, Alpha: 200}], b)
  sdl.Frame([{Kind: "clear", Color: white}], c1)
  Print(sdl.Close(c1))
  Ok("closed")
end

Print(check())
