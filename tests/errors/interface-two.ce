-- A method that two interfaces give to a value that meets both.
interface Shape { Area() }
interface Sized { Area() }
struct Rect { Side }
(r Rect) Area() = r.Side * r.Side
(s Shape) Info() = "shape"
(s Sized) Info() = "sized"
Print(Rect(1).Info())
