kepler doc Inc
echo "exit $?"
kepler doc NoSuchName
echo "exit $?"
kepler doc a b 2>&1 | head -1
kepler doc heap | head -2
kepler doc | head -1 | cut -c1-7
