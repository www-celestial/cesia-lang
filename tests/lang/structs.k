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
