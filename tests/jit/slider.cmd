# A slider's number set in place in a session (cells.Set): the machine code of the loop that reads it, a number of a
# cell of the session, reads it from a slot at each run, so it keeps its code for every next value: ten values of k make
# no unit more than the first run, not one each until the loop gives up. A set of another kind (an Int) makes it again.
# Each answer the same as with the JIT off. The time each cell took varies, and the byte that starts a message shows
# as @.
units() { CESIA_JIT_SHOW=1 cesia run --cells slider.ce < "$1" 2>&1 > /dev/null | grep -c ': module$'; }
answers() { CESIA_JIT=$1 cesia run $no_spec --cells slider.ce < slider-kinds.stdin | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' | tr '\001' '@'; }
once=$(units slider-once.stdin)
echo "ten values of k, no unit more: $([ "$(units slider-sets.stdin)" -eq "$once" ] && echo true || echo false)"
echo "an Int, a Float, an Int: three units more: $([ "$(units slider-kinds.stdin)" -eq $((once + 3)) ] && echo true || echo false)"
hot=$(answers hot)
echo "$hot"
[ "$hot" = "$(answers off)" ] && echo "the same with the JIT off"
[ "$hot" = "$(answers always)" ] && echo "the same with machine code from the first run"
