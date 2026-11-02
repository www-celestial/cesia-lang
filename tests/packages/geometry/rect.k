-- A rectangle: this file needs circle.k, which comes after it, and circle.k needs this file.
struct Rect { Width, Height, tag = "rect" }

-- The area, scaled by a small function of circle.k.
defn (r Rect) Area()
  scale(r.Width * r.Height)
end

half(x) = x / 2

-- Read through circle.k while this file's statements run.
seen = 5
early = readSeen()
