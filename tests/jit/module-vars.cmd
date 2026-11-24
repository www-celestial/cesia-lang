# Variables of a file's top that functions read, assigned in loops that machine code takes: the interpreter's prints with
# machine code from hot loops and from the first run, and units made for the loops.
hot=$(CESIA_JIT=hot cesia run $no_spec module-vars.ce 2>&1)
echo "$hot"
[ "$hot" = "$(CESIA_JIT=off cesia run $no_spec module-vars.ce 2>&1)" ] && echo "the same with the JIT off"
[ "$hot" = "$(CESIA_JIT=always cesia run $no_spec module-vars.ce 2>&1)" ] && echo "the same with machine code from the first run"
echo "units for the loops: $([ "$(CESIA_JIT_SHOW=1 cesia run module-vars.ce 2>&1 > /dev/null | grep -c ': module$')" -ge 8 ] && echo true || echo false)"
