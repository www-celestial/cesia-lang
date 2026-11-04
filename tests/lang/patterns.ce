struct Car { M, K, C = 1500 }

mass(v) = match v
  Car(m, k, c) -> m
  else -> 0
end
isNamedPattern() = mass(Car(250, 16000)) == 250
isOtherStruct() = mass({M: 1, K: 2, C: 3}) == 0
isNestedPattern() = (match Ok(Ok(3))
  Ok(Ok(x)) -> x
  else -> 0
end) == 3
isFieldCount() = (match Ok(1)
  Ok(a, b) -> 1
  else -> 2
end) == 2
