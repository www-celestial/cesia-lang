-- The interactions of the example, through its update function.
use sdl
use examples/scene as scene

fonts = "../../examples/fonts/"

defn opened()
  first = sdl.Open("test", 1280, 720, "$(fonts)AdwaitaSans-Regular.ttf", size = 13, light = true)?
  second = sdl.AddFont("strong", "$(fonts)NotoSans-Medium.ttf", 13, first, light = true)?
  third = sdl.AddFont("code", "$(fonts)JetBrainsMono-Regular.ttf", 13, second)?
  sdl.AddFont("large", "$(fonts)AdwaitaSans-Regular.ttf", 42, third, light = true)
end

mouse(action, x, y) = {Kind: "mouse", Action: action, X: x, Y: y, Button: 1, Amount: 0.0}

defn check()
  begun = scene.Start(opened()?)?
  s = begun.State
  Print(not scene.Moving(s))
  n = s.Nodes[4]
  s = scene.Update(mouse("down", n.X + 20, n.Y + 10), s)
  Print(s.Picked == 4)
  s = scene.Update(mouse("move", n.X + 60, n.Y - 30), s)
  Print(s.Nodes[4].X == n.X + 40 and s.Nodes[4].Y == n.Y - 40)
  s = scene.Update(mouse("up", n.X + 60, n.Y - 30), s)
  s = scene.Update(mouse("down", 1000, 500), s)
  Print(s.Picked == 0)
  s = scene.Update(mouse("up", 1000, 500), s)
  rough = scene.SliderRect(s.Rects.Details, 1)
  s = scene.Update(mouse("down", rough.X + rough.Width - 1, rough.Y + 5), s)
  Print(s.Rough > 0.9 and s.Dragging == 2)
  Print(scene.Moving(s))
  s = scene.Update(mouse("up", 0, 0), s)
  s = scene.Update({Kind: "tick", Seconds: 0.05}, s)
  Print(s.ShownRough > 0.32 and s.ShownRough < 1.0)
  for k in 1:10
    s = scene.Update({Kind: "tick", Seconds: 0.05}, s)
  end
  Print(not scene.Moving(s))
  s = scene.Update(mouse("down", 150, 200), s)
  s = scene.Update(mouse("move", 250, 200), s)
  Print(Abs(s.Light - 1.4) < 0.001 and s.Dragging == 3)
  s = scene.Update(mouse("up", 250, 200), s)
  s = scene.Update({Kind: "key", Key: "t"}, s)
  Print(not s.Dark)
  s = scene.Update({Kind: "resize", Width: 900, Height: 500}, s)
  Print(s.Rects.Graph.Width < 736 and s.Width == 900)
  s = scene.Update({Kind: "resize", Width: 40, Height: 30}, s)
  Print(Len(scene.View(s)) > 10)
  Print(IsMissing(scene.Update({Kind: "quit"}, s)))
  Print(sdl.Close(begun.Window))
  Ok("closed")
end

Print(check())
