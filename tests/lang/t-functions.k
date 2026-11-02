defn total(a, b = 2)
  a + b
end
square(x) = x * x
f = x -> x + 1
g = defn (x, y) x + y end
Print(total(1), total(1, b = 5), total(b = 1, a = 2), square(3), f(1), g(1, 2))   -- 3 6 3 9 2 3
Print(before(1))                     -- 2, hoisted function
before(x) = x + 1

n = 1
add = x -> x + n
n = 2
Print(add(1))                       -- 2, captured at creation

fact(k) = if k < 2 1 else k * fact(k - 1) end
Print(fact(20))                     -- 2432902008176640000
count(k, acc) = if k == 0 acc else count(k - 1, acc + 1) end
Print(count(1000000, 0))            -- 1000000, without reaching depth
Print(total(g(1, 2), g(3, 4)))      -- 10, nested calls don't overwrite the arguments
