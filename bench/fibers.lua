-- COUNT coroutines park on one gate, then all end once it opens. Lua has coroutines and no scheduler: this is the loop.
local count = tonumber(arg[1])
local parked = {}
for i = 1, count do
  local co = coroutine.create(function() coroutine.yield() end)
  coroutine.resume(co)
  parked[i] = co
end
for i = 1, count do coroutine.resume(parked[i]) end
print(count)
