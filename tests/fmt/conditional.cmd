# The ifs that take no end, a if c else b and the guards return x if c and break if c, beside those that take one: a
# file in the style stays as it is, and runs.
cesia fmt --check conditional.ce
echo "check: $?"
cesia run conditional.ce
