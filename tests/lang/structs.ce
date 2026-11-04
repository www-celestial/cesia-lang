struct Car { M, K, C = 1500 }

isDefault() = Car(250, 16000).C == 1500
isNamed() = Car(250, K = 16000).K == 16000
isEqualityOrder() = Equal({X: 1, Y: 2}, {Y: 2, X: 1}) and {X: 1, Y: 2} == {Y: 2, X: 1}
isAddField() = adding().Y == 2
isFieldOfArray() = Equal([{A: 1}, {A: 2}].A, [1, 2])
isShownName() = Text(Car(1, 2)) == "Car(M = 1, K = 2, C = 1500)"
isFieldCount() = Len({A: 1, B: 2}) == 2

defn adding()
  s = {X: 1}
  s.Y = 2
  s
end

defn isDeepWriteStruct()
  s = {X: {Y: {Z: 1}}}
  s.X.Y.Z = 2
  Equal(s, {X: {Y: {Z: 2}}})
end

defn isDeepWriteArray()
  a = [[[1, 2]]]
  a[1][1][1] = 5
  a[1][1][2] = 6
  a[1][1][1] == 5 and a[1][1][2] == 6
end

defn isDeepWriteMixed()
  c = {P: {Q: [[1]]}}
  c.P.Q[1][1] = 2
  c.P.Q[1][1] == 2
end

defn isDeepWriteKeepsACopy()
  a = {X: {Y: {Z: 1}}}
  b = a
  b.X.Y.Z = 2
  a.X.Y.Z == 1 and b.X.Y.Z == 2
end

defn isFourLevels()
  a = {B: {C: {D: {E: 1}}}}
  a.B.C.D.E = 2
  a.B.C.D.E == 2 and Equal(a.B.C.D, {E: 2})
end

-- A truck on the road: the block form of a struct, one field per line.
--
--   Truck(1500).Speed --> 0.0
--   Truck(1, Speed = 2.0).Speed --> 2.0
struct Truck
  Mass

  -- Its speed.
  Speed = 0.0   -- metres per second
  Name = "a--b"
end

struct empty
end

Truck.Parked(mass) = Truck(mass, Name = "parked")
(t Truck) Momentum() = t.Mass * t.Speed

defn (t Truck) Faster(by = 1.0)
  t.Speed = t.Speed + by
  t
end

momentum(v) = match v
  Truck(m, s, n) -> m * s
  else -> -1
end

isBlockDefault() = Truck(1500).Speed == 0.0 and Truck(1500).Name == "a--b"
isBlockNamed() = Truck(1, Speed = 2.0).Speed == 2.0 and Truck(Speed = 3.0, Mass = 2).Mass == 2
isBlockShown() = Text(Truck(1)) == "Truck(Mass = 1, Speed = 0.0, Name = \"a--b\")"
isBlockEqual() = Truck(1) == Truck(1) and Truck(1) != Truck(2)
isBlockEmpty() = Text(empty()) == "empty()"
isBlockMethods() = Truck(2, 3.0).Momentum() == 6.0 and Truck.Parked(5).Name == "parked"
isBlockMethodWrites() = Truck(2).Faster().Faster(2.0).Speed == 3.0
isBlockMatch() = momentum(Truck(2, 4.0)) == 8.0 and momentum({Mass: 2, Speed: 4.0, Name: ""}) == -1
isBlockFieldWrite() = written().Speed == 9.0
isBlockDoc() = StartsWith("Truck { Mass, Speed = 0.0, Name = \"a--b\" }", Doc(Truck)) and Contains("A truck on the road", Doc(Truck))

defn written()
  t = Truck(1)
  t.Speed = 9.0
  t
end
