use sdl

result = sdl.Open("test", 320, 200, "../../examples/fonts/JetBrainsMono-Regular.ttf")
Print(result then MapErr(it.Kind))
Print(result then MapErr(e -> Len(e.Message) > 0))
