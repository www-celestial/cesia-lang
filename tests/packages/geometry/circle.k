-- A circle, and what it adds to the rectangle of rect.k.
struct Circle { Radius }

scale(x) = 2 * x

-- Half the radius, with a small function of rect.k.
(c Circle) Half() = half(c.Radius)

-- A method in another file than its struct.
(r Rect) Perimeter() = 2 * (r.Width + r.Height)

-- A static method in another file than its struct.
Rect.Square(side) = Rect(side, side)

-- A small field declared in rect.k.
(r Rect) Tag() = r.tag

(r Rect) doubled() = r.Width * 2

-- A small method, called from this file.
(r Rect) Doubled() = r.doubled()

readSeen() = seen

-- What readSeen gave during the statements of rect.k.
Early() = early
