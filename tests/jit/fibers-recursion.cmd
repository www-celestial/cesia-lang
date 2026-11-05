# The interpreter, then native code from the first call.
echo "interpreted:"
CESIA_JIT=off cesia run fibers-recursion.ce
echo "native:"
CESIA_JIT=always cesia run fibers-recursion.ce
