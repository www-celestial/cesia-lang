-- A second package with a Rect and a method Area.
struct Rect { Side }

-- Not the Area of geometry.
(r Rect) Area() = 100 * r.Side

-- The documentation of a method of this package, from here.
DocOfArea() = Doc("Rect.Area")
