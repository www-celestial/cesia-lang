-- A rectangle: its example needs util.k.
struct Rect { Width, tag = "r" }

-- Twice the width.
--
--   Rect(2).Twice() --> 4
(r Rect) Twice() = double(r.Width)
