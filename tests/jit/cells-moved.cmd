# Module numbers changed between runs of the loops that read them: the interpreter's answers, with machine code from
# hot loops and from the first run. Each number that moved is read from a slot once its first change made the code
# again: fewer units than the 22 changes, of which three of kind.
hot=$(CESIA_JIT=hot cesia run $no_spec cells-moved.ce 2>&1)
echo "$hot"
[ "$hot" = "$(CESIA_JIT=off cesia run $no_spec cells-moved.ce 2>&1)" ] && echo "the same with the JIT off"
[ "$hot" = "$(CESIA_JIT=always cesia run $no_spec cells-moved.ce 2>&1)" ] && echo "the same with machine code from the first run"
echo "fewer units than changes: $([ "$(CESIA_JIT_SHOW=1 cesia run cells-moved.ce 2>&1 > /dev/null | grep -c ': module$')" -lt 12 ] && echo true || echo false)"
