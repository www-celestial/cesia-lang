# Fibers switch at checkpoints, which machine code keeps at the interpreter's steps: the same sums in each mode, though
# the top code changes k, of either kind, while the loops that read it wait there.
hot=$(CESIA_JIT=hot cesia run $no_spec fibers-moved.ce 2>&1)
echo "$hot"
[ "$hot" = "$(CESIA_JIT=off cesia run $no_spec fibers-moved.ce 2>&1)" ] && echo "the same with the JIT off"
[ "$hot" = "$(CESIA_JIT=always cesia run $no_spec fibers-moved.ce 2>&1)" ] && echo "the same with machine code from the first run"
