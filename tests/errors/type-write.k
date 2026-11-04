-- A write of the wrong type to a typed field, inside a path.
struct Point { X, Y }
struct Line { From Point, To Point }
struct Drawing { Lines }
d = Drawing([Line(Point(0, 0), Point(1, 1)), Line(Point(1, 1), Point(2, 2))])
d.Lines[2].From = Point(3, 3)
Print(d.Lines[2].From.X)
d.Lines[2].From = 3
