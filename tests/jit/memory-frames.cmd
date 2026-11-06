# The interpreter, then native code from the first call: the same failure, at the same call, with the same trace.
echo "interpreted:"
CESIA_JIT=off cesia run --limit memory=500K memory-frames.ce
echo "native:"
CESIA_JIT=always cesia run --limit memory=500K memory-frames.ce
