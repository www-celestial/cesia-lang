-- A value that doesn't meet the interface of a parameter.
interface Shape
  Area()
  Perimeter()
end

struct Rect { Width, Height }
(r Rect) Area() = r.Width * r.Height

defn Describe(s Shape)
  "area $(s.Area()), perimeter $(s.Perimeter())"
end

Print(Describe(Rect(1, 2)))
