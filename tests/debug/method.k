struct Rect { Width }

defn (r Rect) Area()
  v = r.Width * 2
  v + 1
end

defn Rect.Unit()
  Rect(1)
end

r = Rect.Unit()
Print(r.Area())
