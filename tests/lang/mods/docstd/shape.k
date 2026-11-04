-- Shapes, for the test of kepler doc on interfaces.

-- Something with an area and a perimeter.
--
--   total(Square(2)) --> 12
interface Shape
  Area()
  -- Not a definition: Wheels(4) = 4
Perimeter()
end

-- Something with a name.
interface Named { Name() }

-- A square.
struct Square { Side }

-- The area of a square.
(s Square) Area() = s.Side * s.Side

-- The perimeter of a square.
(s Square) Perimeter() = 4 * s.Side

-- What a shape is.
--
--   Square(1).Describe() --> "area 1, perimeter 4"
(s Shape) Describe() = "area $(s.Area()), perimeter $(s.Perimeter())"

total(s Shape) = s.Area() + s.Perimeter()
