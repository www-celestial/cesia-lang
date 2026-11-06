cesia doc math.Inc
echo "exit $?"
cesia doc NoSuchName
echo "exit $?"
cesia doc a b 2>&1 | head -1
cesia doc std/heap | head -2
cesia doc | head -1 | cut -c1-7
