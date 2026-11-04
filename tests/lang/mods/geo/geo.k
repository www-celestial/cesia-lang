-- Interfaces and their methods, for the tests of a use.
use tests/lang/mods/far

-- Something measured by its area.
interface Measured { Area() }

interface sided
  Side()
end

-- Twice the area of what is measured.
(m Measured) Double() = 2 * m.Area()

-- What is measured, by geo.
(m Measured) Label() = "measured"

-- Half the area, and one.
(m Measured) Shown() = m.half() + 1

(m Measured) half() = m.Area() / 2

-- Four times the side.
(s sided) Sides() = 4 * s.Side()

-- A rectangle of geo.
struct Rect { Width, Height }

-- The area of a rectangle.
(r Rect) Area() = r.Width * r.Height

-- The width.
(r Rect) Side() = r.Width

-- A rectangle.
MakeRect(width, height) = Rect(width, height)

-- The area of what is measured.
Total(m Measured) = m.Area()

-- A method of an interface of far, which geo uses.
Extra(x) = x.Extra()
