# The cost of a call to a trivial C function, through ctypes: the loop of ccall.ce.
import ctypes, time
libc = ctypes.CDLL("libc.so.6")
abs_value = libc.abs
abs_value.argtypes = [ctypes.c_int]
abs_value.restype = ctypes.c_int
n = 10000000
start = time.time()
for i in range(n):
    abs_value(-5)
print(f"calls per second: {int(n / (time.time() - start))}")
