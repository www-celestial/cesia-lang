-- The cost of a call to a trivial C function, through LuaJIT's FFI: the loop of ccall.ce. LuaJIT only.
local ffi = require("ffi")
ffi.cdef("int abs(int);")
local n = 10000000
local start = os.clock()
for i = 1, n do ffi.C.abs(-5) end
print(string.format("calls per second: %d", math.floor(n / (os.clock() - start))))
