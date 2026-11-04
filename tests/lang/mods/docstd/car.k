-- A car, for the test of kepler doc on the block form of a struct.
--
--   Car(1500).Speed --> 0.0
--   Car(1500, Speed = 2.0).Moved(3.0) --> 6.0
struct Car
  Mass Float

  -- Not a definition: Wheels(4) = 4
  Speed Float = 0.0   -- metres per second
  Name Text? = "a--b"
end

-- How far it goes in this time.
--
--   Car(1, 1.0).Moved(2.0) --> 2.0
(c Car) Moved(time Number) = c.Speed * time
